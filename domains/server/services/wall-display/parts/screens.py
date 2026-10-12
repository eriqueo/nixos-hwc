"""Screen producers for the wall display: each screen turns one data source
into a full HTML page drawn black on white (an e-ink look).

A screen is a function `html(now) -> str` registered in SCREENS. Pages size
themselves in vh/vw, so one page renders at any device resolution. Data is
cached here (Cached) so the HTML preview, the renderer and every device share
one fetch per source.
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
from zoneinfo import ZoneInfo

import icalendar

CONFIG = json.load(open(os.environ["WALL_CONFIG"]))
RADICALE = CONFIG["radicale"]["url"].rstrip("/")
CAL_USER = CONFIG["radicale"]["user"]
HTPASSWD = CONFIG["radicale"]["htpasswdFile"]
POINT = CONFIG["noaa"]["point"]  # "lat,lon"
PLACE = CONFIG["noaa"]["place"]
UA = CONFIG["noaa"]["userAgent"]
BRIEFING = CONFIG.get("briefingFile")
TZ = ZoneInfo(CONFIG["timeZone"])

DAYS = 7
CAL_TTL = 300
WX_TTL = 900
RETRY = 60
MAX_EVENTS = 9   # per day column; the rest collapse to "+N more"
MAX_ROWS = 14    # list screens (tasks, briefing)

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


def load_events(first_day):
    start = dt.datetime.combine(first_day, dt.time(), TZ)
    query = EVENT_REPORT.format(s=utc_stamp(start), e=utc_stamp(start + dt.timedelta(days=DAYS)))
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
            key = (summary.lower(), s)
            if key in seen:
                continue
            seen.add(key)
            events.append({"summary": summary, "start": s, "end": e,
                           "allday": allday, "calendar": name})
    return {"calendars": [n for _, n in cals], "events": events}


def load_tasks(today):
    """Open tasks due today or earlier, plus undated high-priority ones (iCal 1-4)."""
    tasks = []
    for href, name in collections("VTODO"):
        for t in components(href, TODO_REPORT, "VTODO"):
            if str(t.get("STATUS", "")).upper() in ("COMPLETED", "CANCELLED") or "COMPLETED" in t:
                continue
            due = local(t.decoded("DUE")) if "DUE" in t else None
            due_day = due.date() if isinstance(due, dt.datetime) else due
            prio = int(t.get("PRIORITY", 0) or 0)
            if due_day is not None and due_day > today:
                continue
            if due_day is None and not 1 <= prio <= 4:
                continue
            tasks.append({"summary": str(t.get("SUMMARY", "")).strip() or "(untitled)",
                          "due": due, "due_day": due_day, "list": name, "priority": prio})
    tasks.sort(key=lambda t: (t["due_day"] is None, t["due_day"] or today, t["priority"] or 9, t["summary"]))
    return tasks


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


calendar = Cached("calendar", load_events, CAL_TTL)
weather = Cached("forecast", load_weather, WX_TTL)
todo = Cached("tasks", load_tasks, CAL_TTL)
briefing = Cached("briefing", load_briefing, CAL_TTL)
SOURCES = [calendar, weather, todo] + ([briefing] if BRIEFING else [])


# ── rendering ───────────────────────────────────────────────────────────────

def clock(t):
    h, m = t.hour, t.minute
    return f"{h % 12 or 12}{f':{m:02d}' if m else ''}{'a' if h < 12 else 'p'}"


def stamp(c):
    return clock(dt.datetime.fromtimestamp(c.at, TZ)) if c.at else "never"


def page(title, now, body, sources):
    notes = " · ".join(f"{c.name} {stamp(c)}" for c in sources)
    errors = " · ".join(f"{c.name} failed: {html.escape(c.error)}" for c in sources if c.error)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="300">
<title>{html.escape(title)}</title>
<style>{CSS}</style></head>
<body>
{body}
<footer><span>{notes}</span><span class="err">{errors}</span></footer>
</body></html>"""


def header(now, right):
    return (f'<header><div class="date">{now:%A} {now.day} {now:%B}</div>'
            f'<div class="now">{right}</div></header>')


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
    return capped(items, MAX_EVENTS) or '<li class="none">—</li>'


def capped(items, limit):
    if len(items) > limit:
        extra = len(items) - (limit - 1)
        items = items[:limit - 1] + [f'<li class="more">+{extra} more</li>']
    return "".join(items)


def day_weather(wx, day):
    w = wx["days"].get(day) if wx else None
    if not w:
        return '<div class="wx"><div class="sky">no forecast</div></div>'
    hi = f'<span class="hi">{w["hi"]}°</span>' if "hi" in w else ""
    lo = f'<span class="lo">{w["lo"]}°</span>' if "lo" in w else ""
    pop = f'<div class="pop">{w["pop"]}% precip</div>' if (w.get("pop") or 0) >= 10 else ""
    return f'<div class="wx"><div>{hi}{lo}</div><div class="sky">{html.escape(w["sky"])}</div>{pop}</div>'


def now_line(wx):
    place = f"{html.escape(PLACE)} — " if PLACE else ""
    return place + html.escape(wx["now"]) if wx else "forecast unavailable"


def week(now):
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
    body = f'{header(now, now_line(wx))}{alerts}<main class="week">{"".join(columns)}</main>'
    return page("Week", now, body, [calendar, weather])


def tasks(now):
    today = now.date()
    items = todo.get(today) or []
    rows = []
    for t in items:
        if t["due_day"] is None:
            when = "priority"
        elif t["due_day"] < today:
            n = (today - t["due_day"]).days
            when = f"{n}d overdue"
        elif isinstance(t["due"], dt.datetime):
            when = clock(t["due"])
        else:
            when = "today"
        cls = "late" if t["due_day"] is not None and t["due_day"] < today else ""
        rows.append(f'<li class="{cls}"><span class="t">{when}</span><span class="title">{html.escape(t["summary"])}</span>'
                    f'<span class="tag">{html.escape(t["list"])}</span></li>')
    body = (f'{header(now, "Tasks — due today and overdue")}'
            f'<main class="list"><ul class="rows">{capped(rows, MAX_ROWS) or "<li class=none>Nothing due.</li>"}</ul></main>')
    return page("Tasks", now, body, [todo])


SEVERITY = {"red": "late", "amber": "", "green": ""}


def brief(now):
    b = briefing.get(now.date()) if BRIEFING else None
    rows = []
    for i in (b or {}).get("items", []):
        title = html.escape(i.get("title", "").splitlines()[0][:140])
        why = html.escape(i.get("why") or "")
        rows.append(f'<li class="{SEVERITY.get(i.get("severity"), "")}"><span class="title">{title}</span>'
                    f'<span class="tag">{why}</span></li>')
    when = ""
    if b and b.get("generated_at"):
        when = "as of " + clock(dt.datetime.fromisoformat(b["generated_at"]).astimezone(TZ))
    body = (f'{header(now, "Morning briefing " + when)}'
            f'<main class="list"><ul class="rows">{capped(rows, MAX_ROWS) or "<li class=none>Nothing flagged.</li>"}</ul></main>')
    return page("Briefing", now, body, [briefing])


# The closed screen vocabulary: index.nix validates playlists against these
# names through the generated config, and the server serves nothing else.
SCREENS = {"week": week, "tasks": tasks, "briefing": brief}


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
.t{font-weight:700;margin-right:.6em}
.none,.more{font-style:italic;border-bottom:0}
.list{flex:1;min-height:0;overflow:hidden;margin-top:1.5vh}
.rows{list-style:none;font-size:3.4vh;line-height:1.25}
.rows li{display:flex;align-items:baseline;gap:1vw;padding:.9vh 0;border-bottom:1px dotted #000}
.rows .title{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.rows .late{font-weight:700}
.rows .t{min-width:16vw}
.tag{margin-left:auto;font-size:2.2vh;font-style:italic;white-space:nowrap;padding-left:2vw}
footer{display:flex;justify-content:space-between;gap:2vw;font-size:1.6vh;border-top:1px solid #000;padding-top:.5vh}
.err{font-weight:700;text-align:right}
"""
