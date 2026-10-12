"""Wall calendar: one week of Radicale events and the NOAA forecast, drawn
for an e-ink look (black on white, no colour, no motion).

A stdlib HTTP server. Every request renders from an in-memory cache; the
calendar refreshes after CAL_TTL seconds and the forecast after WX_TTL. A
failed refresh keeps the last good copy and says so in the footer.
Configuration comes from WALL_* environment variables set by index.nix.
"""
import base64
import datetime as dt
import html
import json
import os
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

import icalendar

ENV = os.environ
PORT = int(ENV["WALL_PORT"])
RADICALE = ENV["WALL_RADICALE_URL"].rstrip("/")
CAL_USER = ENV["WALL_RADICALE_USER"]
HTPASSWD = ENV["WALL_HTPASSWD_FILE"]
POINT = ENV["WALL_NOAA_POINT"]  # "lat,lon"
PLACE = ENV.get("WALL_PLACE", "")
TZ = ZoneInfo(ENV["WALL_TZ"])
UA = ENV["WALL_USER_AGENT"]

DAYS = 7
CAL_TTL = 300
WX_TTL = 900
RETRY = 60
MAX_EVENTS = 9  # per day column; the rest collapse to "+N more"

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}

PROPFIND = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:displayname/><c:supported-calendar-component-set/></d:prop>
</d:propfind>"""

# Radicale expands recurrences server-side, so each instance arrives as its
# own VEVENT with a UTC start.
REPORT = """<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><c:calendar-data><c:expand start="{s}" end="{e}"/></c:calendar-data></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
    <c:time-range start="{s}" end="{e}"/>
  </c:comp-filter></c:comp-filter></c:filter>
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


def calendars():
    """Every collection under the principal that can hold events."""
    found = []
    for resp in dav(f"{RADICALE}/{CAL_USER}/", "PROPFIND", PROPFIND).findall("d:response", NS):
        comps = {c.get("name") for c in resp.iter(f"{{{NS['c']}}}comp")}
        if "VEVENT" in comps:
            href = resp.findtext("d:href", namespaces=NS)
            found.append((href, resp.findtext(".//d:displayname", namespaces=NS) or href))
    return found


def local(t):
    """A DTSTART/DTEND value as an aware local datetime, or a date if all-day."""
    if not isinstance(t, dt.datetime):
        return t
    return (t if t.tzinfo else t.replace(tzinfo=TZ)).astimezone(TZ)


def utc_stamp(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def load_events(first_day):
    start = dt.datetime.combine(first_day, dt.time(), TZ)
    end = start + dt.timedelta(days=DAYS)
    query = REPORT.format(s=utc_stamp(start), e=utc_stamp(end))
    cals, events, seen = calendars(), [], set()
    for href, name in cals:
        for data in dav(RADICALE + href, "REPORT", query).iter(f"{{{NS['c']}}}calendar-data"):
            if not data.text:
                continue
            for ev in icalendar.Calendar.from_ical(data.text).walk("VEVENT"):
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
                key = (summary.lower(), s)
                if key in seen:
                    continue
                seen.add(key)
                events.append({"summary": summary, "start": s, "end": e,
                               "allday": allday, "calendar": name})
    return {"calendars": [n for _, n in cals], "events": events}


_forecast_url = None


def load_weather():
    global _forecast_url
    geo = {"Accept": "application/geo+json"}
    if _forecast_url is None:
        point = json.loads(fetch(f"https://api.weather.gov/points/{POINT}", headers=geo))
        _forecast_url = point["properties"]["forecast"]
    periods = json.loads(fetch(_forecast_url, headers=geo))["properties"]["periods"]
    alerts = json.loads(fetch(f"https://api.weather.gov/alerts/active?point={POINT}",
                              headers=geo))["features"]
    days = {}
    for p in periods:
        day = dt.datetime.fromisoformat(p["startTime"]).astimezone(TZ).date()
        slot = days.setdefault(day, {})
        pop = (p.get("probabilityOfPrecipitation") or {}).get("value")
        if p["isDaytime"]:
            slot.update(hi=p["temperature"], sky=p["shortForecast"], pop=pop)
        else:
            slot["lo"] = p["temperature"]
            slot.setdefault("sky", p["shortForecast"])
            slot["pop"] = max(slot.get("pop") or 0, pop or 0) or None
    now = periods[0]
    return {
        "days": days,
        "now": f'{now["name"]} · {now["temperature"]}° · {now["shortForecast"]}'
               f' · {now["windDirection"]} {now["windSpeed"]}',
        "alerts": [a["properties"]["event"] + (": " + a["properties"]["headline"]
                   if a["properties"].get("headline") else "") for a in alerts],
    }


class Cached:
    """Last good value of a loader, refreshed when older than ttl."""

    def __init__(self, loader, ttl):
        self.loader, self.ttl = loader, ttl
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


calendar = Cached(load_events, CAL_TTL)
weather = Cached(load_weather, WX_TTL)


# ── rendering ───────────────────────────────────────────────────────────────

def clock(t):
    h, m = t.hour, t.minute
    return f"{h % 12 or 12}{f':{m:02d}' if m else ''}{'a' if h < 12 else 'p'}"


def on_day(ev, day):
    if ev["allday"]:
        return ev["start"] <= day < ev["end"]
    ds = dt.datetime.combine(day, dt.time(), TZ)
    de = ds + dt.timedelta(days=1)
    return ds <= ev["start"] < de or ev["start"] < ds < ev["end"]


def day_events(events, day):
    todays = [e for e in events if on_day(e, day)]
    todays.sort(key=lambda e: (not e["allday"],
                               e["start"] if not e["allday"] else dt.datetime.min.replace(tzinfo=TZ),
                               e["summary"]))
    items = []
    for e in todays:
        title = html.escape(e["summary"])
        if e["allday"]:
            items.append(f'<li class="allday">{title}</li>')
        else:
            when = clock(e["start"]) if e["start"].date() == day else "cont."
            items.append(f'<li><span class="t">{when}</span>{title}</li>')
    if len(items) > MAX_EVENTS:
        extra = len(items) - (MAX_EVENTS - 1)
        items = items[:MAX_EVENTS - 1] + [f'<li class="more">+{extra} more</li>']
    return "".join(items) or '<li class="none">—</li>'


def day_weather(wx, day):
    w = (wx or {}).get("days", {}).get(day) if wx else None
    if not w:
        return '<div class="wx"><div class="sky">no forecast</div></div>'
    hi = f'<span class="hi">{w["hi"]}°</span>' if "hi" in w else ""
    lo = f'<span class="lo">{w["lo"]}°</span>' if "lo" in w else ""
    pop = f'<div class="pop">{w["pop"]}% precip</div>' if (w.get("pop") or 0) >= 10 else ""
    return f'<div class="wx"><div>{hi}{lo}</div><div class="sky">{html.escape(w["sky"])}</div>{pop}</div>'


def stamp(c):
    return clock(dt.datetime.fromtimestamp(c.at, TZ)) if c.at else "never"


def render(now):
    today = now.date()
    cal = calendar.get(today)
    wx = weather.get()
    events = cal["events"] if cal else []

    columns = []
    for i in range(DAYS):
        day = today + dt.timedelta(days=i)
        columns.append(
            f'<section class="day{" today" if i == 0 else ""}">'
            f'<h2><span>{day:%a}</span><span class="dom">{day.day}</span></h2>'
            f'{day_weather(wx, day)}<ul class="events">{day_events(events, day)}</ul></section>')

    alerts = "".join(f'<div class="alert">{html.escape(a)}</div>' for a in (wx or {}).get("alerts", []))
    place = f"{html.escape(PLACE)} — " if PLACE else ""
    now_line = place + html.escape(wx["now"]) if wx else "forecast unavailable"
    notes = [f"calendar {stamp(calendar)}", f"forecast {stamp(weather)}"]
    errors = " · ".join(f"{n} failed: {html.escape(c.error)}"
                        for n, c in (("calendar", calendar), ("forecast", weather)) if c.error)

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="300">
<title>Week</title>
<style>{CSS}</style></head>
<body>
<header><div class="date">{now:%A} {today.day} {now:%B}</div><div class="now">{now_line}</div></header>
{alerts}
<main class="week">{"".join(columns)}</main>
<footer><span>{" · ".join(notes)}</span><span class="err">{errors}</span></footer>
</body></html>"""


# Black on white only: no colour, no grey fills, no shadows, no transitions.
CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:#fff;color:#000}
body{font-family:"Noto Serif",Georgia,serif;display:flex;flex-direction:column;padding:1.4vh 1.2vw}
header{display:flex;justify-content:space-between;align-items:baseline;gap:2vw;border-bottom:3px solid #000;padding-bottom:.8vh}
.date{font-size:4.6vh;font-weight:700;white-space:nowrap}
.now{font-size:2.4vh;text-align:right}
.alert{background:#000;color:#fff;font-size:2.2vh;font-weight:700;padding:.5vh .8vw;margin-top:.8vh}
.week{flex:1;display:grid;grid-template-columns:repeat(7,1fr);min-height:0;margin-top:1vh}
.day{border-right:1px solid #000;padding:0 .5vw;overflow:hidden;min-width:0}
.day:last-child{border-right:0}
.day h2{display:flex;justify-content:space-between;align-items:baseline;font-size:2.6vh;border-bottom:2px solid #000;padding:.3vh .4vw}
.today h2{background:#000;color:#fff}
.dom{font-size:3.4vh}
.wx{border-bottom:1px dotted #000;padding:.7vh 0;font-size:2vh;line-height:1.2}
.hi{font-size:3.8vh;font-weight:700}
.lo{font-size:2.6vh;margin-left:.5vw}
.sky{min-height:4.8vh}
.events{list-style:none;font-size:2.1vh;line-height:1.2}
.events li{padding:.5vh 0;border-bottom:1px dotted #000;overflow-wrap:anywhere}
.events .allday{font-weight:700;border:2px solid #000;padding:.3vh .3vw;margin:.5vh 0}
.t{font-weight:700;margin-right:.3em}
.none,.more{font-style:italic;border-bottom:0}
footer{display:flex;justify-content:space-between;gap:2vw;font-size:1.6vh;border-top:1px solid #000;padding-top:.5vh}
.err{font-weight:700;text-align:right}
"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self.send(200, "text/html; charset=utf-8", render(dt.datetime.now(TZ)))
        elif path == "/healthz":
            calendar.get(dt.datetime.now(TZ).date())
            weather.get()
            body = {n: {"ok": c.value is not None and c.error is None, "updated": c.at, "error": c.error}
                    for n, c in (("calendar", calendar), ("forecast", weather))}
            body["calendars"] = (calendar.value or {}).get("calendars", [])
            ok = all(v["ok"] for k, v in body.items() if k != "calendars")
            self.send(200 if ok else 503, "application/json", json.dumps(body))
        else:
            self.send(404, "text/plain", "not found")

    def send(self, code, ctype, body):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        pass  # the tablet reloads every five minutes; keep the journal for errors


if __name__ == "__main__":
    password()  # refuse to start without a readable credential
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
