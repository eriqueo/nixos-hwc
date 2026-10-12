"""Wall display: a TRMNL-compatible BYOS server for HWC's wall screens.

Devices speak the TRMNL BYOS protocol as observed in the TRMNL Android client
v2.14.0 (REA, 2026-10-12):
  GET  /api/setup/   header ID                      -> api_key for a known device
  GET  /api/display  headers ID, access-token (+RSSI, Percent-Charged)
                                                     -> next playlist image
  POST /api/log      device log lines -> journal
The client never reports its screen size, so each device's resolution, grey
depth and playlist come from the Nix config (index.nix → WALL_CONFIG).

Screens (screens.py) are HTML pages in the TRMNL framework, whose CSS, JS,
fonts and weather icons are served from the store at /framework/. A single
render worker screenshots each (screen, size, greys) with headless Chromium,
laid out at the device's CSS size and captured at its device scale, and
quantises it with ImageMagick into images/<screen>-<W>x<H>g<greys>-<hash>.png.
A device is served the last good image; a failed render keeps it and is
reported in /healthz.

The same pages are served as HTML at /<screen> for browser kiosks ("/" = week;
?device=<name> picks the layout, default the first declared device),
and /device/<name> is a web client: a browser shows that device's rotation as
images and reloads itself, which survives reboots where the TRMNL app cannot.
"""
import datetime as dt
import hashlib
import hmac
import ipaddress
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

import apps
import screens
import voice
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
ASSET_ROOT = os.path.realpath(os.path.join(screens.ASSETS, "framework"))
ASSET_TYPES = {".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
               ".woff2": "font/woff2", ".ttf": "font/ttf", ".svg": "image/svg+xml",
               ".txt": "text/plain; charset=utf-8", ".md": "text/plain; charset=utf-8",
               "": "text/plain; charset=utf-8"}  # licenses/LICENSE
# 2- and 4-grey renders draw text without antialiasing: antialiased glyph
# edges at fractional x dither into noise when quantised to 1-2 bits.
CRISP_ENV = {**os.environ, "FONTCONFIG_FILE": CONFIG["crispFontsConf"]}


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
    """One worker: every (screen, W, H, greys) any playlist needs. A target is
    drawn with the profile (scale, framework classes) of the first device
    that declares it."""

    def __init__(self):
        self.lock = threading.Lock()
        self.current = {}   # target -> filename
        self.status = {}    # target -> {"ok", "at", "error"}
        self.specs = {}     # target -> device spec
        for d in DEVICES.values():
            for s in d["playlist"]:
                self.specs.setdefault((s, d["width"], d["height"], d["grays"]), d)
        self.targets = sorted(self.specs)

    def render(self, target):
        screen, w, h, greys = target
        with self.lock:
            try:
                device = self.specs.get(target) or {"width": w, "height": h, "grays": greys}
                page = SCREENS[screen](dt.datetime.now(TZ), device)
                digest = hashlib.sha256(f"{w}x{h}g{greys}\n{page}".encode()).hexdigest()[:16]
                name = f"{screen}-{w}x{h}g{greys}-{digest}.png"
                path = os.path.join(IMAGES, name)
                if not os.path.exists(path):
                    self.screenshot(page, device, path)
                previous = self.current.get(target)
                self.current[target] = name
                self.prune(target, keep={name, previous})
                self.status[target] = {"ok": True, "at": time.time(), "error": None}
            except Exception as exc:  # keep serving the last good image
                self.status[target] = {"ok": False, "at": time.time(),
                                       "error": f"{type(exc).__name__}: {exc}"}
                log(f"render {screen} {w}x{h}g{greys} failed: {exc}")
            return self.current.get(target)

    def screenshot(self, page, device, out):
        """Lay the page out at the device's CSS size and capture it at its
        pixel size (Chromium's device scale factor), then quantise it to the
        device's greys. The page loads the framework from the store
        (screens.for_file); file:// fonts need file access from files."""
        css_w, css_h, _ = screens.profile(device)
        scale = float(device.get("scale") or 1)
        greys = device["grays"]
        with tempfile.TemporaryDirectory(dir=STATE) as tmp:
            src, raw = os.path.join(tmp, "page.html"), os.path.join(tmp, "raw.png")
            with open(src, "w") as f:
                f.write(screens.for_file(page))
            run([CONFIG["chromium"], "--headless=new", "--no-sandbox", "--disable-gpu",
                 "--hide-scrollbars", f"--force-device-scale-factor={scale:g}",
                 "--allow-file-access-from-files", "--virtual-time-budget=3000",
                 f"--user-data-dir={os.path.join(STATE, 'chromium')}",
                 f"--window-size={css_w},{css_h}", f"--screenshot={raw}", f"file://{src}"],
                env=CRISP_ENV if greys < 16 else None)
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


def run(cmd, env=None):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=RENDER_TIMEOUT, env=env)
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
        "voice": voice.status(),
    }
    ok = (voice.healthy()
          and all(v["ok"] for v in body["sources"].values())
          and all(v["ok"] for v in body["renders"].values())
          and all(v["age_s"] is None or v["age_s"] < STALE_DEVICE for v in body["devices"].values()))
    return ok, body


# Other faces of this server, chosen by the first label of the request host
# (todo.<vhostDomain> → HOST_APPS["todo"]). Each app is an object with
# get(handler, path) and post(handler, path); anything else is the wall face.
HOST_APPS = {}
HOST_APPS.update(apps.HOST_APPS)  # todo.* Tasks, calendar.* Calendar (apps.py)

TAILNET = ipaddress.ip_network("100.64.0.0/10")


class Handler(BaseHTTPRequestHandler):
    # Requests that change data must come from a tailnet device. Caddy sets
    # X-Real-IP to its {remote} ("ip:port", "[v6]:port"); the server binds
    # loopback only, so the header is Caddy's word, not the client's.
    def client_ip(self):
        raw = self.headers.get("X-Real-IP") or self.client_address[0]
        if raw.startswith("["):
            raw = raw[1:].partition("]")[0]
        elif raw.count(":") == 1:
            raw = raw.partition(":")[0]
        try:
            return ipaddress.ip_address(raw)
        except ValueError:
            return None

    def from_tailnet(self):
        ip = self.client_ip()
        return ip is not None and ip.version == 4 and ip in TAILNET

    def refuse_unless_tailnet(self):
        """True (and a 403 sent) when a data-changing request is not from the tailnet."""
        if self.from_tailnet():
            return False
        log(f"refused write from {self.client_ip()} to {self.headers.get('Host')}{self.path}")
        self.json(403, {"error": "changes are only accepted from tailnet devices"})
        return True

    def read_body(self, limit=1 << 20):
        length = int(self.headers.get("Content-Length") or 0)
        if length > limit:
            raise ValueError(f"body over {limit} bytes")
        return self.rfile.read(length)

    def host_app(self):
        host = self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or ""
        return HOST_APPS.get(host.split(".")[0].split(":")[0])

    def do_GET(self):
        path = self.path.split("?")[0]
        app = self.host_app()
        if app is not None:
            app.get(self, path)
        elif path in ("/api/setup", "/api/setup/"):
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
        elif path.startswith("/framework/"):
            self.serve_asset(path[len("/framework/"):])
        elif path.strip("/") in ("", *SCREENS):
            screen = path.strip("/") or "week"
            self.send(200, "text/html; charset=utf-8",
                      SCREENS[screen](dt.datetime.now(TZ), self.preview_device()))
        else:
            self.send(404, "text/plain", "not found")

    def do_POST(self):
        path = self.path.split("?")[0]
        app = self.host_app()
        if app is not None:
            app.post(self, path)
        elif path in POST_ROUTES:
            POST_ROUTES[path](self)
        else:
            self.send(404, "text/plain", "not found")

    def device_log(self):
        body = self.read_body(65536).decode(errors="replace")
        log(f"device log {self.headers.get('ID', '?')}: {body[:2000]}")
        self.json(200, {"status": 200})

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
        on their own after a reboot (the TRMNL Android app cannot).

        Touch: the left third links to ?go=prev (one screen back), the rest
        to the next screen. Plain links, no script, so any browser works."""
        device = devices.get(name)
        if device is None:
            return self.send(404, "text/plain", "unknown device")
        back = "go=prev" in self.path.partition("?")[2].split("&")
        with _devices_lock:
            if back:
                device.cursor -= 2  # the cursor already points past the screen on view
            target = device.next_target()
            device.seen = time.time()
            device.report = {"client": "web"}
        img = renderer.image(target)
        wait = device.spec["refreshRate"] if img else 60
        here = f"/device/{name}"
        body = (f'<img src="/images/{img}" alt="">' if img
                else "<p>No image rendered yet.</p>")
        # With voice on, a script reloads instead (it waits out a recording
        # or an answer on screen); the meta refresh stays for script-less browsers.
        refresh = f'<meta http-equiv="refresh" content="{wait};url={here}">'
        voice_head, voice_body = voice.client(here, wait)
        if voice_body:
            refresh, body = f"<noscript>{refresh}</noscript>{voice_head}", body + voice_body
        self.send(200, "text/html; charset=utf-8", f"""<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
{refresh}
<title>{name}</title>
<style>html,body{{margin:0;height:100%;background:#fff;overflow:hidden}}
img{{display:block;width:100vw;height:100vh;object-fit:contain}}
a{{position:fixed;top:0;bottom:0}}
.prev{{left:0;width:33vw}}.next{{left:33vw;right:0}}</style>
</head><body>{body}<a class="prev" href="{here}?go=prev" aria-label="previous"></a><a class="next" href="{here}" aria-label="next"></a></body></html>""")

    def serve_image(self, name):
        if not IMAGE_NAME.match(name):
            return self.send(404, "text/plain", "not found")
        try:
            with open(os.path.join(IMAGES, name), "rb") as f:
                data = f.read()
        except FileNotFoundError:
            return self.send(404, "text/plain", "not found")
        self.send(200, "image/png", data, cache="public, max-age=86400, immutable")

    def preview_device(self):
        """The device an HTML preview is laid out for: ?device=<name>, else
        the first declared device, else the Fire HD 8 profile."""
        query = dict(p.partition("=")[::2] for p in self.path.partition("?")[2].split("&") if p)
        if query.get("device") in DEVICES:
            return DEVICES[query["device"]]
        return next(iter(DEVICES.values()), screens.PREVIEW_DEVICE)

    def serve_asset(self, rel):
        """Framework CSS/JS/fonts, weather icons and their licenses, from the
        store path in the config (pages link them as framework/…)."""
        path = os.path.realpath(os.path.join(ASSET_ROOT, rel))
        ctype = ASSET_TYPES.get(os.path.splitext(path)[1])
        if ctype is None or not path.startswith(ASSET_ROOT + os.sep) or not os.path.isfile(path):
            return self.send(404, "text/plain", "not found")
        with open(path, "rb") as f:
            self.send(200, ctype, f.read(), cache="public, max-age=86400")

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


# POST paths of the wall face (other faces route through HOST_APPS).
POST_ROUTES = {"/api/log": Handler.device_log}
if voice.ENABLED:
    POST_ROUTES.update({"/voice": voice.handle_voice, "/voice/confirm": voice.handle_confirm})


def main():
    screens.password()  # refuse to start without a readable credential
    for d in DEVICES.values():
        unknown = [s for s in d["playlist"] if s not in SCREENS]
        if unknown or d["grays"] not in BITS:
            raise SystemExit(f"bad device config {d}: unknown screens {unknown} or grays not in {sorted(BITS)}")
    os.makedirs(IMAGES, exist_ok=True)
    threading.Thread(target=renderer.loop, daemon=True, name="render").start()
    voice.start()  # resident Piper, when voice is on
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
