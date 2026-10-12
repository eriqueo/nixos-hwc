"""Wall display: a TRMNL-compatible BYOS server for HWC's wall screens.

Devices speak the TRMNL BYOS protocol as observed in the TRMNL Android client
v2.14.0 (REA, 2026-10-12):
  GET  /api/setup/   header ID                      -> api_key for a known device
  GET  /api/display  headers ID, access-token (+RSSI, Percent-Charged)
                                                     -> next playlist image
  POST /api/log      device log lines -> journal
The client never reports its screen size, so each device's resolution, grey
depth and playlist come from the Nix config (index.nix → WALL_CONFIG).

Screens (screens.py) are HTML pages. A single render worker screenshots each
(screen, size, greys) with headless Chromium and quantises it with ImageMagick
into images/<screen>-<W>x<H>g<greys>-<hash>.png. A device is served the last
good image; a failed render keeps it and is reported in /healthz.

The same pages are served as HTML at /<screen> for browser kiosks ("/" = week),
and /device/<name> is a web client: a browser shows that device's rotation as
images and reloads itself, which survives reboots where the TRMNL app cannot.
"""
import datetime as dt
import hashlib
import hmac
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import screens
from screens import CONFIG, SCREENS, SOURCES, TZ

PORT = CONFIG["port"]
STATE = CONFIG["stateDir"]
IMAGES = os.path.join(STATE, "images")
KEYS_FILE = os.path.join(STATE, "keys.json")
DEVICES = CONFIG["devices"]
BY_ID = {d["id"]: name for name, d in DEVICES.items() if d.get("id")}  # web-only devices have no id
RENDER_EVERY = 60      # seconds between render passes
RENDER_TIMEOUT = 60    # per Chromium/ImageMagick call
STALE_DEVICE = 2400    # /healthz fails when a device that has called is silent this long
IMAGE_NAME = re.compile(r"^[a-z]+-\d+x\d+g\d+-[0-9a-f]{16}\.png$")
BITS = {2: 1, 4: 2, 16: 4}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


# ── device keys (StateDirectory, REPLACEABLE: re-run setup in the app) ──────

_keys_lock = threading.Lock()


def load_keys():
    try:
        with open(KEYS_FILE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def key_for(device_id):
    """The device's api_key, minted once and persisted atomically."""
    with _keys_lock:
        keys = load_keys()
        if device_id not in keys:
            keys[device_id] = secrets.token_urlsafe(24)
            tmp = KEYS_FILE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(keys, f)
            os.chmod(tmp, 0o600)
            os.replace(tmp, KEYS_FILE)
        return keys[device_id]


# ── rendering ───────────────────────────────────────────────────────────────

class Renderer:
    """One worker: every (screen, W, H, greys) any playlist needs."""

    def __init__(self):
        self.lock = threading.Lock()
        self.current = {}   # target -> filename
        self.status = {}    # target -> {"ok", "at", "error"}
        self.targets = sorted({(s, d["width"], d["height"], d["grays"])
                               for d in DEVICES.values() for s in d["playlist"]})

    def render(self, target):
        screen, w, h, greys = target
        with self.lock:
            try:
                page = SCREENS[screen](dt.datetime.now(TZ))
                digest = hashlib.sha256(f"{w}x{h}g{greys}\n{page}".encode()).hexdigest()[:16]
                name = f"{screen}-{w}x{h}g{greys}-{digest}.png"
                path = os.path.join(IMAGES, name)
                if not os.path.exists(path):
                    self.screenshot(page, w, h, greys, path)
                previous = self.current.get(target)
                self.current[target] = name
                self.prune(target, keep={name, previous})
                self.status[target] = {"ok": True, "at": time.time(), "error": None}
            except Exception as exc:  # keep serving the last good image
                self.status[target] = {"ok": False, "at": time.time(),
                                       "error": f"{type(exc).__name__}: {exc}"}
                log(f"render {screen} {w}x{h}g{greys} failed: {exc}")
            return self.current.get(target)

    def screenshot(self, page, w, h, greys, out):
        with tempfile.TemporaryDirectory(dir=STATE) as tmp:
            src, raw = os.path.join(tmp, "page.html"), os.path.join(tmp, "raw.png")
            with open(src, "w") as f:
                f.write(page)
            run([CONFIG["chromium"], "--headless=new", "--no-sandbox", "--disable-gpu",
                 "--hide-scrollbars", "--force-device-scale-factor=1",
                 f"--user-data-dir={os.path.join(STATE, 'chromium')}",
                 f"--window-size={w},{h}", f"--screenshot={raw}", f"file://{src}"])
            part = out + ".part"
            run([CONFIG["magick"], raw, "-colorspace", "Gray", "-dither", "FloydSteinberg",
                 "-posterize", str(greys), "-define", f"png:bit-depth={BITS[greys]}",
                 "-define", "png:color-type=0", f"png:{part}"])
            os.replace(part, out)

    def prune(self, target, keep):
        screen, w, h, greys = target
        prefix = f"{screen}-{w}x{h}g{greys}-"
        for name in os.listdir(IMAGES):
            if name.startswith(prefix) and name not in keep:
                os.remove(os.path.join(IMAGES, name))

    def image(self, target):
        """The current image for a target, rendering it now if none exists yet."""
        return self.current.get(target) or self.render(target)

    def loop(self):
        while True:
            for target in self.targets:
                self.render(target)
            time.sleep(RENDER_EVERY)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=RENDER_TIMEOUT)
    if r.returncode != 0:
        raise RuntimeError(f"{os.path.basename(cmd[0])} exited {r.returncode}: {r.stderr.strip()[-300:]}")


renderer = Renderer()


# ── devices ─────────────────────────────────────────────────────────────────

class Device:
    """Runtime state of one declared device: playlist cursor and last report."""

    def __init__(self, name, spec):
        self.name, self.spec = name, spec
        self.cursor, self.report = 0, {}
        self.seen: float | None = None

    def peek_target(self):
        playlist = self.spec["playlist"]
        screen = playlist[self.cursor % len(playlist)]
        return (screen, self.spec["width"], self.spec["height"], self.spec["grays"])

    def next_target(self):
        target = self.peek_target()
        self.cursor += 1
        return target


devices = {name: Device(name, spec) for name, spec in DEVICES.items()}
_devices_lock = threading.Lock()


def health():
    now = time.time()
    body = {
        "sources": {c.name: c.status() for c in SOURCES},
        "renders": {f"{s}-{w}x{h}g{g}": st for (s, w, h, g), st in renderer.status.items()},
        "devices": {d.name: {"id": d.spec.get("id"), "last_seen": d.seen,
                             "age_s": round(now - d.seen) if d.seen else None, **d.report}
                    for d in devices.values()},
    }
    ok = (all(v["ok"] for v in body["sources"].values())
          and all(v["ok"] for v in body["renders"].values())
          and all(v["age_s"] is None or v["age_s"] < STALE_DEVICE for v in body["devices"].values()))
    return ok, body


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/api/setup", "/api/setup/"):
            self.byos_setup()
        elif path == "/api/display":
            self.byos_display()
        elif path.startswith("/images/"):
            self.serve_image(path[len("/images/"):])
        elif path.startswith("/device/"):
            self.web_client(path[len("/device/"):].strip("/"))
        elif path == "/healthz":
            ok, body = health()
            self.send(200 if ok else 503, "application/json", json.dumps(body))
        elif path.strip("/") in ("", *SCREENS):
            screen = path.strip("/") or "week"
            self.send(200, "text/html; charset=utf-8", SCREENS[screen](dt.datetime.now(TZ)))
        else:
            self.send(404, "text/plain", "not found")

    def do_POST(self):
        if self.path.split("?")[0] == "/api/log":
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(min(length, 65536)).decode(errors="replace")
            log(f"device log {self.headers.get('ID', '?')}: {body[:2000]}")
            self.json(200, {"status": 200})
        else:
            self.send(404, "text/plain", "not found")

    # BYOS (names avoid BaseRequestHandler's own setup/handle hooks) ---------

    def byos_setup(self):
        device_id = self.headers.get("ID", "")
        name = BY_ID.get(device_id)
        if name is None:
            log(f"setup refused: unknown device ID {device_id!r} (declare it in hwc.server.services.wallDisplay.devices)")
            return self.json(404, {"status": 404, "api_key": None, "friendly_id": None,
                                   "image_url": None, "message": "Unknown device ID"})
        img = renderer.image(devices[name].peek_target())
        log(f"setup: {name} ({device_id})")
        self.json(200, {"status": 200, "api_key": key_for(device_id), "friendly_id": name,
                        "image_url": self.url(img) if img else None,
                        "message": f"Registered as {name}"})

    def byos_display(self):
        device_id = self.headers.get("ID", "")
        name = BY_ID.get(device_id)
        token = self.headers.get("access-token", "")
        if name is None or not hmac.compare_digest(token, load_keys().get(device_id, "\0")):
            log(f"display refused for ID {device_id!r}")
            return self.json(401, {"status": 401, "error": "Unknown device or token",
                                   "reset_firmware": False, "update_firmware": False})
        device = devices[name]
        with _devices_lock:
            target = device.next_target()
            device.seen = time.time()
            device.report = {k: self.headers.get(h) for k, h in
                             (("rssi", "RSSI"), ("battery", "Percent-Charged")) if self.headers.get(h)}
        img = renderer.image(target)
        if img is None:
            return self.json(200, {"status": 500, "error": "No image rendered yet",
                                   "refresh_rate": 60, "reset_firmware": False, "update_firmware": False})
        self.json(200, {"status": 0, "image_url": self.url(img), "filename": img,
                        "refresh_rate": device.spec["refreshRate"], "reset_firmware": False,
                        "update_firmware": False, "firmware_url": None, "special_function": "sleep"})

    # Web client ------------------------------------------------------------

    def web_client(self, name):
        """A browser acting as the device: each load shows the next playlist
        image and reloads after refreshRate. For kiosks that must come back
        on their own after a reboot (the TRMNL Android app cannot)."""
        device = devices.get(name)
        if device is None:
            return self.send(404, "text/plain", "unknown device")
        with _devices_lock:
            target = device.next_target()
            device.seen = time.time()
            device.report = {"client": "web"}
        img = renderer.image(target)
        wait = device.spec["refreshRate"] if img else 60
        body = (f'<img src="/images/{img}" alt="">' if img
                else "<p>No image rendered yet.</p>")
        self.send(200, "text/html; charset=utf-8", f"""<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="{wait}">
<title>{name}</title>
<style>html,body{{margin:0;height:100%;background:#fff;overflow:hidden}}
img{{display:block;width:100vw;height:100vh;object-fit:contain}}</style>
</head><body>{body}</body></html>""")

    def serve_image(self, name):
        if not IMAGE_NAME.match(name):
            return self.send(404, "text/plain", "not found")
        try:
            with open(os.path.join(IMAGES, name), "rb") as f:
                data = f.read()
        except FileNotFoundError:
            return self.send(404, "text/plain", "not found")
        self.send(200, "image/png", data, cache="public, max-age=86400, immutable")

    # plumbing --------------------------------------------------------------

    def url(self, name):
        """Absolute image URL as the device reached us (Caddy sets these)."""
        proto = self.headers.get("X-Forwarded-Proto", "http")
        host = self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or f"127.0.0.1:{PORT}"
        return f"{proto}://{host}/images/{name}"

    def json(self, code, body):
        self.send(code, "application/json", json.dumps(body))

    def send(self, code, ctype, body, cache="no-store"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        pass  # devices poll constantly; the journal keeps setup, refusals and failures


def main():
    screens.password()  # refuse to start without a readable credential
    for d in DEVICES.values():
        unknown = [s for s in d["playlist"] if s not in SCREENS]
        if unknown or d["grays"] not in BITS:
            raise SystemExit(f"bad device config {d}: unknown screens {unknown} or grays not in {sorted(BITS)}")
    os.makedirs(IMAGES, exist_ok=True)
    threading.Thread(target=renderer.loop, daemon=True, name="render").start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
