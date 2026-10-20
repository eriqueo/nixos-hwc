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

The same pages are served as HTML at /<screen> for browser kiosks
(?device=<name> picks the layout, default the first declared device).
The root opens /review/<device>/<screen>, a fixed image preview with scene
navigation. Reviews leave device rotation and presence untouched.
And /device/<name> is a web client: a browser shows that device's rotation as
images and reloads itself, which survives reboots where the TRMNL app cannot.
"""
import base64
import datetime as dt
import hashlib
import html
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
import urllib.request
import urllib.error
from urllib.parse import quote, unquote, parse_qs
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


COOKING_PREFIX = "/cooking"
COOKING_PATH = re.compile(r"/cooking/(?:(?:api/|qr/)?(?:dates|dinners)/[a-zA-Z0-9_-]{1,100}|assets/(?:app\.js|app\.css|palette\.css|theme\.css))")
COOKING_CAPACITY = 16  # matches Meals admission; browser loads assets in parallel
COOKING_SLOTS = threading.BoundedSemaphore(COOKING_CAPACITY)  # shed excess reads with 503; no queue/retry
COOKING_LIMIT = 262144

class NoCookingRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

COOKING_HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoCookingRedirect())

# Wall destination labels and targets have one owner. Scene routes keep a
# chosen page fixed; the original /device/<name> remains the rotating entry.
WALL_DESTINATIONS = (("home", "Home"), ("tasks", "Tasks"), ("week", "Events"),
                     ("meals", "Meals"), ("month", "Month"))


def scene_url(name, scene):
    return f"/device/{quote(name, safe='')}/scenes/{quote(scene, safe='')}"


def wall_controls(name, scene, now):
    links = []
    for target, label in WALL_DESTINATIONS:
        if target == "meals":
            if not (CONFIG.get("meals") or {}).get("readUrl"):
                continue
            url = f"{COOKING_PREFIX}/dates/{now.date().isoformat()}?device={quote(name, safe='')}"
        else:
            if target not in DEVICES[name]["playlist"]:
                continue
            url = scene_url(name, target)
        current = ' aria-current="page"' if target == scene else ''
        links.append(f'<a href="{html.escape(url, quote=True)}"{current}>{label}</a>')
    phone = ''
    if scene == "meals":
        phone = (f'<span class="wall-phone"><img src="{COOKING_PREFIX}/qr/dates/{now.date().isoformat()}" '
                 'alt="Open Meals on your phone" width="96" height="96"><span>Open Meals<br>on your phone</span></span>')
    return '<nav class="wall-controls" aria-label="Wall pages">' + ''.join(links) + phone + '</nav>'


# Grayscale device surface, shared by the image client and cooking page.
WALL_CONTROL_CSS = """
.wall-controls{height:112px;box-sizing:border-box;display:flex;align-items:center;justify-content:center;gap:10px;padding:8px max(8px,env(safe-area-inset-right)) 8px max(8px,env(safe-area-inset-left));background:white;border-top:2px solid black;font:18px sans-serif;flex-wrap:wrap}
.wall-controls a{position:static;display:flex;align-items:center;justify-content:center;min-height:48px;padding:0 16px;border:2px solid black;border-radius:4px;color:black;text-decoration:none;box-sizing:border-box}
.wall-controls a[aria-current=page]{background:black;color:white}
.wall-phone{display:flex;align-items:center;gap:8px;font-size:14px}.wall-phone img{display:block;width:96px;height:96px}
.wall-controls a:focus-visible{outline:3px solid black;outline-offset:3px}
@media(max-width:600px){.wall-controls{gap:6px;font-size:16px}.wall-controls a{padding:0 9px}.wall-phone img{width:64px;height:64px}.wall-phone span{display:none}}
"""


COOKING_CONTROL_CSS = WALL_CONTROL_CSS + (
    '.wall-controls{position:fixed;bottom:0;left:0;right:0;z-index:20}'
    '.cooking-phone{display:none!important}body{padding-bottom:128px!important}'
    # A filter on body makes position:fixed relative to the scrolled body.
    # Keep grayscale on content so the footer stays attached to the viewport.
    'body.wall-cooking{filter:none}body.wall-cooking>.content{filter:grayscale(1)}')
# Hash only our fixed styles; keep arbitrary inline scripts/styles blocked.
COOKING_STYLE_HASHES = ' '.join("'sha256-" + base64.b64encode(hashlib.sha256(css.encode()).digest()).decode() + "'"
                              for css in (WALL_CONTROL_CSS, COOKING_CONTROL_CSS))


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
        self.wake = threading.Event()  # capacity one: changes coalesce while rendering
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
            self.wake.clear()
            for target in self.targets:
                self.render(target)
            self.wake.wait(RENDER_EVERY)

    def changed(self):
        screens.calendar.invalidate()
        screens.month_calendar.invalidate()
        screens.todo.invalidate()
        self.wake.set()


def run(cmd, env=None):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=RENDER_TIMEOUT, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"{os.path.basename(cmd[0])} exited {r.returncode}: {r.stderr.strip()[-300:]}")


def review_url(name, scene):
    return f"/review/{quote(name, safe='')}/{quote(scene, safe='')}"


def image_updates(name, scene):
    """One outstanding fetch, ten-second deadline; failures keep the last image.
    The fifteen-second next poll is the only retry. Scene rotation is unchanged."""
    url = f"/device/{quote(name, safe='')}/images/{quote(scene, safe='')}"
    return '''<script>
async function refreshSceneImage() {
  if (document.hidden) { setTimeout(refreshSceneImage, 15000); return; }
  const controller = new AbortController(), deadline = setTimeout(() => controller.abort(), 10000);
  try {
    const r = await fetch(URL, {cache: 'no-store', signal: controller.signal});
    if (r.ok) {
      const data = await r.json(), image = document.getElementById('scene-image');
      if (image && image.getAttribute('src') !== data.image) {
        await new Promise(resolve => {
          const candidate = new Image(), stop = setTimeout(() => { candidate.src = ''; resolve(); }, 10000);
          candidate.onload = () => { clearTimeout(stop); image.src = data.image; resolve(); };
          candidate.onerror = () => { clearTimeout(stop); resolve(); };
          candidate.src = data.image;
        });
      }
    }
  } catch (_) { /* keep the last good image until the next scheduled poll */ }
  finally { clearTimeout(deadline); setTimeout(refreshSceneImage, 15000); }
}
setTimeout(refreshSceneImage, 15000);
</script>'''.replace('URL', json.dumps(url), 1)


# HWC UI tokens vendored from scout/packages/ui/src/styles/{palette,theme}.css.
# HWC-EXCEPTION(Law 13): text-only token subset; remove when the wall server
# consumes a shared @scout/ui asset package. Scene images remain grayscale.
REVIEW_CSS = """
:root{color-scheme:dark;
--color-base-900:#1d2021;--color-base-800:#23282d;--color-base-700:#2a2f34;--color-base-600:#3a3f44;
--color-cream-100:#ebdbb2;--color-cream-200:#d5c4a1;--color-cream-300:#a7aaad;--color-copper:#cf995f;
--font-display:'Playfair Display',Georgia,serif;--font-body:'DM Sans',system-ui,sans-serif;
--surface-page:var(--color-base-800);--surface-card:var(--color-base-900);--surface-elevated:var(--color-base-700);
--text-heading:var(--color-cream-100);--text-body:var(--color-cream-200);--text-muted:var(--color-cream-300);
--interactive-accent:var(--color-copper);--border-default:var(--color-base-600);--border-accent:var(--color-copper)}
*{box-sizing:border-box}body{margin:0;background:var(--surface-page);color:var(--text-body);font:16px var(--font-body)}
header,main{max-width:1200px;margin:auto;padding:20px 24px}
header{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap}
h1{margin:0;font:28px var(--font-display);color:var(--text-heading)}h2{margin:0;font-size:20px;color:var(--text-heading)}
nav{display:flex;gap:8px;flex-wrap:wrap}a{display:inline-flex;align-items:center;justify-content:center;
min-height:44px;padding:10px 16px;border:1px solid var(--border-default);border-radius:6px;color:var(--text-body);text-decoration:none}
a:hover{background:var(--surface-elevated)}a[aria-current=page]{border-color:var(--border-accent);color:var(--interactive-accent)}
a:focus-visible{outline:2px solid var(--interactive-accent);outline-offset:3px}
.scene-heading{display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin:20px 0 12px;flex-wrap:wrap}
.scene-heading span,footer p{color:var(--text-muted);font-size:14px}
.preview{background:var(--surface-card);border:1px solid var(--border-default);overflow:hidden}
.preview img{display:block;width:100%;height:auto;max-height:calc(100vh - 300px);object-fit:contain}.preview p{padding:24px}
footer{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;margin-top:16px}
@media(max-width:600px){header,main{padding:16px}nav a{padding:10px 12px}}
"""


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
HOST_APPS.update(apps.host_apps(renderer.changed))  # notification bound at composition root

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
        elif path.startswith(COOKING_PREFIX + "/"):
            self.cooking_read(path)
        elif path in ("/api/setup", "/api/setup/"):
            self.byos_setup()
        elif path == "/api/display":
            self.byos_display()
        elif path.startswith("/images/"):
            self.serve_image(path[len("/images/"):])
        elif path.startswith("/device/"):
            address = path[len("/device/"):].rstrip("/").split("/")
            if len(address) == 3 and address[1] == "images":
                self.current_image(*map(unquote, (address[0], address[2])))
            elif len(address) == 3 and address[1] == "scenes":
                self.web_client(unquote(address[0]), unquote(address[2]))
            elif len(address) == 1:
                self.web_client(unquote(address[0]))
            else:
                self.send(404, "text/plain", "unknown device route")
        elif path == "/healthz":
            ok, body = health()
            self.send(200 if ok else 503, "application/json", json.dumps(body))
        elif path.startswith("/framework/"):
            self.serve_asset(path[len("/framework/"):])
        elif path in ("/", "/review", "/review/"):
            name = "ipad" if "ipad" in DEVICES else next(iter(DEVICES), None)
            if name is None:
                return self.send(503, "text/plain", "No display devices configured.")
            self.send_response(302)
            self.send_header("Location", review_url(name, DEVICES[name]["playlist"][0]))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif path.startswith("/review/"):
            self.review(path[len("/review/"):].split("/"))
        elif path.strip("/") in SCREENS:
            screen = path.strip("/")
            self.send(200, "text/html; charset=utf-8",
                      SCREENS[screen](dt.datetime.now(TZ), self.preview_device()))
        else:
            self.send(404, "text/plain", "not found")

    def cooking_unavailable(self, path):
        if path.startswith((COOKING_PREFIX + "/dates/", COOKING_PREFIX + "/dinners/")):
            device = parse_qs(self.path.partition("?")[2]).get("device", [""])[0]
            back = "/device/" + quote(device) if device in DEVICES else "/"
            controls = wall_controls(device, "meals", dt.datetime.now(TZ)) if device in DEVICES else ""
            return self.send(503, "text/html; charset=utf-8",
                '<!doctype html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
                f'<style>{WALL_CONTROL_CSS}</style></head><body>'
                '<h1>Meals is unavailable</h1><p>Your calendar and other wall pages still work.</p>'
                f'<p><a href="{back}">Back to wall</a></p><p><a href="{html.escape(self.path, quote=True)}">Try again</a></p>{controls}</body>')
        return self.json(503, {"error": {"code": "MEALS_UNAVAILABLE", "message": "Meals is unavailable. Your open recipe has been kept."}})

    def cooking_read(self, path):
        """GET-only transport substitution for Meals' cooking face; never a general proxy."""
        peer = self.client_ip()
        if peer is None or not (peer.is_loopback or self.from_tailnet() or peer in ipaddress.ip_network("fd7a:115c:a1e0::/48")):
            return self.json(403, {"error": {"code": "TAILNET_REQUIRED", "message": "Connect through Tailscale"}})
        if not COOKING_PATH.fullmatch(path):
            return self.json(404, {"error": {"code": "NOT_FOUND", "message": "Page not found"}})
        origin = (CONFIG.get("meals") or {}).get("readUrl")
        if not origin or not COOKING_SLOTS.acquire(False):
            return self.cooking_unavailable(path)
        try:
            try:
                response = COOKING_HTTP.open(origin + path, timeout=3)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                body = response.read(COOKING_LIMIT + 1)
                if len(body) > COOKING_LIMIT:
                    raise ValueError("cooking response limit")
                ctype = response.headers.get("Content-Type", "application/octet-stream")
                device = parse_qs(self.path.partition("?")[2]).get("device", [""])[0]
                if ctype.startswith("text/html") and device in DEVICES:
                    footer = wall_controls(device, "meals", dt.datetime.now(TZ))
                    body = body.decode("utf-8").replace('</head>', '<style>' + COOKING_CONTROL_CSS + '</style></head>', 1)
                    body = body.replace('</body>', footer + '</body>', 1).encode('utf-8')
                self.send(response.code, ctype, body)
        except (OSError, ValueError, urllib.error.URLError):
            self.cooking_unavailable(path)
        finally:
            COOKING_SLOTS.release()

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

    def review(self, address):
        """A fixed scene using the tablet's image, without touching its cursor."""
        if len(address) != 2:
            return self.send(404, "text/plain", "unknown preview")
        name, scene = map(unquote, address)
        device = DEVICES.get(name)
        if device is None or scene not in device["playlist"]:
            return self.send(404, "text/plain", "unknown device or scene")
        playlist = device["playlist"]
        index = playlist.index(scene)
        here = review_url(name, scene)
        escape = html.escape

        def link(url, label, selected=False):
            current = ' aria-current="page"' if selected else ''
            return f'<a href="{escape(url, quote=True)}"{current}>{escape(label)}</a>'

        scene_links = ''.join(link(review_url(name, s), s.capitalize(), s == scene) for s in playlist)
        device_links = ''.join(link(review_url(n, scene if scene in d["playlist"] else d["playlist"][0]),
                                   n, n == name) for n, d in DEVICES.items())
        previous = review_url(name, playlist[(index - 1) % len(playlist)])
        following = review_url(name, playlist[(index + 1) % len(playlist)])
        image = renderer.image((scene, device["width"], device["height"], device["grays"]))
        preview = (f'<img id="scene-image" src="/images/{image}" width="{device["width"]}" height="{device["height"]}" '
                   f'alt="{escape(scene.capitalize())} scene on {escape(name)}">' if image else
                   '<p role="status">Scene image is not ready. Reload to try again.</p>')
        self.send(200 if image else 503, "text/html; charset=utf-8", f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(scene.capitalize())} · Wall Display</title><style>{REVIEW_CSS}</style></head>
<body><header><h1>Wall Display</h1><nav aria-label="Display">{device_links}</nav></header>
<main><nav aria-label="Scenes">{scene_links}</nav>{wall_controls(name, scene, dt.datetime.now(TZ))}
<div class="scene-heading"><h2>{escape(scene.capitalize())}</h2>
<span>{index + 1} of {len(playlist)} · {device["width"]} × {device["height"]}</span></div>
<div class="preview">{preview}</div>
<footer><nav aria-label="Scene controls">{link(previous, '← Previous')}{link(following, 'Next →')}
{link(here, 'Reload scene')}</nav><p>This preview stays on this scene.</p></footer>
</main>{image_updates(name, scene) if image else ''}</body></html>''')

    def current_image(self, name, scene):
        device = DEVICES.get(name)
        if device is None or scene not in device["playlist"]:
            return self.json(404, {"error": "unknown device or scene"})
        target = (scene, device["width"], device["height"], device["grays"])
        image = renderer.current.get(target)
        if image is None:
            return self.json(503, {"error": "scene image is not ready"})
        self.json(200, {"image": f"/images/{image}"})

    def web_client(self, name, scene=None):
        """A browser acting as the device: each load shows the next playlist
        image and reloads after refreshRate. For kiosks that must come back
        on their own after a reboot (the TRMNL Android app cannot).

        Touch: the left third selects the previous fixed scene, the rest
        selects the next. Fixed scenes refresh in place; the base route rotates."""
        device = devices.get(name)
        if device is None or (scene is not None and scene not in device.spec["playlist"]):
            return self.send(404, "text/plain", "unknown device or scene")
        back = "go=prev" in self.path.partition("?")[2].split("&")
        with _devices_lock:
            if back and scene is None:
                device.cursor -= 2  # the cursor already points past the screen on view
            target = ((scene, device.spec["width"], device.spec["height"], device.spec["grays"])
                      if scene is not None else device.next_target())
            device.seen = time.time()
            device.report = {"client": "web"}
        img = renderer.image(target)
        wait = device.spec["refreshRate"] if img else 60
        here = scene_url(name, scene) if scene is not None else f"/device/{quote(name, safe='')}"
        controls = wall_controls(name, target[0], dt.datetime.now(TZ))
        playlist = device.spec["playlist"]
        index = playlist.index(target[0])
        previous = scene_url(name, playlist[(index - 1) % len(playlist)])
        following = scene_url(name, playlist[(index + 1) % len(playlist)])
        body = (f'<img id="scene-image" src="/images/{img}" alt="">' if img
                else "<p>No image rendered yet.</p>")
        # With voice on, a script reloads instead (it waits out a recording
        # or an answer on screen); the meta refresh stays for script-less browsers.
        refresh = f'<meta http-equiv="refresh" content="{wait};url={here}">'
        voice_head, voice_body = voice.client(here, wait) if device.spec["voice"] else ("", "")
        if voice_body:
            refresh, body = f"<noscript>{refresh}</noscript>{voice_head}", body + voice_body
        self.send(200, "text/html; charset=utf-8", f"""<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
{refresh}
<title>{name}</title>
<style>html,body{{margin:0;height:100%;background:#fff;overflow:hidden}}
#scene-image{{display:block;width:100vw;height:calc(100vh - 112px);object-fit:contain}}
.prev,.next{{position:fixed;top:0;bottom:112px}}
.prev{{left:0;width:33vw}}.next{{left:33vw;right:0}}
{WALL_CONTROL_CSS}
</style>
</head><body>{body}<a class="prev" href="{previous}" aria-label="previous"></a><a class="next" href="{following}" aria-label="next"></a>{controls}{image_updates(name, target[0]) if img else ''}</body></html>""")

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
        if self.path.startswith(COOKING_PREFIX + "/"):
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", f"default-src 'self'; script-src 'self'; style-src 'self' {COOKING_STYLE_HASHES}; img-src 'self'; frame-ancestors 'none'")
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
