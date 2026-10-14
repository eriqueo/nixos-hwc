"""Phone apps of the wall-display server, chosen by request host (server.HOST_APPS):

  todo.<vhostDomain>      Tasks — every Radicale task list: add, complete,
                          reopen, edit summary/due/priority, delete.
  calendar.<vhostDomain>  Calendar — day/week/month agenda over every Radicale
                          event calendar; add, edit, delete on writable ones.

Reads go to Radicale over CalDAV through the screens.py helpers. Writes go
ONLY through the hwc-sys MCP gateway, called here server-side with a closed
(tool, action) allowlist (WRITE_TOOLS); the browser never reaches /mcp.

Every write must come from a tailnet address (Handler.refuse_unless_tailnet),
carry Content-Type application/json and, when the browser sends one, an Origin
on this host — so a page on another site cannot drive these endpoints through
a tailnet browser.

Calendar writes run through khal + vdirsyncer inside the gateway and reach
Radicale asynchronously, so a calendar write waits (SYNC_WAIT) until Radicale
shows the change and says plainly when it has not yet. The gateway's own
`edit` action is not used: it deletes the event before `khal new` runs without
a calendar, which fails on a host with no default_calendar and loses the
event. Edit here is a verified delete followed by a create on the chosen
calendar, restoring the old event if the create fails.
"""
import datetime as dt
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import screens
from screens import CONFIG, TZ

APPS = CONFIG.get("apps") or {}
GROCERY_PATH = APPS["paths"]["groceries"]
GATEWAY = APPS.get("gatewayUrl")  # None: no gateway on this host, apps are read-only
# Collection ids (/<user>/<id>/) mirrored from outside feeds — never written.
READ_ONLY = set(APPS.get("readOnlyCalendars") or [])

# The only gateway calls this module can make. None = a tool without actions.
WRITE_TOOLS = {
    "hwc_tasks_add": {None},
    "hwc_tasks_update": {"complete", "reopen", "edit", "delete"},
    # delete without confirm is the gateway's dry run: used to prove the
    # match is exactly the event the phone chose. sync runs vdirsyncer.
    "hwc_calendar": {"create", "delete", "sync"},
}
PROTOCOL = "2025-06-18"
GATEWAY_TIMEOUT = 60
SYNC_WAIT = 40       # seconds a calendar write waits for Radicale to show it
DONE_DAYS = 7        # completed tasks stay visible (to reopen) this long
BODY_LIMIT = 16384


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def now():
    return dt.datetime.now(TZ)


class Invalid(ValueError):
    """Bad input from the phone: 400 with this message."""


class GatewayError(RuntimeError):
    """The gateway refused or failed: 502 with this message."""


# ── gateway (Streamable HTTP JSON-RPC, one session per call) ────────────────

def _rpc(body, sid):
    headers = {"Content-Type": "application/json",
               "Accept": "application/json, text/event-stream",
               "MCP-Protocol-Version": PROTOCOL}
    if sid:
        headers["Mcp-Session-Id"] = sid
    req = urllib.request.Request(GATEWAY, data=json.dumps(body).encode(),
                                 headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=GATEWAY_TIMEOUT) as r:
            sid = r.headers.get("Mcp-Session-Id") or sid
            ctype = r.headers.get("Content-Type", "")
            raw = r.read().decode(errors="replace")
    except urllib.error.HTTPError as exc:
        raise GatewayError(f"gateway HTTP {exc.code}") from exc
    except OSError as exc:
        raise GatewayError(f"gateway unreachable: {exc}") from exc
    if "id" not in body:
        return None, sid
    msg = None
    if "text/event-stream" in ctype:
        for line in raw.splitlines():
            if line.startswith("data:"):
                try:
                    j = json.loads(line[5:].strip())
                except ValueError:
                    continue
                if isinstance(j, dict) and j.get("id") == body["id"]:
                    msg = j
    else:
        msg = json.loads(raw)
    if not msg:
        raise GatewayError(f"no gateway reply to {body['method']}")
    if msg.get("error"):
        raise GatewayError(msg["error"].get("message") or "gateway error")
    return msg.get("result") or {}, sid


def gateway_call(tool, args):
    """Call one allowlisted gateway tool; returns its result envelope."""
    if args.get("action") not in WRITE_TOOLS.get(tool, ()):
        raise GatewayError(f"{tool} {args.get('action')} is not allowed from the phone apps")
    if not GATEWAY:
        raise GatewayError("no MCP gateway on this host; changes are disabled")
    sid = None
    try:
        _, sid = _rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": PROTOCOL, "capabilities": {},
            "clientInfo": {"name": "wall-display-apps", "version": "1"}}}, None)
        _rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
        result, _ = _rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                          "params": {"name": tool, "arguments": args}}, sid)
    finally:
        if sid:  # end the session; the gateway keeps them otherwise
            try:
                urllib.request.urlopen(urllib.request.Request(
                    GATEWAY, method="DELETE", headers={"Mcp-Session-Id": sid}), timeout=5).close()
            except OSError:
                pass
    text = next((c.get("text", "") for c in result.get("content", []) if c.get("type") == "text"), "")
    try:
        env = json.loads(text)
    except ValueError:
        env = {"status": "error" if result.get("isError") else "ok", "message": text}
    if result.get("isError") or env.get("status") == "error":
        detail = " — ".join(x for x in (env.get("message"), env.get("suggestion")) if x)
        raise GatewayError(detail[:400] or f"{tool} failed")
    log(f"apps: {tool} {args.get('action') or ''} ok: {str(env.get('message'))[:120]}")
    return env


# ── input validation ────────────────────────────────────────────────────────

CONTROL = re.compile(r"[\x00-\x1f\x7f]")
TIME_RE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def text_field(body, key, limit, required=False, multiline=False):
    v = body.get(key)
    if v is None:
        if required:
            raise Invalid(f"{key} is required")
        return None
    if not isinstance(v, str):
        raise Invalid(f"{key} must be text")
    v = v.strip()
    if required and not v:
        raise Invalid(f"{key} is required")
    if len(v) > limit:
        raise Invalid(f"{key} is longer than {limit} characters")
    if CONTROL.search(v.replace("\n", "") if multiline else v):
        raise Invalid(f"{key} contains control characters")
    return v


def date_field(v, key):
    if not isinstance(v, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", v):
        raise Invalid(f"{key} must be a date YYYY-MM-DD")
    try:
        d = dt.date.fromisoformat(v)
    except ValueError:
        raise Invalid(f"{key} is not a real date") from None
    if not 2000 <= d.year <= 2100:
        raise Invalid(f"{key} is out of range")
    return d


def time_field(v, key):
    if not isinstance(v, str) or not TIME_RE.match(v):
        raise Invalid(f"{key} must be a time HH:MM")
    return v


def priority_field(v):
    if not isinstance(v, int) or isinstance(v, bool) or not 0 <= v <= 9:
        raise Invalid("priority must be 0 (none) to 9")
    return v


def coll_id(href):
    return href.rstrip("/").rsplit("/", 1)[-1]


def iso_time(t):
    return f"{t.hour:02d}:{t.minute:02d}"


# ── tasks ───────────────────────────────────────────────────────────────────

def task_lists():
    return [(href, name) for href, name in screens.collections("VTODO") if coll_id(href) not in READ_ONLY]


def read_tasks(today):
    """Every writable task list with its open tasks and the recently finished."""
    out = []
    for href, name in task_lists():
        tasks = []
        for t in screens.components(href, screens.TODO_REPORT, "VTODO"):
            try:
                status = str(t.get("STATUS", "NEEDS-ACTION")).upper()
                if status == "CANCELLED" or "UID" not in t:
                    continue
                done = status == "COMPLETED" or "COMPLETED" in t
                completed = screens.local(t.decoded("COMPLETED")) if "COMPLETED" in t else None
                if done and (not isinstance(completed, dt.datetime)
                             or completed.date() < today - dt.timedelta(days=DONE_DAYS)):
                    continue
                due = screens.local(t.decoded("DUE")) if "DUE" in t else None
                tasks.append({
                    "uid": str(t["UID"]),
                    "summary": str(t.get("SUMMARY", "")).strip() or "(untitled)",
                    "list": name,
                    "due": (due.date() if isinstance(due, dt.datetime) else due).isoformat() if due else None,
                    "dueTime": iso_time(due) if isinstance(due, dt.datetime) else None,
                    "priority": int(t.get("PRIORITY", 0) or 0),
                    "done": done,
                    "completed": completed.isoformat() if done else None,
                    "recurring": "RRULE" in t,
                })
            except (ValueError, TypeError, KeyError) as exc:  # one malformed item must not hide a list
                log(f"apps: skipped a task in {name}: {exc}")
        tasks.sort(key=lambda x: (x["done"], x["due"] is None, x["due"] or "", x["priority"] or 10,
                                  x["summary"].lower()))
        out.append({"name": name, "tasks": tasks})
    out.sort(key=lambda lst: lst["name"].lower())
    return out


def tasks_state(h):
    today = now().date()
    return {"today": today.isoformat(), "canWrite": can_write(h), "lists": read_tasks(today)}


def find_task(uid):
    for lst in read_tasks(now().date()):
        for t in lst["tasks"]:
            if t["uid"] == uid:
                return t
    return None


def task_add(h, body):
    summary = text_field(body, "summary", 200, required=True)
    list_name = text_field(body, "list", 100, required=True)
    names = [name for _, name in task_lists()]
    if list_name not in names:
        raise Invalid(f"no task list named {list_name!r}")
    args = {"summary": summary, "list": list_name}
    if body.get("due"):
        args["due"] = date_field(body["due"], "due").isoformat()
    prio = priority_field(body.get("priority", 0))
    if prio:
        args["priority"] = prio
    env = gateway_call("hwc_tasks_add", args)
    return {"ok": True, "message": env.get("message"), "state": tasks_state(h)}


def task_update(h, body):
    uid = text_field(body, "uid", 300, required=True)
    action = body.get("action")
    if action not in ("complete", "reopen", "edit", "delete"):
        raise Invalid("action must be complete, reopen, edit or delete")
    task = find_task(uid)
    if task is None:
        raise Invalid("that task is no longer there; refresh")
    args = {"uid": uid, "action": action}
    if action == "delete" and body.get("confirm") is not True:
        raise Invalid("delete needs confirm: true")
    if action == "edit":
        if "summary" in body:
            args["summary"] = text_field(body, "summary", 200, required=True)
        if "due" in body:
            args["due"] = "" if body["due"] in ("", None) else date_field(body["due"], "due").isoformat()
        if "priority" in body:
            args["priority"] = priority_field(body["priority"])
        if len(args) == 2:
            raise Invalid("nothing to change")
    env = gateway_call("hwc_tasks_update", args)
    return {"ok": True, "message": env.get("message"), "state": tasks_state(h)}


# ── calendar ────────────────────────────────────────────────────────────────

def read_events(first, last):
    """Events touching [first, last] (local dates) on every event calendar.
    Returns (calendars, events); events keep screens.on_day's keys."""
    start = dt.datetime.combine(first, dt.time(), TZ)
    end = dt.datetime.combine(last + dt.timedelta(days=1), dt.time(), TZ)
    query = screens.EVENT_REPORT.format(s=screens.utc_stamp(start), e=screens.utc_stamp(end))
    cals, events, seen = [], [], set()
    for href, name in screens.collections("VEVENT"):
        cid = coll_id(href)
        writable = cid not in READ_ONLY
        cals.append({"id": cid, "name": name, "writable": writable})
        for ev in screens.components(href, query, "VEVENT"):
            try:
                if str(ev.get("STATUS", "")).upper() == "CANCELLED" or "UID" not in ev:
                    continue
                s = screens.local(ev.decoded("DTSTART"))
                allday = not isinstance(s, dt.datetime)
                if "DTEND" in ev:
                    e = screens.local(ev.decoded("DTEND"))
                elif "DURATION" in ev:
                    e = s + ev.decoded("DURATION")
                else:
                    e = s + dt.timedelta(days=1) if allday else s
                uid = str(ev["UID"])
                if (cid, uid, s) in seen:
                    continue
                seen.add((cid, uid, s))
                sday = s if allday else s.date()
                eday = (e - dt.timedelta(days=1)) if allday else e.date()
                events.append({
                    "start": s, "end": e, "allday": allday,  # screens.on_day keys
                    "uid": uid, "cal": cid, "calName": name, "writable": writable,
                    "summary": str(ev.get("SUMMARY", "")).strip() or "(busy)",
                    "date": sday.isoformat(),
                    "endDate": eday.isoformat() if eday > sday else None,
                    "startTime": None if allday else iso_time(s),
                    "endTime": None if allday else iso_time(e),
                    "location": str(ev.get("LOCATION", "")).strip(),
                    "description": str(ev.get("DESCRIPTION", "")).strip(),
                    "recurring": "RECURRENCE-ID" in ev or "RRULE" in ev,
                })
            except (ValueError, TypeError, KeyError) as exc:
                log(f"apps: skipped an event in {name}: {exc}")
    return cals, events


def public(ev):
    return {k: v for k, v in ev.items() if k not in ("start", "end")}


def view_range(view, day):
    if view == "day":
        return day, day, day - dt.timedelta(days=1), day + dt.timedelta(days=1)
    if view == "week":
        mon = day - dt.timedelta(days=day.weekday())
        return mon, mon + dt.timedelta(days=6), mon - dt.timedelta(days=7), mon + dt.timedelta(days=7)
    first = day.replace(day=1)
    nxt = (first + dt.timedelta(days=32)).replace(day=1)
    prev = (first - dt.timedelta(days=1)).replace(day=1)
    return first, nxt - dt.timedelta(days=1), prev, nxt


def agenda(h, view, day):
    if view not in ("day", "week", "month"):
        raise Invalid("view must be day, week or month")
    first, last, prev, nxt = view_range(view, day)
    today = now().date()
    cals, events = read_events(first, last)
    days, d = [], first
    while d <= last:
        todays = [e for e in events if screens.on_day(e, d)]
        todays.sort(key=lambda e: (not e["allday"], e["startTime"] or "", e["summary"].lower()))
        if todays or view != "month" or d == today:
            days.append({"date": d.isoformat(), "today": d == today,
                         "events": [dict(public(e), cont=e["date"] != d.isoformat()) for e in todays]})
        d += dt.timedelta(days=1)
    if view == "day":
        title = f"{first:%a} {first.day} {first:%b %Y}"
    elif view == "week":
        title = f"{first.day} {first:%b} – {last.day} {last:%b %Y}"
    else:
        title = f"{first:%B %Y}"
    return {"view": view, "date": day.isoformat(), "title": title, "today": today.isoformat(),
            "prev": prev.isoformat(), "next": nxt.isoformat(), "canWrite": can_write(h),
            "calendars": cals, "days": days}


# khal parses `khal new` arguments as "START [END] [TZ] SUMMARY [:: DESCRIPTION]"
# and takes the longest prefix that reads as a date range, so a summary that
# starts like a date, time, duration or zone ("tomorrow", "2pm", "1h", "UTC")
# would be eaten. Refuse those rather than create a wrong event.
KHAL_WORDS = {"today", "tomorrow", "yesterday", "now", "eod", "week", "utc", "gmt", "z",
              "mon", "tue", "wed", "thu", "fri", "sat", "sun", "monday", "tuesday", "wednesday",
              "thursday", "friday", "saturday", "sunday"}


def khal_safe(value, key):
    if " :: " in value or value.startswith(":: ") or value.endswith(" ::"):
        raise Invalid(f"{key} cannot contain ' :: '")
    if key == "summary":
        first = value.split()[0].lower().rstrip(",.:;")
        if first[:1].isdigit() or first in KHAL_WORDS or "/" in first:
            raise Invalid("start the title with a word, not a date, time, weekday or zone "
                          "(the calendar tool would read it as part of the date)")
    return value


def event_fields(body, cals):
    """Validated create arguments for hwc_calendar from the phone's form."""
    summary = khal_safe(text_field(body, "summary", 200, required=True), "summary")
    cal = text_field(body, "calendar", 100, required=True)
    if not any(c["name"] == cal and c["writable"] for c in cals):
        raise Invalid(f"{cal!r} is not a writable calendar")
    date = date_field(body.get("date"), "date")
    args = {"action": "create", "summary": summary, "calendar": cal, "date": date.isoformat()}
    last = date_field(body["endDate"], "endDate") if body.get("endDate") else date
    if last < date or (last - date).days > 366:
        raise Invalid("endDate must be on or after date, within a year")
    if last > date:
        args["endDate"] = last.isoformat()
    if not body.get("allday"):
        start = time_field(body.get("startTime"), "startTime")
        end = time_field(body.get("endTime"), "endTime")
        if last == date and end <= start:
            raise Invalid("end must be after start; choose a later end date for overnight events")
        args.update(startTime=start, endTime=end)
    loc = text_field(body, "location", 200)
    desc = text_field(body, "description", 2000, multiline=True)
    if loc:
        args["location"] = khal_safe(loc, "location")
    if desc:
        args["description"] = khal_safe(desc.replace("\n", " "), "description")
    return args


def signature(args):
    """What a created event looks like when Radicale shows it."""
    return (args["calendar"], args["summary"], args["date"], args.get("startTime"))


def count_like(events, sig):
    return sum(1 for e in events if (e["calName"], e["summary"], e["date"], e["startTime"]) == sig)


def locate(body):
    """The event the phone chose, re-read from Radicale and proven to be the
    one hwc_calendar would act on. Returns (event, calendars)."""
    uid = text_field(body, "uid", 400, required=True)
    cid = text_field(body, "cal", 100, required=True)
    day = date_field(body.get("date"), "date")
    cals, events = read_events(day, day)
    ev = next((e for e in events if e["uid"] == uid and e["cal"] == cid and e["date"] == day.isoformat()), None)
    if ev is None:
        raise Invalid("that event is no longer there; refresh")
    if not ev["writable"]:
        raise Invalid(f"{ev['calName']} is a read-only mirror")
    if ev["recurring"]:
        raise Invalid("repeating events are changed in the phone's calendar app, not here")
    probe = {"action": "delete", "query": ev["summary"], "filter_date": ev["date"], "confirm": False}
    matches = (gateway_call("hwc_calendar", probe).get("data") or {}).get("matches") or []
    if not matches:  # the gateway's local copy may lag Radicale: sync once, look again
        gateway_call("hwc_calendar", {"action": "sync"})
        matches = (gateway_call("hwc_calendar", probe).get("data") or {}).get("matches") or []
    if len(matches) != 1 or matches[0].get("uid") != uid or matches[0].get("recurring"):
        raise Invalid(f"the calendar tool finds {len(matches)} event(s) named like this on that day, "
                      "so it cannot change exactly this one; change it in the phone's calendar app")
    return ev, cals


def wait_until(first, last, done):
    deadline = time.time() + SYNC_WAIT
    while True:
        _, events = read_events(first, last)
        if done(events):
            return True
        if time.time() >= deadline:
            return False
        time.sleep(1.5)


PENDING = ("saved, but Radicale does not show it yet (the sync is still running); "
           "refresh in a minute, and check the calendar on your phone if it never appears")


def cal_reply(h, body, message, synced):
    view = body.get("view") if body.get("view") in ("day", "week", "month") else "week"
    try:
        day = date_field(body.get("viewDate"), "viewDate")
    except Invalid:
        day = now().date()
    return {"ok": True, "synced": synced, "message": message if synced else PENDING,
            "state": agenda(h, view, day)}


def cal_create(h, body):
    cals, _ = read_events(now().date(), now().date())
    args = event_fields(body, cals)
    day = dt.date.fromisoformat(args["date"])
    sig = signature(args)
    before = count_like(read_events(day, day)[1], sig)
    env = gateway_call("hwc_calendar", args)
    synced = wait_until(day, day, lambda evs: count_like(evs, sig) > before)
    return cal_reply(h, body, env.get("message"), synced)


def cal_delete(h, body):
    if body.get("confirm") is not True:
        raise Invalid("delete needs confirm: true")
    ev, _ = locate(body)
    day = dt.date.fromisoformat(ev["date"])
    env = gateway_call("hwc_calendar", {"action": "delete", "query": ev["summary"],
                                        "filter_date": ev["date"], "confirm": True})
    synced = wait_until(day, day, lambda evs: not any(e["uid"] == ev["uid"] for e in evs))
    return cal_reply(h, body, env.get("message"), synced)


def as_create(ev):
    """Create arguments that rebuild an event read from Radicale."""
    args = {"action": "create", "summary": ev["summary"], "calendar": ev["calName"], "date": ev["date"]}
    if ev["endDate"]:
        args["endDate"] = ev["endDate"]
    if not ev["allday"]:
        args.update(startTime=ev["startTime"], endTime=ev["endTime"])
    if ev["location"]:
        args["location"] = ev["location"]
    if ev["description"]:
        args["description"] = ev["description"].replace("\n", " ")
    return args


def cal_edit(h, body):
    ev, cals = locate(body)
    new = event_fields(body.get("event") or {}, cals)
    if new == as_create(ev):
        raise Invalid("nothing to change")
    old_day, new_day = dt.date.fromisoformat(ev["date"]), dt.date.fromisoformat(new["date"])
    sig = signature(new)
    before = count_like(read_events(new_day, new_day)[1], sig)
    gateway_call("hwc_calendar", {"action": "delete", "query": ev["summary"],
                                  "filter_date": ev["date"], "confirm": True})
    try:
        env = gateway_call("hwc_calendar", new)
    except GatewayError as exc:
        try:
            gateway_call("hwc_calendar", as_create(ev))
            restored = "the original event was put back"
        except GatewayError as again:
            restored = f"putting the original back also failed ({again}); re-add it by hand"
        raise GatewayError(f"the change failed ({exc}); {restored}") from exc
    # When the title, calendar, day and start are unchanged, the old event was
    # one of `before`, so the edited copy only brings the count back to it.
    target = before if sig == signature(as_create(ev)) else before + 1
    first, last = min(old_day, new_day), max(old_day, new_day)
    synced = wait_until(first, last, lambda evs: count_like(evs, sig) >= target
                        and not any(e["uid"] == ev["uid"] for e in evs))
    return cal_reply(h, body, env.get("message"), synced)


# ── HTTP faces ──────────────────────────────────────────────────────────────

def can_write(h):
    return bool(GATEWAY) and h.from_tailnet()


def same_site(h):
    if "application/json" not in (h.headers.get("Content-Type") or ""):
        return False
    origin = h.headers.get("Origin")
    if origin is None:  # not a browser (curl); the tailnet check still applies
        return True
    host = h.headers.get("X-Forwarded-Host") or h.headers.get("Host") or ""
    return urllib.parse.urlsplit(origin).netloc == host


class App:
    page = ""
    pages = {}
    reads = {}
    writes = {}

    def __init__(self, changed):
        self.changed = changed

    def get(self, h, path):
        if path in ("/", "/index.html"):
            return h.send(200, "text/html; charset=utf-8", self.page)
        if path in self.pages:
            return h.send(200, "text/html; charset=utf-8", self.pages[path])
        read = self.reads.get(path)
        if read is None:
            return h.send(404, "text/plain", "not found")
        query = urllib.parse.parse_qs(h.path.partition("?")[2])
        self.answer(h, lambda: read(h, {k: v[0] for k, v in query.items()}))

    def post(self, h, path):
        if h.refuse_unless_tailnet():
            return
        if not same_site(h):
            return h.json(403, {"error": "changes need a JSON request from this site"})
        write = self.writes.get(path)
        if write is None:
            return h.json(404, {"error": "not found"})
        try:
            body = json.loads(h.read_body(BODY_LIMIT) or b"{}")
            if not isinstance(body, dict):
                raise ValueError("body must be a JSON object")
        except ValueError as exc:
            return h.json(400, {"error": f"bad request: {exc}"})
        def apply():
            result = write(h, body)
            self.changed()
            return result
        self.answer(h, apply)

    @staticmethod
    def answer(h, fn):
        try:
            h.json(200, fn())
        except Invalid as exc:
            h.json(400, {"error": str(exc)})
        except GatewayError as exc:
            h.json(502, {"error": str(exc)})
        except Exception as exc:  # CalDAV down, etc.: say so, keep serving
            log(f"apps: {h.command} {h.path} failed: {type(exc).__name__}: {exc}")
            h.json(500, {"error": f"{type(exc).__name__}: {exc}"})


def _agenda_read(h, q):
    day = date_field(q["date"], "date") if q.get("date") else now().date()
    return agenda(h, q.get("view", "week"), day)


class TasksApp(App):
    reads = {"/api/state": lambda h, q: tasks_state(h)}
    writes = {"/api/add": task_add, "/api/update": task_update}


class CalendarApp(App):
    reads = {"/api/agenda": _agenda_read}
    writes = {"/api/create": cal_create, "/api/edit": cal_edit, "/api/delete": cal_delete}


# ── pages (no build step: one HTML file each, vanilla JS, data via textContent) ──

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
[hidden]{display:none!important}
html{-webkit-text-size-adjust:100%;touch-action:manipulation}
body{font:16px/1.35 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:#fff;color:#000;
  min-height:100dvh;padding:0 0 calc(24px + env(safe-area-inset-bottom))}
button,input,select,textarea{font:inherit;color:#000;background:#fff;border:2px solid #000;border-radius:0}
button{min-height:44px;padding:0 14px;font-weight:700;cursor:pointer;-webkit-tap-highlight-color:transparent}
button.ink{background:#000;color:#fff}
button:disabled{opacity:.4}
input,select,textarea{min-height:44px;padding:8px 10px;width:100%;font-size:16px}
textarea{min-height:88px}
label{display:block;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;margin:10px 0 4px}
header{position:sticky;top:0;background:#fff;border-bottom:3px solid #000;padding:calc(10px + env(safe-area-inset-top)) 14px 10px;z-index:2}
h1{font-size:26px;font-weight:800;letter-spacing:-.01em}
.bar{display:flex;gap:8px;align-items:center;justify-content:space-between}
.chips{display:flex;gap:6px;overflow-x:auto;padding-top:10px;scrollbar-width:none}
.chips button{flex:none;font-weight:600}
.chips button[aria-pressed=true]{background:#000;color:#fff}
main{padding:0 14px}
h2{font-size:14px;text-transform:uppercase;letter-spacing:.06em;border-bottom:2px solid #000;padding:16px 0 4px}
h2.today{background:#000;color:#fff;padding-left:6px}
ul{list-style:none}
li.row{display:flex;align-items:center;gap:10px;border-bottom:1px dotted #000;min-height:52px;padding:4px 0}
.tick{flex:none;width:44px;height:44px;padding:0;font-size:22px;line-height:1}
.body{flex:1;min-width:0;text-align:left;border:0;background:none;padding:6px 0;font-weight:400;min-height:44px}
.title{display:block;overflow-wrap:anywhere}
.meta{display:block;font:12px/1.3 ui-monospace,Menlo,monospace;margin-top:2px}
.done .title{text-decoration:line-through}
.late .meta{font-weight:700}
.when{flex:none;width:68px;font:700 13px/1.2 ui-monospace,Menlo,monospace;white-space:pre-line}
.lock{font:11px ui-monospace,Menlo,monospace;border:1px solid #000;padding:0 4px;margin-left:4px}
.empty{font:13px ui-monospace,Menlo,monospace;padding:14px 0;color:#000}
form.add{display:grid;gap:8px;padding:12px 0;border-bottom:3px solid #000}
.grid3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px}
.status{position:fixed;left:0;right:0;bottom:0;background:#000;color:#fff;font:13px ui-monospace,Menlo,monospace;
  padding:10px 14px calc(10px + env(safe-area-inset-bottom));z-index:5}
.status:empty{display:none}
.note{font:12px ui-monospace,Menlo,monospace;padding:8px 0}
details summary{min-height:44px;display:flex;align-items:center;font-weight:700;cursor:pointer}
.sheet{position:fixed;inset:0;background:rgba(0,0,0,.35);display:flex;align-items:flex-end;z-index:4}
.sheet[hidden]{display:none}
.panel{background:#fff;border-top:3px solid #000;width:100%;max-height:92dvh;overflow:auto;
  padding:16px 14px calc(16px + env(safe-area-inset-bottom))}
.panel h3{font-size:20px;margin-bottom:6px}
.actions{display:flex;gap:8px;margin-top:16px;flex-wrap:wrap}
.actions button{flex:1}
.check{display:flex;align-items:center;gap:10px;min-height:44px;margin-top:8px;font-weight:700}
.check input{width:24px;height:24px;min-height:0}
.confirm{border:3px solid #000;padding:12px;margin-top:16px}
@media (prefers-reduced-motion:no-preference){button:active{transform:translateY(1px)}}
@media (min-width:700px){main,header>*{max-width:640px;margin-left:auto;margin-right:auto}}
"""

COMMON_JS = r"""
const $ = (s, el = document) => el.querySelector(s);
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v; else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else if (v === true) n.setAttribute(k, ""); else if (v !== false && v != null) n.setAttribute(k, v);
  }
  for (const k of kids.flat()) if (k != null) n.append(k.nodeType ? k : document.createTextNode(String(k)));
  return n;
};
let busy = false;
function say(msg, sticky) {
  const s = $("#status"); s.textContent = msg || "";
  clearTimeout(say.t); if (msg && !sticky) say.t = setTimeout(() => { s.textContent = ""; }, 6000);
}
async function api(path, body) {
  const opt = body ? { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) } : {};
  const r = await fetch(path, opt);
  let j = {}; try { j = await r.json(); } catch (e) {}
  if (!r.ok) throw new Error(j.error || ("HTTP " + r.status));
  return j;
}
async function write(path, body, saving) {
  if (busy) return null; busy = true; say(saving || "saving…", true);
  document.body.setAttribute("aria-busy", "true");
  try { const j = await api(path, body); say(j.message || "saved"); return j; }
  catch (e) { say("not saved: " + e.message); return null; }
  finally { busy = false; document.body.removeAttribute("aria-busy"); }
}
function sheet(build) {
  const s = $("#sheet"), p = $("#panel"); p.replaceChildren(...build(() => { s.hidden = true; }));
  s.hidden = false; const f = p.querySelector("input,select,textarea,button"); if (f) f.focus();
}
document.addEventListener("keydown", e => { if (e.key === "Escape") $("#sheet").hidden = true; });
document.addEventListener("click", e => { if (e.target.id === "sheet") e.target.hidden = true; });
const PRI = ["", "A", "B", "C", "D", "E", "F", "G", "H", "I"];
const fmtDay = iso => { const d = new Date(iso + "T12:00:00"); return d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" }); };
"""

SHELL = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#ffffff"><meta name="apple-mobile-web-app-capable" content="yes">
<title>{title}</title><style>{css}</style></head>
<body>{body}
<div id="sheet" class="sheet" hidden><div id="panel" class="panel" role="dialog" aria-modal="true"></div></div>
<div id="status" class="status" role="status" aria-live="polite"></div>
<script>{common}{script}</script></body></html>"""

TASKS_BODY = """
<header><div class="bar"><h1>Tasks</h1><button id="reload" aria-label="refresh">↻</button></div>
<div class="chips" id="chips" role="toolbar" aria-label="lists"></div></header>
<main>
<form class="add" id="add" autocomplete="off">
  <input id="a-sum" maxlength="200" placeholder="New task  (+project @context (A) due:… work too)" aria-label="task" required>
  <div class="grid3">
    <select id="a-list" aria-label="list"></select>
    <input id="a-due" type="date" aria-label="due date">
    <select id="a-pri" aria-label="priority"></select>
  </div>
  <button class="ink" type="submit">Add task</button>
</form>
<p class="note" id="ro" hidden>read-only here: changes are accepted from tailnet devices only</p>
<div id="list"></div>
</main>"""

TASKS_JS = r"""
const groceryPage = location.pathname === @@GROCERY_PATH@@, groceryList = @@GROCERY_LIST@@;
let S = null, sel = groceryPage ? groceryList : localStorage.getItem("tasks.list") || "";
function priOptions(select, cur) {
  select.replaceChildren(el("option", { value: 0 }, "prio –"),
    ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map(p => el("option", { value: p }, "(" + PRI[p] + ")")));
  select.value = String(cur || 0);
}
function dueLabel(t) {
  if (!t.due) return "";
  const days = Math.round((new Date(t.due + "T12:00:00") - new Date(S.today + "T12:00:00")) / 864e5);
  const word = days === 0 ? "today" : days === 1 ? "tomorrow" : days < 0 ? (-days) + "d overdue" : fmtDay(t.due);
  return word + (t.dueTime ? " " + t.dueTime : "");
}
function render(state) {
  S = state; const names = S.lists.map(l => l.name);
  if (sel && !names.includes(sel) && !groceryPage) sel = "";
  $("#chips").replaceChildren(...["", ...names].map(n => el("button", {
    "aria-pressed": String(n === sel), onclick: () => { sel = n; localStorage.setItem("tasks.list", n); render(S); }
  }, n || "All")));
  const aList = $("#a-list"), keep = aList.value;
  aList.replaceChildren(...names.map(n => el("option", { value: n }, n)));
  aList.value = sel || (names.includes(keep) ? keep : (names.includes("hwc") ? "hwc" : names[0] || ""));
  if (!$("#a-pri").options.length) priOptions($("#a-pri"), 0);
  $("#ro").hidden = S.canWrite; $("#add").hidden = !S.canWrite;
  if (groceryPage) {
    $("#chips").hidden = true;
    aList.value = groceryList; aList.disabled = true;
    $("#a-due").hidden = true; $("#a-pri").hidden = true;
    $("#add").hidden = !S.canWrite || !names.includes(groceryList);
    if (!names.includes(groceryList)) say("Grocery list is unavailable; no items can be added.", true);
  }
  const tasks = S.lists.filter(l => !sel || l.name === sel).flatMap(l => l.tasks);
  const open = tasks.filter(t => !t.done), done = tasks.filter(t => t.done);
  const groups = [
    ["Overdue", open.filter(t => t.due && t.due < S.today)],
    ["Today", open.filter(t => t.due === S.today)],
    ["Upcoming", open.filter(t => t.due && t.due > S.today)],
    ["No date", open.filter(t => !t.due)],
  ];
  const out = groups.filter(([, ts]) => ts.length).map(([name, ts]) =>
    [el("h2", { class: name === "Today" ? "today" : "" }, name + " · " + ts.length), el("ul", {}, ts.map(row))]);
  if (!open.length) out.push(el("p", { class: "empty" }, "nothing to do"));
  if (done.length) out.push(el("details", {}, el("summary", {}, "Done this week · " + done.length), el("ul", {}, done.map(row))));
  $("#list").replaceChildren(...out.flat());
}
function row(t) {
  const late = !t.done && t.due && t.due < S.today;
  const meta = [dueLabel(t), t.priority ? "(" + PRI[t.priority] + ")" : "", sel ? "" : t.list, t.recurring ? "repeats" : ""].filter(Boolean).join(" · ");
  return el("li", { class: "row" + (t.done ? " done" : "") + (late ? " late" : "") },
    el("button", { class: "tick", "aria-label": (t.done ? "reopen " : "complete ") + t.summary, disabled: !S.canWrite,
      onclick: () => update({ uid: t.uid, action: t.done ? "reopen" : "complete" }, t.done ? "reopening…" : "completing…") }, t.done ? "✓" : ""),
    el("button", { class: "body", onclick: () => edit(t) }, el("span", { class: "title" }, t.summary), meta ? el("span", { class: "meta" }, meta) : null));
}
async function update(body, saving) { const j = await write("/api/update", body, saving); if (j) render(j.state); return j; }
function edit(t) {
  sheet(close => {
    const sum = el("input", { value: t.summary, maxlength: 200, "aria-label": "summary" });
    const due = el("input", { type: "date", value: t.due || "", "aria-label": "due" });
    const pri = el("select", { "aria-label": "priority" }); priOptions(pri, t.priority);
    const confirmBox = el("div", { class: "confirm", hidden: true },
      el("p", {}, "Delete “" + t.summary + "”? This cannot be undone."),
      el("div", { class: "actions" },
        el("button", { type: "button", onclick: () => { confirmBox.hidden = true; } }, "Keep it"),
        el("button", { class: "ink", type: "button", onclick: async () => { if (await update({ uid: t.uid, action: "delete", confirm: true }, "deleting…")) close(); } }, "Delete")));
    const ro = !S.canWrite;
    return [el("h3", {}, ro ? "Task" : "Edit task"), el("p", { class: "meta" }, t.list + (t.done ? " · done" : "")),
      el("label", {}, "Summary"), sum, el("label", {}, "Due"), due, el("label", {}, "Priority"), pri,
      el("div", { class: "actions" },
        el("button", { type: "button", onclick: close }, "Close"),
        ro ? null : el("button", { type: "button", onclick: () => { confirmBox.hidden = false; } }, "Delete…"),
        ro ? null : el("button", { class: "ink", type: "button", onclick: async () => {
          const b = { uid: t.uid, action: "edit" };
          if (sum.value.trim() !== t.summary) b.summary = sum.value;
          if (due.value !== (t.due || "")) b.due = due.value;
          if (+pri.value !== t.priority) b.priority = +pri.value;
          if (Object.keys(b).length === 2) return close();
          if (await update(b)) close();
        } }, "Save")),
      confirmBox].filter(Boolean);
  });
}
$("#add").addEventListener("submit", async e => {
  e.preventDefault();
  const b = { summary: $("#a-sum").value, list: $("#a-list").value, priority: +$("#a-pri").value };
  if ($("#a-due").value) b.due = $("#a-due").value;
  const j = await write("/api/add", b, "adding…");
  if (j) { $("#a-sum").value = ""; $("#a-due").value = ""; $("#a-pri").value = "0"; render(j.state); }
});
async function load() { try { render(await api("/api/state")); } catch (e) { say("could not load: " + e.message, true); } }
$("#reload").addEventListener("click", load);
document.addEventListener("visibilitychange", () => { if (!document.hidden && !busy) load(); });
load();
"""

CAL_BODY = """
<header><div class="bar"><h1>Calendar</h1><button id="add" class="ink" aria-label="new event">+ Event</button></div>
<div class="chips" role="toolbar" aria-label="view">
  <button data-view="day">Day</button><button data-view="week">Week</button><button data-view="month">Month</button>
</div>
<div class="bar" style="padding-top:8px">
  <button id="prev" aria-label="previous">‹</button><strong id="title" style="text-align:center;flex:1"></strong>
  <button id="next" aria-label="next">›</button><button id="today">Today</button>
</div></header>
<main><p class="note" id="ro" hidden>read-only here: changes are accepted from tailnet devices only</p><div id="days"></div></main>"""

CAL_JS = r"""
let S = null, view = localStorage.getItem("cal.view") || "week", date = "";
const writable = () => S.calendars.filter(c => c.writable);
function render(state) {
  S = state; view = S.view; date = S.date;
  document.querySelectorAll("[data-view]").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.view === view)));
  $("#title").textContent = S.title; $("#ro").hidden = S.canWrite;
  $("#add").hidden = !S.canWrite || !writable().length;
  const out = S.days.map(d => [
    el("h2", { class: d.today ? "today" : "" }, fmtDay(d.date) + (d.today ? " · today" : "")),
    d.events.length ? el("ul", {}, d.events.map(ev => el("li", { class: "row" },
      el("span", { class: "when" }, ev.cont ? "cont." : ev.allday ? "all day" : ev.startTime + "\n" + ev.endTime),
      el("button", { class: "body", onclick: () => open(ev) },
        el("span", { class: "title" }, ev.summary),
        el("span", { class: "meta" }, ev.calName, ev.writable ? null : el("span", { class: "lock" }, "read-only"),
          ev.recurring ? " · repeats" : "", ev.location ? " · " + ev.location : "")))))
      : el("p", { class: "empty" }, "no events")]);
  if (!out.length) out.push([el("p", { class: "empty" }, "no events this month")]);
  $("#days").replaceChildren(...out.flat());
}
async function load(v, d) {
  try {
    const q = new URLSearchParams({ view: v || view }); if (d || date) q.set("date", d || date);
    render(await api("/api/agenda?" + q)); localStorage.setItem("cal.view", view);
  } catch (e) { say("could not load: " + e.message, true); }
}
function form(ev, close) {
  const cal = el("select", { "aria-label": "calendar" }, writable().map(c => el("option", { value: c.name }, c.name)));
  cal.value = ev ? ev.calName : (localStorage.getItem("cal.last") || (writable().find(c => c.name === "hwc") || writable()[0]).name);
  if (!cal.value) cal.selectedIndex = 0;
  const f = {
    summary: el("input", { value: ev ? ev.summary : "", maxlength: 200, "aria-label": "title" }),
    calendar: cal,
    date: el("input", { type: "date", value: ev ? ev.date : (S.days.find(d => d.today) ? S.today : S.date), "aria-label": "start date" }),
    allday: el("input", { type: "checkbox", checked: ev ? ev.allday : false }),
    startTime: el("input", { type: "time", value: ev && ev.startTime || "09:00" }),
    endTime: el("input", { type: "time", value: ev && ev.endTime || "10:00" }),
    endDate: el("input", { type: "date", value: ev && (ev.endDate || ev.date) || S.today, "aria-label": "end date" }),
    location: el("input", { value: ev ? ev.location : "", maxlength: 200 }),
    description: el("textarea", { maxlength: 2000 }, ev ? ev.description : ""),
  };
  const timed = el("div", { class: "grid3", style: "grid-template-columns:1fr 1fr" },
    el("div", {}, el("label", {}, "Starts"), f.startTime), el("div", {}, el("label", {}, "Ends"), f.endTime));
  const multi = el("div", {}, el("label", {}, "End date (last day for all-day events)"), f.endDate);
  f.date.addEventListener("change", () => { f.endDate.min = f.date.value; if (f.endDate.value < f.date.value) f.endDate.value = f.date.value; });
  const sync = () => { timed.hidden = f.allday.checked; f.endDate.min = f.date.value; if (f.endDate.value < f.date.value) f.endDate.value = f.date.value; };
  f.allday.addEventListener("change", sync); sync();
  const value = () => {
    const b = { summary: f.summary.value, calendar: f.calendar.value, date: f.date.value, allday: f.allday.checked,
      location: f.location.value, description: f.description.value };
    if (f.endDate.value) b.endDate = f.endDate.value;
    if (!b.allday) { b.startTime = f.startTime.value; b.endTime = f.endTime.value; }
    localStorage.setItem("cal.last", b.calendar); return b;
  };
  return { value, nodes: [el("label", {}, "Title"), f.summary, el("label", {}, "Calendar"), f.calendar,
    el("label", {}, "Start date"), f.date, multi, el("label", { class: "check" }, f.allday, "All day"), timed,
    el("label", {}, "Location"), f.location, el("label", {}, "Notes"), f.description] };
}
const ctx = () => ({ view, viewDate: date });
async function save(path, body, saving) {
  const j = await write(path, Object.assign(body, ctx()), saving);
  if (j) { render(j.state); if (!j.synced) say(j.message, true); }
  return j;
}
function open(ev) {
  sheet(close => {
    const editable = S.canWrite && ev.writable && !ev.recurring;
    if (!editable) {
      const why = !ev.writable ? ev.calName + " is a read-only mirror" : ev.recurring ? "repeating: change it in the phone's calendar app" : "read-only from this device";
      return [el("h3", {}, ev.summary), el("p", { class: "meta" }, ev.calName + " · " + fmtDay(ev.date) + (ev.allday ? " · all day" : " · " + ev.startTime + "–" + ev.endTime)),
        ev.location ? el("p", {}, ev.location) : null, ev.description ? el("p", { style: "white-space:pre-wrap;margin-top:8px" }, ev.description) : null,
        el("p", { class: "note" }, why), el("div", { class: "actions" }, el("button", { onclick: close }, "Close"))].filter(Boolean);
    }
    const fm = form(ev, close), id = { uid: ev.uid, cal: ev.cal, date: ev.date };
    const confirmBox = el("div", { class: "confirm", hidden: true },
      el("p", {}, "Delete “" + ev.summary + "” on " + fmtDay(ev.date) + "? This cannot be undone."),
      el("div", { class: "actions" },
        el("button", { type: "button", onclick: () => { confirmBox.hidden = true; } }, "Keep it"),
        el("button", { class: "ink", type: "button", onclick: async () => {
          if (await save("/api/delete", Object.assign({ confirm: true }, id), "deleting… waiting for the calendar to sync")) close(); } }, "Delete")));
    return [el("h3", {}, "Edit event"), el("p", { class: "note" }, "saving re-creates the event; alarms and invitations on it are not kept"),
      ...fm.nodes, el("div", { class: "actions" },
        el("button", { type: "button", onclick: close }, "Close"),
        el("button", { type: "button", onclick: () => { confirmBox.hidden = false; } }, "Delete…"),
        el("button", { class: "ink", type: "button", onclick: async () => {
          if (await save("/api/edit", Object.assign({ event: fm.value() }, id), "saving… waiting for the calendar to sync")) close(); } }, "Save")),
      confirmBox];
  });
}
function newEvent() { sheet(close => {
  const fm = form(null, close);
  return [el("h3", {}, "New event"), ...fm.nodes, el("div", { class: "actions" },
    el("button", { type: "button", onclick: close }, "Cancel"),
    el("button", { class: "ink", type: "button", onclick: async () => {
      if (await save("/api/create", fm.value(), "saving… waiting for the calendar to sync")) close(); } }, "Add"))];
}); }
$("#add").addEventListener("click", newEvent);
document.querySelectorAll("[data-view]").forEach(b => b.addEventListener("click", () => load(b.dataset.view, date)));
$("#prev").addEventListener("click", () => load(view, S.prev));
$("#next").addEventListener("click", () => load(view, S.next));
$("#today").addEventListener("click", () => load(view, S.today));
document.addEventListener("visibilitychange", () => { if (!document.hidden && !busy) load(); });
load(view).then(() => { if (new URLSearchParams(location.search).get("add") === "1" && S && S.canWrite && writable().length) newEvent(); });
"""


def _page(title, body, script):
    # Plain replacement: the CSS and JS are full of braces str.format would read.
    out = SHELL
    for key, value in (("title", title), ("css", CSS), ("body", body), ("common", COMMON_JS), ("script", script)):
        out = out.replace("{" + key + "}", value, 1)
    return out


TASKS_JS = TASKS_JS.replace("@@GROCERY_LIST@@", json.dumps(screens.TASK_LISTS["groceries"]))
TASKS_JS = TASKS_JS.replace("@@GROCERY_PATH@@", json.dumps(GROCERY_PATH))
TasksApp.page = _page("Tasks", TASKS_BODY, TASKS_JS)
TasksApp.pages = {GROCERY_PATH: _page("Groceries", TASKS_BODY.replace("<h1>Tasks</h1>", "<h1>Groceries</h1>"), TASKS_JS)}
CalendarApp.page = _page("Calendar", CAL_BODY, CAL_JS)

# First host label → app (server.py merges this into HOST_APPS).
def host_apps(changed):
    return {"todo": TasksApp(changed), "calendar": CalendarApp(changed)}
