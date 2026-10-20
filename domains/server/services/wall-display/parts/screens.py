"""Screen producers for the wall display: each screen turns cached data into
a full HTML page in the TRMNL framework's look (black, white and greys).

A screen is a function `html(now, device) -> str` registered in SCREENS.
`device` is a device spec from the config (width, height, grays, scale):
the page is laid out at width/scale x height/scale CSS pixels with the
framework's device classes for that grey depth (profile()), and the
renderer captures it at width x height. The framework CSS/JS/fonts and the
weather icons are local files under CONFIG["assets"]/framework, linked
relative to <base href="/">: the server serves them at /framework/, and
for_file() points a page at the store path for the file:// render. Nothing
is fetched from the network at render time.

Data is cached here (Cached) so the HTML preview, the renderer and every
device share one fetch per source.
"""
import calendar as month_grid
import base64
import datetime as dt
import html
import json
import os
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

import icalendar
import segno

CONFIG = json.load(open(os.environ["WALL_CONFIG"]))
RADICALE = CONFIG["radicale"]["url"].rstrip("/")
CAL_USER = CONFIG["radicale"]["user"]
HTPASSWD = CONFIG["radicale"]["htpasswdFile"]
POINT = CONFIG["noaa"]["point"]  # "lat,lon"
PLACE = CONFIG["noaa"]["place"]
UA = CONFIG["noaa"]["userAgent"]
BRIEFING = CONFIG.get("briefingFile")
TZ = ZoneInfo(CONFIG["timeZone"])
ASSETS = CONFIG["assets"]          # store path holding framework/
LINKS = CONFIG.get("links") or {}  # screen -> URL its QR code opens
TASK_LISTS = CONFIG["taskLists"]

DAYS = 7
CAL_TTL = 60
WX_TTL = 900
RETRY = 60

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}

PROPFIND = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:displayname/><c:supported-calendar-component-set/></d:prop>
</d:propfind>"""

# Radicale expands recurrences server-side, so each instance arrives as its
# own VEVENT with a UTC start.
EVENT_REPORT = """<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><c:calendar-data><c:expand start="{s}" end="{e}"/></c:calendar-data></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
    <c:time-range start="{s}" end="{e}"/>
  </c:comp-filter></c:comp-filter></c:filter>
</c:calendar-query>"""

TODO_REPORT = """<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VTODO"/></c:comp-filter></c:filter>
</c:calendar-query>"""


# ── fetching ────────────────────────────────────────────────────────────────

def password():
    with open(HTPASSWD) as f:
        for line in f:
            user, _, pw = line.rstrip("\n").partition(":")
            if user == CAL_USER:
                return pw
    raise RuntimeError(f"no {CAL_USER} entry in {HTPASSWD}")


def fetch(url, method="GET", body=None, headers=None, auth=False):
    req = urllib.request.Request(
        url, method=method, data=body.encode() if body else None,
        headers={"User-Agent": UA, **(headers or {})})
    if auth:
        token = base64.b64encode(f"{CAL_USER}:{password()}".encode()).decode()
        req.add_header("Authorization", f"Basic {token}")
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def dav(url, method, body):
    xml = fetch(url, method, body, {"Depth": "1", "Content-Type": "application/xml"}, auth=True)
    return ET.fromstring(xml)


def collections(component):
    """Every collection under the principal that can hold `component`."""
    found = []
    for resp in dav(f"{RADICALE}/{CAL_USER}/", "PROPFIND", PROPFIND).findall("d:response", NS):
        comps = {c.get("name") for c in resp.iter(f"{{{NS['c']}}}comp")}
        if component in comps:
            href = resp.findtext("d:href", namespaces=NS)
            found.append((href, resp.findtext(".//d:displayname", namespaces=NS) or href))
    return found


def components(href, query, kind):
    for data in dav(RADICALE + href, "REPORT", query).iter(f"{{{NS['c']}}}calendar-data"):
        if data.text:
            yield from icalendar.Calendar.from_ical(data.text).walk(kind)


def local(t):
    """An iCal date-time as an aware local datetime, or a date if all-day."""
    if not isinstance(t, dt.datetime):
        return t
    return (t if t.tzinfo else t.replace(tzinfo=TZ)).astimezone(TZ)


def utc_stamp(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def day_of(t):
    return t.date() if isinstance(t, dt.datetime) else t


def managed_meal(href, ev):
    meal = CONFIG.get("meals") or {}
    uid = str(ev.get("UID", ""))
    return href == meal.get("href") and uid.startswith("meal-dinner-") and str(ev.get("X-HWC-MEAL-SCHEMA", "")) == "1"


def dinner_row(events, day):
    meals = [e for e in events_on(events, day) if e.get("meal")]
    if not meals:
        return ""
    return '<div class="w-dinner"><span class="label label--small label--outline">Dinner</span>' + ''.join(
        f'<span class="title title--small w-c2">{E(e["summary"].removeprefix("Dinner: "))}</span>' for e in meals[:1]) + more(len(meals)-1) + '</div>'


def load_events(first_day):
    first, end = first_day if isinstance(first_day, tuple) else (first_day, first_day + dt.timedelta(days=DAYS))
    start = dt.datetime.combine(first, dt.time(), TZ)
    stop = dt.datetime.combine(end, dt.time(), TZ)
    query = EVENT_REPORT.format(s=utc_stamp(start), e=utc_stamp(stop))
    cals, events, seen = collections("VEVENT"), [], set()
    for href, name in cals:
        for ev in components(href, query, "VEVENT"):
            if str(ev.get("STATUS", "")).upper() == "CANCELLED":
                continue
            s = local(ev.decoded("DTSTART"))
            allday = not isinstance(s, dt.datetime)
            if "DTEND" in ev:
                e = local(ev.decoded("DTEND"))
            elif "DURATION" in ev:
                e = s + ev.decoded("DURATION")
            else:
                e = s + dt.timedelta(days=1) if allday else s
            summary = str(ev.get("SUMMARY", "")).strip() or "(busy)"
            # The mirrored feeds can carry the same event twice.
            key = (str(ev.get("UID")), s) if managed_meal(href, ev) else (summary.lower(), s)
            if key in seen:
                continue
            seen.add(key)
            events.append({"summary": summary, "start": s, "end": e,
                           "allday": allday, "calendar": name, "uid": str(ev.get("UID", "")), "meal": managed_meal(href, ev)})
    shown = drop_shadowed_busy(events, lambda e: e["summary"],
                               lambda e: (e["allday"], e["start"], e["end"]))
    return {"calendars": [n for _, n in cals], "events": shown}


# Titles a free/busy feed gives an event it will not describe. Proton work
# mirrors other calendars this way, so most of them shadow a real event.
PLACEHOLDERS = {"busy", "(busy)"}


def is_placeholder(summary):
    return (summary or "").strip().lower() in PLACEHOLDERS


def drop_shadowed_busy(events, summary, span):
    """Drop a placeholder "Busy" event that coincides with a titled event:
    the titled one already says what the time is for. A lone Busy stays.
    span(e) -> (group, start, end); two events coincide when they share a
    group and start together or overlap. The one rule for the screens and
    for voice (voice.dedupe_busy), which pass their own event shapes."""
    def coincide(a, b):
        (ga, sa, ea), (gb, sb, eb) = span(a), span(b)
        return ga == gb and (sa == sb or (sa < eb and sb < ea))

    titled = [e for e in events if not is_placeholder(summary(e))]
    return [e for e in events
            if not is_placeholder(summary(e)) or not any(coincide(e, t) for t in titled)]


def load_tasks(today):
    """Every open task across every Radicale task list ("open": dated first by
    due day, then undated; overdue first) and the ones completed today
    ("done", newest first)."""
    open_, done = [], []
    for href, name in collections("VTODO"):
        for t in components(href, TODO_REPORT, "VTODO"):
            status = str(t.get("STATUS", "")).upper()
            if status == "CANCELLED":
                continue
            summary = str(t.get("SUMMARY", "")).strip() or "(untitled)"
            if status == "COMPLETED" or "COMPLETED" in t:
                at = local(t.decoded("COMPLETED")) if "COMPLETED" in t else None
                if at is not None and day_of(at) == today:
                    done.append({"summary": summary, "list": name, "completed": at})
                continue
            due = local(t.decoded("DUE")) if "DUE" in t else None
            open_.append({"summary": summary, "due": due, "due_day": day_of(due),
                          "list": name, "priority": int(t.get("PRIORITY", 0) or 0)})
    open_.sort(key=lambda t: (t["due_day"] is None, t["due_day"] or today,
                              t["priority"] or 10, t["summary"].lower()))
    done.sort(key=lambda t: t["completed"] if isinstance(t["completed"], dt.datetime)
              else dt.datetime.combine(t["completed"], dt.time(), TZ), reverse=True)
    return {"open": open_, "done": done}


# api.weather.gov icon codes (…/icons/land/day/rain_showers,40/tsra,60) →
# Weather Icons glyphs (day, night).
ICONS = {
    "skc": ("wi-day-sunny", "wi-night-clear"),
    "few": ("wi-day-sunny-overcast", "wi-night-alt-partly-cloudy"),
    "sct": ("wi-day-cloudy", "wi-night-alt-cloudy"),
    "bkn": ("wi-cloudy", "wi-cloudy"),
    "ovc": ("wi-cloudy", "wi-cloudy"),
    "wind_skc": ("wi-day-windy", "wi-windy"),
    "wind_few": ("wi-day-windy", "wi-windy"),
    "wind_sct": ("wi-day-cloudy-windy", "wi-night-alt-cloudy-windy"),
    "wind_bkn": ("wi-cloudy-windy", "wi-cloudy-windy"),
    "wind_ovc": ("wi-cloudy-windy", "wi-cloudy-windy"),
    "snow": ("wi-day-snow", "wi-night-alt-snow"),
    "rain_snow": ("wi-day-rain-mix", "wi-night-alt-rain-mix"),
    "rain_sleet": ("wi-day-sleet", "wi-night-alt-sleet"),
    "snow_sleet": ("wi-day-sleet", "wi-night-alt-sleet"),
    "fzra": ("wi-rain-mix", "wi-rain-mix"),
    "rain_fzra": ("wi-rain-mix", "wi-rain-mix"),
    "snow_fzra": ("wi-rain-mix", "wi-rain-mix"),
    "sleet": ("wi-sleet", "wi-sleet"),
    "rain": ("wi-day-rain", "wi-night-alt-rain"),
    "rain_showers": ("wi-day-showers", "wi-night-alt-showers"),
    "rain_showers_hi": ("wi-day-showers", "wi-night-alt-showers"),
    "tsra": ("wi-day-thunderstorm", "wi-night-alt-thunderstorm"),
    "tsra_sct": ("wi-day-storm-showers", "wi-night-alt-storm-showers"),
    "tsra_hi": ("wi-day-storm-showers", "wi-night-alt-storm-showers"),
    "tornado": ("wi-tornado", "wi-tornado"),
    "hurricane": ("wi-hurricane", "wi-hurricane"),
    "tropical_storm": ("wi-hurricane", "wi-hurricane"),
    "dust": ("wi-dust", "wi-dust"),
    "smoke": ("wi-smoke", "wi-smoke"),
    "haze": ("wi-day-haze", "wi-night-fog"),
    "hot": ("wi-hot", "wi-hot"),
    "cold": ("wi-snowflake-cold", "wi-snowflake-cold"),
    "blizzard": ("wi-snow-wind", "wi-snow-wind"),
    "fog": ("wi-day-fog", "wi-night-fog"),
}


def noaa_icon(url):
    """The glyph for an api.weather.gov icon URL: its first (earliest) condition."""
    try:
        parts = url.split("/icons/", 1)[1].split("?")[0].split("/")
        night, code = parts[1] == "night", parts[2].split(",")[0]
    except (AttributeError, IndexError):
        return "wi-na"
    pair = ICONS.get(code)
    return pair[night] if pair else "wi-na"


_urls = None  # (forecast, hourly) for POINT


def load_weather():
    global _urls
    geo = {"Accept": "application/geo+json"}
    if _urls is None:
        point = json.loads(fetch(f"https://api.weather.gov/points/{POINT}", headers=geo))["properties"]
        _urls = (point["forecast"], point["forecastHourly"])
    periods = json.loads(fetch(_urls[0], headers=geo))["properties"]["periods"]
    alerts = json.loads(fetch(f"https://api.weather.gov/alerts/active?point={POINT}",
                              headers=geo))["features"]
    days = {}
    for p in periods:
        day = dt.datetime.fromisoformat(p["startTime"]).astimezone(TZ).date()
        slot = days.setdefault(day, {})
        pop = (p.get("probabilityOfPrecipitation") or {}).get("value")
        if p["isDaytime"]:
            slot.update(hi=p["temperature"], sky=p["shortForecast"], pop=pop,
                        icon=noaa_icon(p.get("icon")))
        else:
            slot["lo"] = p["temperature"]
            slot.setdefault("sky", p["shortForecast"])
            slot.setdefault("icon", noaa_icon(p.get("icon")))
            slot["pop"] = max(slot.get("pop") or 0, pop or 0) or None
    now = periods[0]
    return {
        "days": days,
        "now": f'{now["name"]} · {now["temperature"]}° · {now["shortForecast"]}'
               f' · {now["windDirection"]} {now["windSpeed"]}',
        "current": load_current(geo),
        "alerts": [alert_text(a["properties"]) for a in alerts],
    }


def alert_text(p):
    """"Dense Fog Advisory until Tue 12p": the event and when it ends."""
    ends = p.get("ends") or p.get("expires")
    if not ends:
        return p["event"]
    t = dt.datetime.fromisoformat(ends).astimezone(TZ)
    return f'{p["event"]} until {t:%a} {clock(t)}'


def load_current(geo):
    """This hour from the hourly forecast (temperature, humidity, precip,
    wind); None when that endpoint fails, so the daily data still shows."""
    try:
        hours = json.loads(fetch(_urls[1], headers=geo))["properties"]["periods"]
    except Exception:
        return None
    now = dt.datetime.now(TZ)
    pick = next((h for h in hours if dt.datetime.fromisoformat(h["startTime"]) <= now
                 < dt.datetime.fromisoformat(h["endTime"])), hours[0] if hours else None)
    if pick is None:
        return None
    return {
        "temp": pick["temperature"],
        "at": dt.datetime.fromisoformat(pick["startTime"]).astimezone(TZ),
        "sky": pick["shortForecast"],
        "icon": noaa_icon(pick.get("icon")),
        "humidity": (pick.get("relativeHumidity") or {}).get("value"),
        "pop": (pick.get("probabilityOfPrecipitation") or {}).get("value"),
        "wind": f'{pick.get("windDirection", "")} {pick.get("windSpeed", "")}'.strip(),
    }


def load_briefing(_day):
    """Allowlisted view of the morning briefing: its prioritised items minus
    mail (mail subjects stay off a wall screen). Keyed by day like the other
    loaders so a new day re-reads the file."""
    with open(BRIEFING) as f:
        b = json.load(f)
    items = [i for i in (b.get("sections", {}).get("today", {}).get("items") or [])
             if i.get("source") != "mail"]
    return {"generated_at": b.get("generated_at"), "items": items}


class Cached:
    """Last good value of a loader, refreshed when older than ttl or when the
    key (e.g. today's date) changes. A failed refresh keeps the last value."""

    def __init__(self, name, loader, ttl):
        self.name, self.loader, self.ttl = name, loader, ttl
        self.value, self.key, self.at, self.next_try, self.error = None, None, 0.0, 0.0, None
        self.lock = threading.Lock()

    def get(self, key=None):
        with self.lock:
            now = time.time()
            stale = self.value is None or key != self.key or now - self.at > self.ttl
            if stale and now >= self.next_try:
                try:
                    self.value = self.loader(key) if key is not None else self.loader()
                    self.key, self.at, self.error = key, now, None
                except Exception as exc:  # keep serving the last good copy
                    self.error = f"{type(exc).__name__}: {exc}"
                    self.next_try = now + RETRY
            return self.value

    def status(self):
        return {"ok": self.value is not None and self.error is None, "updated": self.at, "error": self.error}

    def invalidate(self):
        """A confirmed local write expires the cache, retaining its last good value."""
        with self.lock:
            self.at, self.next_try = 0.0, 0.0


calendar = Cached("calendar", load_events, CAL_TTL)
# Single-entry, rebuildable month cache; at most 42 days, using the same parser.
month_calendar = Cached("month calendar", load_events, CAL_TTL)
weather = Cached("forecast", load_weather, WX_TTL)
todo = Cached("tasks", load_tasks, CAL_TTL)
briefing = Cached("briefing", load_briefing, CAL_TTL)
# A source only used by an optional screen is not loaded without a render.
# Keep it out of health checks when no device rotates through that screen.
SOURCES = [calendar, weather, todo] + ([month_calendar] if any(
    "month" in d["playlist"] for d in CONFIG["devices"].values()) else []) + ([briefing] if BRIEFING and any(
    "briefing" in device["playlist"] for device in CONFIG["devices"].values()) else [])


# ── page frame: framework, device profile, shared pieces ────────────────────

BASE = '<base href="/">'
BIT_CLASS = {2: "screen--1bit", 4: "screen--2bit", 16: "screen--4bit"}
# /<screen> previews without a declared device: the Fire HD 8 profile.
PREVIEW_DEVICE = {"width": 1280, "height": 800, "grays": 16, "scale": 1.6}
ICON_DIR = os.path.join(ASSETS, "framework", "icons")
ICON_NAMES = {n[:-4] for n in os.listdir(ICON_DIR) if n.endswith(".svg")}


def profile(device):
    """(CSS width, CSS height, framework device classes) for a device spec.
    16 greys lays out as a TRMNL X ("v2", md); 2 and 4 greys as a TRMNL OG
    (sm). The framework needs a device class with its bit-depth class, or
    its views render blank. Its own --pixel-ratio is pinned to 1 in page():
    Chromium's device scale factor does the scaling instead."""
    scale = float(device.get("scale") or 1)
    w, h = round(device["width"] / scale), round(device["height"] / scale)
    model = "screen--v2 screen--md" if device["grays"] == 16 else "screen--og screen--sm"
    density = " screen--density-2x" if scale >= 1.5 else ""
    return w, h, f"{model} {BIT_CLASS[device['grays']]}{density}"


def for_file(page):
    """The page with its base pointed at the asset store path, for a
    file:// render by Chromium."""
    return page.replace(BASE, f'<base href="file://{ASSETS}/">', 1)


def clock(t):
    h, m = t.hour, t.minute
    return f"{h % 12 or 12}{f':{m:02d}' if m else ''}{'a' if h < 12 else 'p'}"


def stamp(c):
    return clock(dt.datetime.fromtimestamp(c.at, TZ)) if c.at else "never"


E = html.escape


def page(title, now, device, body, sources, instance=None):
    """A framework page: one full view, its layout and a title bar naming the
    screen, the sources' freshness and any source that failed."""
    w, h, classes = profile(device)
    failed = "".join(f'<span class="label label--small label--inverted">{E(c.name)} failed {stamp(c)}</span>'
                     for c in sources if c.error)
    errors = " · ".join(f"{c.name}: {c.error}" for c in sources if c.error)
    if instance is None:
        instance = ("updated " + stamp(sources[0]) if len(sources) == 1
                    else " · ".join(f"{c.name} {stamp(c)}" for c in sources))
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">{BASE}
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="300">
<title>{E(title)}</title>
<link rel="stylesheet" href="framework/plugins.css">
<script src="framework/plugins.js" defer></script>
<style>:root,.screen{{--screen-w:{w}px!important;--screen-h:{h}px!important;--pixel-ratio:1!important}}
{CSS}</style></head>
<body class="environment trmnl" data-errors="{E(errors)}">
<div class="screen screen--fonts-trmnl {classes}"><div class="view view--full">
<div class="layout w-fill">{body}</div>
<div class="title_bar"><span class="title">{E(title)}</span>{failed}<span class="instance">{E(instance)}</span></div>
</div></div></body></html>"""


def icon(name, cls=""):
    name = name if name in ICON_NAMES else "wi-na"
    return f'<img class="w-ico {cls}" src="framework/icons/{name}.svg" alt="">'


QR_CSS_PX = 96  # target QR edge on the 800-wide layout


def qr(screen, device, caption):
    """The screen's QR code (LINKS[screen]) as inline SVG, sized so every
    module is a whole number of device pixels (crisp at 1 bit), or ''."""
    url = LINKS.get(screen)
    if not url:
        return ""
    code = segno.make(url, error="m", micro=False)
    modules = code.symbol_size(border=0)[0]
    scale = float(device.get("scale") or 1)
    per = max(2, int(QR_CSS_PX * scale // modules))
    edge = modules * per / scale
    svg = code.svg_inline(border=0, omitsize=True, dark="#000", svgclass="w-qrsvg")
    return (f'<div class="w-qr"><div style="width:{edge:.3f}px;height:{edge:.3f}px">{svg}</div>'
            f'<span class="label label--small">{E(caption)}</span></div>')


def rail(screen, device, stats, caption):
    """Right-hand column: big counts, then the QR code with its caption."""
    cells = "".join(f'<div class="w-stat"><span class="value value--small value--tnums">{E(str(v))}</span>'
                    f'<span class="label label--small">{E(k)}</span></div>' for k, v in stats)
    return f'<div class="w-rail">{cells}<div class="w-grow"></div>{qr(screen, device, caption)}</div>'


def more(n):
    return f'<span class="label label--small label--outline w-more">+{n} more</span>' if n > 0 else ""


def none(text):
    return f'<span class="description w-none">{E(text)}</span>'


# ── events ──────────────────────────────────────────────────────────────────

def on_day(ev, day):
    if ev["allday"]:
        return ev["start"] <= day < ev["end"]
    ds = dt.datetime.combine(day, dt.time(), TZ)
    de = ds + dt.timedelta(days=1)
    return ds <= ev["start"] < de or ev["start"] < ds < ev["end"]


def events_on(events, day):
    todays = [e for e in events if on_day(e, day)]
    todays.sort(key=lambda e: (not e["allday"],
                               e["start"] if not e["allday"] else dt.datetime.min.replace(tzinfo=TZ),
                               e["summary"]))
    return todays


def event_rows(evs, day, limit, clamp=2):
    rows = []
    for e in evs[:limit]:
        if e["allday"]:
            when, cls = "all day", "label--inverted"
        else:
            when, cls = (clock(e["start"]) if e["start"].date() == day else "cont."), "label--outline"
        rows.append(f'<div class="w-ev"><span class="label label--small {cls}">{when}</span>'
                    f'<span class="description w-c{clamp}">{E(e["summary"])}</span></div>')
    return "".join(rows) + more(len(evs) - limit)


def agenda_row(e, day, past=False):
    """One event as a single line: time chip, then the title (home screen).
    A past event is struck through, like a finished task."""
    if e["allday"]:
        when, cls = "all day", "label--inverted"
    else:
        when, cls = (clock(e["start"]) if e["start"].date() == day else "cont."), "label--outline"
    return (f'<div class="w-agenda{" w-past" if past else ""}"><span class="label {cls}">{when}</span>'
            f'<span class="title title--small w-c1">{E(e["summary"])}</span></div>')


def wx_day(wx, day):
    return (wx or {}).get("days", {}).get(day) or {}


def deg(v):
    return f"{v}°" if v is not None else "–"


def hi_lo(w):
    return f'{deg(w.get("hi"))} / {deg(w.get("lo"))}'


def alert_bar(wx, limit=1, clamp=1):
    alerts = (wx or {}).get("alerts", [])[:limit]
    return "".join(f'<div class="w-alert w-c{clamp}">{E(a)}</div>' for a in alerts)


# ── tasks ───────────────────────────────────────────────────────────────────

def due_chip(t, today):
    """(text, label class) for a task's due day; (None, None) when undated."""
    d = t["due_day"]
    if d is None:
        return None, None
    if d < today:
        n = (today - d).days
        return ("yesterday" if n == 1 else f"{n} days ago"), "label--inverted"
    if d == today:
        return (clock(t["due"]) if isinstance(t["due"], dt.datetime) else "today"), "label--inverted"
    if (d - today).days == 1:
        return "tomorrow", "label--outline"
    if (d - today).days < 7:
        return f"{d:%a}", "label--outline"
    return f"{d:%b} {d.day}", "label--outline"


def task_row(t, today, clamp=2):
    text, cls = due_chip(t, today)
    chip = f'<span class="label label--small {cls}">{E(text)}</span>' if text else ""
    prio = '<span class="label label--small label--outline">!</span>' if 1 <= t["priority"] <= 4 and not text else ""
    return (f'<div class="w-task"><span class="w-box"></span><div class="w-tbody">'
            f'<span class="title title--small w-c{clamp}">{E(t["summary"])}</span>'
            f'<div class="w-meta">{chip}{prio}<span class="description w-c1">{E(t["list"])}</span></div></div></div>')


def done_row(t):
    when = clock(t["completed"]) if isinstance(t["completed"], dt.datetime) else "today"
    return (f'<div class="w-task w-done"><span class="w-box w-checked"></span><div class="w-tbody">'
            f'<span class="title title--small w-c2">{E(t["summary"])}</span>'
            f'<div class="w-meta"><span class="description w-c1">{E(when)} · {E(t["list"])}</span></div></div></div>')


def top_tasks(open_, today, n=3):
    """Overdue first, then due today, then undated by priority (unset last),
    then the next dated ones."""
    due = [t for t in open_ if t["due_day"] is not None and t["due_day"] <= today]
    undated = sorted((t for t in open_ if t["due_day"] is None),
                     key=lambda t: (t["priority"] or 10, t["summary"].lower()))
    later = [t for t in open_ if t["due_day"] is not None and t["due_day"] > today]
    return (due + undated + later)[:n]


def column(heading, rows, total, limit, empty, extra=None):
    """A headed list: the heading, then `extra` (default: the count), then
    up to `limit` rows and "+N more"."""
    shown = "".join(rows[:limit]) or none(empty)
    if extra is None:
        extra = f'<span class="label label--small">{total}</span>'
    return (f'<div class="w-col"><div class="w-head"><span class="title">{E(heading)}</span>{extra}</div>'
            f'<div class="w-list">{shown}{more(total - limit)}</div></div>')


# ── screens ─────────────────────────────────────────────────────────────────

def home(now, device):
    today = now.date()
    tomorrow = today + dt.timedelta(days=1)
    cal = calendar.get(today)
    wx = weather.get()
    tk = todo.get(today)
    events = cal["events"] if cal else []
    w = wx_day(wx, today)
    cur = (wx or {}).get("current") or {}
    pop = w.get("pop")

    # The big number is the temperature now, as on the weather screen; the
    # day's high and low sit under it (after dusk NOAA drops today's high).
    range_ = " · ".join(f"{k} {deg(w[k2])}" for k, k2 in (("high", "hi"), ("low", "lo")) if w.get(k2) is not None)
    weather_col = (
        f'<div class="w-col w-homewx">'
        f'<div class="w-head"><span class="title">{now:%A}</span><span class="label label--small">{now:%B} {now.day}</span></div>'
        f'<div class="w-wxrow">{icon(cur.get("icon") or w.get("icon") or "wi-na", "w-ico-home")}'
        f'<div class="w-stack"><span class="value value--xlarge value--tnums">{deg(cur.get("temp", w.get("hi")))}</span>'
        f'<span class="label">{range_}</span></div></div>'
        f'<span class="title title--small w-c2">{E(w.get("sky") or cur.get("sky") or "no forecast")}</span>'
        f'<div class="w-meta">'
        + (f'<span class="label label--small label--outline">{pop}% precip</span>' if pop else
           '<span class="label label--small label--outline">dry</span>')
        + f'</div>{alert_bar(wx, clamp=2)}</div>')

    # The whole day: finished events struck through above what is still to
    # come. When they do not all fit, the oldest finished ones give way.
    ordinary = [e for e in events if not e.get("meal")]
    todays = events_on(ordinary, today)
    upcoming = [e for e in todays if e["allday"] or e["end"] > now]
    past = [e for e in todays if e not in upcoming]
    today_limit = 5 if dinner_row(events, today) else 6
    tomorrow_limit = 5 if dinner_row(events, tomorrow) else 6
    keep = max(0, today_limit - len(upcoming))
    rows = ([agenda_row(e, today, past=True) for e in past[len(past) - keep:]] if keep else []) \
        + [agenda_row(e, today) for e in upcoming]
    later = events_on(ordinary, tomorrow)
    today_col = column(f"Today · {today:%b} {today.day}", rows, len(todays), today_limit, "Nothing today", extra="")
    tomorrow_col = column(f"Tomorrow · {tomorrow:%b} {tomorrow.day}", [agenda_row(e, tomorrow) for e in later], len(later), tomorrow_limit,
                          "Nothing scheduled",
                          extra=f'<span class="label label--small label--outline">{hi_lo(wx_day(wx, tomorrow))}</span>')

    today_col = today_col.replace('<div class="w-list">', '<div class="w-list">' + dinner_row(events, today), 1)
    tomorrow_col = tomorrow_col.replace('<div class="w-list">', '<div class="w-list">' + dinner_row(events, tomorrow), 1)

    family = [t for t in (tk or {}).get("open", []) if t["list"] == TASK_LISTS["family"]]
    top = top_tasks(family, today)
    late = sum(1 for t in family if t["due_day"] and t["due_day"] < today)
    cards = "".join(f'<div class="w-card">{task_row(t, today)}</div>' for t in top) or none("No tasks due today")
    tasks_strip = (f'<div class="w-strip w-grow"><div class="w-head"><span class="title">Family tasks</span>'
                   + (f'<span class="label label--small label--inverted">{late} overdue</span>' if late else "")
                   + f'</div><div class="w-cards">{cards}</div></div>')

    body = (f'<div class="w-row w-flex">{weather_col}{today_col}{tomorrow_col}</div>'
            f'<div class="w-row w-homebottom">{tasks_strip}{qr("home", device, "Add calendar event")}</div>')
    return page("Home", now, device, body, [calendar, weather, todo],
                instance=f"{PLACE} · {now:%a} {now.day} {now:%b}" if PLACE else None)


def week(now, device):
    today = now.date()
    cal = calendar.get(today)
    wx = weather.get()
    events = cal["events"] if cal else []
    # Two rows reserve enough height for larger, two-line event titles and
    # the overflow count, including the shorter Fire tablet profile.
    event_limit = 3 if profile(device)[1] >= 560 else 2
    cols = []
    for i in range(DAYS):
        day = today + dt.timedelta(days=i)
        w = wx_day(wx, day)
        pop = f'<span class="label label--small">{w["pop"]}%</span>' if (w.get("pop") or 0) >= 20 else ""
        dinner = dinner_row(events, day)
        evs = events_on([e for e in events if not e.get("meal")], day)
        cols.append(
            f'<div class="w-day{" w-today" if i == 0 else ""}">'
            f'<div class="w-dayhead"><span>{day:%a}</span><span>{day.day}</span></div>'
            f'<div class="w-daywx">{icon(w.get("icon", "wi-na"), "w-ico-s")}'
            f'<span class="label label--small value--tnums">{deg(w.get("hi"))}/{deg(w.get("lo"))}</span>{pop}</div>'
            f'<div class="w-list">{dinner}{event_rows(evs, day, max(1, event_limit - bool(dinner)), clamp=2) or ("" if dinner else none("—"))}</div></div>')
    cols.append(f'<div class="w-weekqr">{qr("week", device, "Add calendar event")}</div>')
    body = f'{alert_bar(wx)}<div class="w-week w-flex">{"".join(cols)}</div>'
    return page("Week", now, device, body, [calendar, weather],
                instance=(f"{PLACE} · " if PLACE else "") + ((wx or {}).get("now") or "forecast unavailable"))


def month_range(today):
    weeks = month_grid.Calendar(firstweekday=0).monthdatescalendar(today.year, today.month)
    return weeks[0][0], weeks[-1][-1] + dt.timedelta(days=1)


def month(now, device):
    today = now.date()
    first, end = month_range(today)
    data = month_calendar.get((first, end))
    events = (data or {}).get("events", [])
    rows = (end - first).days // 7
    cells = []
    # Keep text legible at six weeks on the shorter Fire profile.
    limit = 2 if rows <= 5 and profile(device)[1] >= 560 else 1
    for offset in range((end - first).days):
        day = first + dt.timedelta(days=offset)
        current = day == today
        label = ('Today, ' if current else '') + f'{day:%B} {day.day}'
        day_events = events_on(events, day)
        lines = []
        for ev in day_events[:limit]:
            when = '' if ev['allday'] else clock(ev['start']) + ' '
            lines.append(f'<div class="w-month-event w-c1">{E(when + ev["summary"])}</div>')
        cells.append(f'<div class="w-monthday{" w-outside" if day.month != today.month else ""}">'
                     f'<span class="w-monthdate{" w-current" if current else ""}" aria-label="{E(label)}">{day.day}</span>'
                     + ''.join(lines) + more(len(day_events) - limit) + '</div>')
    weekdays = ''.join(f'<span>{day}</span>' for day in ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'))
    body = (f'<div class="w-monthhead"><span class="title">{today:%B %Y}</span>'
            f'<span class="label label--small">Scan to add events on your phone</span></div>'
            f'<div class="w-row w-flex"><div class="w-monthwrap"><div class="w-weekdays">{weekdays}</div>'
            f'<div class="w-monthgrid" style="grid-template-rows:repeat({rows},minmax(0,1fr))">{"".join(cells)}</div></div>'
            f'{qr("month", device, "Add calendar event")}</div>')
    return page("Month", now, device, body, [month_calendar], instance=f'{today:%B %Y}')


def weather_screen(now, device):
    today = now.date()
    wx = weather.get()
    t = wx_day(wx, today)
    cur = (wx or {}).get("current") or {}
    temp = cur.get("temp", t.get("hi"))
    at = f'Now · {clock(cur["at"])}' if cur.get("at") else "Today"

    def stat(glyph, value, label):
        return (f'<div class="w-wxstat">{icon(glyph, "w-ico-m")}<div class="w-stack">'
                f'<span class="value value--xsmall value--tnums">{E(value)}</span>'
                f'<span class="label label--small">{E(label)}</span></div></div>')

    pop = cur.get("pop") if cur.get("pop") is not None else t.get("pop")
    stats = (stat("wi-thermometer", hi_lo(t), "High / Low")
             + stat("wi-humidity", f'{cur["humidity"]}%' if cur.get("humidity") is not None else "–", "Humidity")
             + stat("wi-umbrella", f"{pop or 0}%", "Precipitation")
             + stat("wi-strong-wind", cur.get("wind") or "–", "Wind"))
    top = (f'<div class="w-wxtop">'
           f'<div class="w-wxbig">{icon(cur.get("icon") or t.get("icon") or "wi-na", "w-ico-xl")}</div>'
           f'<div class="w-wxnow"><span class="value value--xxxlarge value--tnums">{deg(temp)}</span>'
           f'<span class="label">{E(at)}</span>'
           f'<span class="description w-c1">{E(cur.get("sky") or t.get("sky") or "")}</span></div>'
           f'<div class="w-wxstats">{stats}</div>{qr("weather", device, "Scan for forecast")}</div>')
    cards = []
    for i in range(1, 6):
        day = today + dt.timedelta(days=i)
        w = wx_day(wx, day)
        if not w:
            continue
        name = "Tomorrow" if i == 1 else f"{day:%A}"
        cards.append(f'<div class="w-wxcard"><span class="title title--small">{name}</span>'
                     f'{icon(w.get("icon", "wi-na"), "w-ico-l")}'
                     f'<span class="description w-c2 w-center">{E(w.get("sky", ""))}</span>'
                     f'<span class="value value--xsmall value--tnums">{hi_lo(w)}</span>'
                     f'<span class="w-pop">{icon("wi-raindrop", "w-ico-xs")}{w.get("pop") or 0}%</span></div>')
    body = (f'{top}{alert_bar(wx)}<div class="w-wxcards">{"".join(cards) or none("no forecast")}</div>')
    return page("Weather", now, device, body, [weather],
                instance=f"{PLACE} · NWS forecast · updated {stamp(weather)}" if PLACE else None)


def tasks(now, device):
    today = now.date()
    tk = todo.get(today) or {"open": [], "done": []}
    dated = [t for t in tk["open"] if t["due_day"] is not None]
    undated = sorted((t for t in tk["open"] if t["due_day"] is None),
                     key=lambda t: (t["priority"] or 10, t["summary"].lower()))
    late = sum(1 for t in dated if t["due_day"] < today)
    cols = (column("Deadlines", [task_row(t, today) for t in dated], len(dated), 6, "No deadlines",
                   extra=f'<span class="label label--small">{len(dated)}</span>'
                   + (f'<span class="label label--small label--inverted">{late} late</span>' if late else ""))
            + column("To-Dos", [task_row(t, today) for t in undated], len(undated), 6, "Nothing to do")
            + column("Finished", [done_row(t) for t in tk["done"]], len(tk["done"]), 6, "Nothing yet today"))
    body = (f'<div class="w-row w-flex"><div class="w-cols">{cols}</div>'
            f'{rail("tasks", device, [("Pending", len(tk["open"])), ("Done today", len(tk["done"]))], "Scan to manage")}</div>')
    return page("Tasks", now, device, body, [todo])


def groceries(now, device):
    tk = todo.get(now.date()) or {"open": []}
    items = [t for t in tk["open"] if t["list"] == TASK_LISTS["groceries"]]
    rows = ''.join(f'<div class="w-task"><span class="w-box"></span>'
                   f'<span class="title title--small w-c2">{E(t["summary"])}</span></div>' for t in items[:12])
    body = (f'<div class="w-row w-flex"><div class="w-col"><div class="w-head">'
            f'<span class="title">Grocery list</span></div><div class="w-groceries">'
            f'{rows or none("Nothing to buy")}</div>{more(len(items) - 12)}</div>'
            f'{rail("groceries", device, [("To buy", len(items))], "Add grocery items")}</div>')
    return page("Groceries", now, device, body, [todo])


SEVERITY = {"red": "label--inverted", "amber": "label--outline", "green": ""}
SEVERITY_TEXT = {"red": "urgent", "amber": "soon", "green": "fyi"}


def brief(now, device):
    b = briefing.get(now.date()) if BRIEFING else None
    items = (b or {}).get("items", [])
    rows = []
    for n, i in enumerate(items, 1):
        sev = i.get("severity")
        title = (i.get("title") or "").splitlines()[0][:160] if i.get("title") else ""
        chip = (f'<span class="label label--small {SEVERITY[sev]}">{SEVERITY_TEXT[sev]}</span>'
                if sev in SEVERITY else "")
        src = f'<span class="label label--small label--outline">{E(i["source"])}</span>' if i.get("source") else ""
        rows.append(f'<div class="w-brief"><span class="title w-num">{n}</span><div class="w-tbody">'
                    f'<span class="title w-c1">{E(title)}</span>'
                    f'<div class="w-meta">{chip}{src}<span class="description w-c1">{E(i.get("why") or "")}</span></div>'
                    f'</div></div>')
    limit = 6
    shown = "".join(rows[:limit]) or none("Nothing flagged.")
    when = ""
    if b and b.get("generated_at"):
        when = "as of " + clock(dt.datetime.fromisoformat(b["generated_at"]).astimezone(TZ))
    urgent = sum(1 for i in items if i.get("severity") == "red")
    body = (f'<div class="w-row w-flex"><div class="w-col w-wide"><div class="w-list">{shown}{more(len(rows) - limit)}</div></div>'
            f'{rail("briefing", device, [("Items", len(items)), ("Urgent", urgent)], "Scan for Workbench")}</div>')
    return page("Morning briefing", now, device, body, [briefing] if BRIEFING else [],
                instance=when or "no briefing yet")


# The closed screen vocabulary: index.nix validates playlists against these
# names through the generated config, and the server serves nothing else.
SCREENS = {"home": home, "week": week, "weather": weather_screen, "tasks": tasks,
           "groceries": groceries, "briefing": brief, "month": month}


# Layout on top of the framework: its type scale, labels and title bar do
# the look; these rules only place things. Black, white and the framework's
# greys; no motion.
CSS = """
.w-monthhead{display:flex;align-items:baseline;justify-content:space-between;gap:12px}
.w-monthwrap{display:flex;flex-direction:column;flex:1;min-width:0;min-height:0}
.w-weekdays,.w-monthgrid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr))}
.w-weekdays{text-align:center;font-weight:bold;flex:none}
.w-monthgrid{flex:1;min-height:0;border-top:1px solid #000;border-left:1px solid #000}
.w-monthday{min-height:0;min-width:0;overflow:hidden;border-right:1px solid #000;border-bottom:1px solid #000;padding:3px;display:flex;flex-direction:column;gap:2px}
.w-monthdate{font-weight:bold;align-self:flex-start;padding:0 4px}
.w-current{background:#000;color:#fff;border-radius:3px}
.w-outside{color:#666}
.w-month-event{font-size:12px;line-height:1.2}
.w-monthday .w-more{font-size:11px!important;line-height:1.1!important}

.w-dinner{display:flex;flex-direction:column;gap:2px;border-bottom:1px solid #000;padding-bottom:4px;flex:none}
.w-fill{display:flex!important;flex-direction:column!important;align-items:stretch!important;justify-content:flex-start!important;gap:8px;overflow:hidden}
.w-row{display:flex;gap:12px;min-height:0}
.w-flex{flex:1}
.w-grow{flex:1}
.w-col{flex:1;min-width:0;display:flex;flex-direction:column;gap:6px;overflow:hidden}
.w-wide{flex:1}
.w-head{display:flex;align-items:baseline;gap:6px;border-bottom:2px solid #000;padding-bottom:3px}
.w-head .title{margin-right:auto}
.w-list{display:flex;flex-direction:column;gap:6px;min-height:0;overflow:hidden}
.w-c1{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.w-c2,.w-c3{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.w-c3{-webkit-line-clamp:3}
.w-center{text-align:center}
.w-none{font-style:italic}
.w-more{align-self:flex-start}
.w-meta{display:flex;align-items:center;gap:5px;min-width:0}
.w-meta .label{flex:none}
.w-stack{display:flex;flex-direction:column;align-items:flex-start}
.w-ico{display:block;flex:none}
.w-ico-xs{width:16px;height:16px}.w-ico-s{width:24px;height:24px}.w-ico-m{width:34px;height:34px}
.w-ico-l{width:64px;height:64px}.w-ico-xl{width:132px;height:132px}
.w-agenda{display:flex;align-items:center;gap:8px;min-width:0}
.w-agenda .label{flex:none}
.w-past .title{text-decoration:line-through}
.w-qr .label{text-align:center}
.w-brief{padding-bottom:6px;border-bottom:1px solid #000}
.w-brief:last-child{border-bottom:0}
.w-alert{background:#000;color:#fff;font-weight:700;padding:3px 8px;border-radius:6px;flex:none}
.w-ev{display:flex;flex-direction:column;align-items:flex-start;gap:1px}
.w-rail{flex:none;width:112px;display:flex;flex-direction:column;align-items:center;gap:6px;border-left:2px solid #000;padding-left:10px}
.w-stat{display:flex;flex-direction:column;align-items:center}
.w-qr{display:flex;flex:none;flex-direction:column;align-items:center;gap:4px;width:112px}
.w-qrsvg{display:block;width:100%;height:100%;shape-rendering:crispEdges}
.w-week{min-width:0;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-template-rows:repeat(2,minmax(0,1fr));gap:12px}
.w-day{display:flex;flex-direction:column;gap:6px;min-width:0;overflow:hidden}
.w-day .description{font-size:17px!important;line-height:1.1!important}
.w-weekqr{display:flex;align-items:center;justify-content:center}
.w-groceries{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;align-content:start}
.w-homebottom{flex:none;align-items:flex-end}
.w-homebottom .w-strip{flex:1;min-width:0;overflow:hidden}
.w-homebottom .w-cards{gap:8px}
.w-homebottom .w-card{padding:5px}
.w-homebottom .w-meta{flex-wrap:wrap}
.w-homebottom .w-cards .description{display:none}
.w-homebottom .w-task .title{font-size:17px!important;line-height:1.1!important}
.w-head{flex-wrap:wrap}
.w-dayhead{display:flex;justify-content:space-between;align-items:baseline;border:2px solid #000;border-radius:6px;padding:1px 6px;font-weight:700}
.w-today .w-dayhead{background:#000;color:#fff}
.w-daywx{display:flex;align-items:center;gap:3px;flex-wrap:wrap;border-bottom:1px solid #000;padding-bottom:4px}
.w-task,.w-brief{display:flex;gap:7px;align-items:flex-start;min-width:0}
.w-tbody{display:flex;flex-direction:column;gap:2px;min-width:0;flex:1}
.w-box{flex:none;width:14px;height:14px;border:2px solid #000;border-radius:3px;margin-top:3px}
.w-checked{background:#000}
.w-done .title{text-decoration:line-through}
.w-num{flex:none;width:22px;text-align:right}
.w-cols{flex:1;min-width:0;display:flex;gap:14px}
.w-homewx{flex:0 0 236px}
.w-wxrow{display:flex;align-items:center;gap:10px}
.w-strip{flex:none;display:flex;flex-direction:column;gap:6px}
.w-cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
.w-card{border:2px solid #000;border-radius:8px;padding:6px 8px;min-width:0}
.w-wxtop{flex:none;display:grid;grid-template-columns:96px 180px minmax(0,1fr) 112px;align-items:center;gap:12px}
.w-wxbig{flex:none}
.w-wxnow{flex:none;display:flex;flex-direction:column;align-items:flex-start;border-left:2px solid #000;border-right:2px solid #000;padding:0 14px;max-width:230px}
.w-wxstats{flex:1;min-width:0;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px 8px}
.w-wxstat{display:flex;align-items:center;gap:6px;min-width:0}
.w-wxcards{flex:1;min-height:0;display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}
.w-wxcard{display:flex;flex-direction:column;align-items:center;justify-content:flex-start;gap:2px;border:2px solid #000;border-radius:8px;padding:5px 4px;min-width:0;overflow:hidden}
.w-wxcard{justify-content:space-evenly}
.w-wxcard .w-ico-l{width:60px;height:60px}
.w-wxcard .description{min-height:2.4em}
.w-wxstat .value{white-space:nowrap}
.w-ico-home{width:88px;height:88px}
.w-wxrow .value{white-space:nowrap}
.w-wxstat .w-stack{min-width:0}
.w-wxstat .value{white-space:normal;overflow-wrap:anywhere;font-size:22px!important;line-height:1.1!important}
.w-wxnow{width:180px;max-width:180px}
.w-wxnow .value{font-size:80px!important;line-height:1!important}
.w-wxtop .w-ico-xl{width:96px;height:96px}
.w-pop{display:flex;align-items:center;gap:3px;font-weight:700}
"""
