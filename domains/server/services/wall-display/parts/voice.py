"""Tap-to-talk voice for the wall display.

POST /voice (WebM/Opus from the tablet, tailnet only) runs:
  whisper (the `whisper` vhost) -> transcript
  DX2 (OpenAI-compatible chat, tool calls, at most MAX_TOOL_TURNS tool turns)
  tools through the hwc-sys MCP gateway, under a CLOSED (tool, action) list
  Piper (resident subprocess) -> WAV -> ffmpeg -> Opus/OGG, returned inline.

Reads run at once. Writes (hwc_tasks_add, hwc_tasks_update complete) never
run inside /voice: they become a pending action (single use, 60 s) and the
reply asks "Add milk to Groceries?". POST /voice/confirm {id, decision}
runs or drops it; a spoken "yes"/"no" in the next recording (?pending=<id>)
does the same. Every other gateway tool is refused and never offered.

One journal line per request (heard text, tool calls with args, decision).
No audio is kept after the request; the DX2 key is read at call time and
never logged.

Why its own file: server.py holds the device protocol and rendering and
only registers these handlers (POST_ROUTES, health, web client fragment);
screens.py holds the screen producers. Neither is about speech, and the
voice code (tool allowlist, pending writes, Piper supervisor) would double
server.py.
"""
import base64
import datetime as dt
import io
import json
import os
import queue
import re
import secrets
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid
import wave

import screens
from screens import CONFIG, TZ

VOICE = CONFIG.get("voice") or None
ENABLED = VOICE is not None

MAX_AUDIO = 2 << 20      # bytes of WebM per request
MAX_TOOL_TURNS = 4
PENDING_TTL = 60         # seconds a pending write may wait for its confirmation
WHISPER_TIMEOUT = 20
LLM_TIMEOUT = 25
MCP_TIMEOUT = 15
TTS_TIMEOUT = 20
PIPER_DOWN_FAIL = 300    # /healthz fails when voice is on and Piper is down this long
TOOL_OUT_CAP = 6000      # characters of tool output handed back to the model


def log(msg):
    print(msg, file=sys.stderr, flush=True)


# ── the closed tool vocabulary ──────────────────────────────────────────────
# Each entry: the schema offered to the model, and clean(args) -> the exact
# gateway arguments (or raises Refused). Only these names reach the gateway.

class Refused(Exception):
    pass


DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _str(args, key, limit=200, required=False):
    v = args.get(key)
    if v is None or v == "":
        if required:
            raise Refused(f"{key} is required")
        return None
    if not isinstance(v, str):
        raise Refused(f"{key} must be a string")
    return v.strip()[:limit]


def _enum(args, key, allowed, default):
    v = args.get(key, default)
    if v not in allowed:
        raise Refused(f"{key} must be one of {sorted(allowed)}")
    return v


def _date(args, key):
    v = _str(args, key, 10)
    if v is not None and not DATE.match(v):
        raise Refused(f"{key} must be YYYY-MM-DD")
    return v


def _drop_none(d):
    return {k: v for k, v in d.items() if v is not None}


def clean_calendar(a):
    return _drop_none({"action": _enum(a, "action", {"list"}, "list"),
                       "range": _enum(a, "range", {"today", "week", "custom"}, "today"),
                       "start": _date(a, "start"), "end": _date(a, "end")})


def clean_tasks_list(a):
    return _drop_none({"list": _str(a, "list", 60),
                       "status": _enum(a, "status", {"active", "completed", "all"}, "active"),
                       "grep": _str(a, "grep", 80)})


def clean_tasks_lists(a):
    return {"action": _enum(a, "action", {"list"}, "list")}


def clean_today(a):
    return {"action": _enum(a, "action", {"board", "summary"}, "board")}


def clean_weather(_a):
    return {}


DUE = re.compile(r"^(\d{4}-\d{2}-\d{2}|today|tomorrow)$")
# Haiku-style artefact seen in the spike: "Milk +groceries". The gateway would
# read a trailing +tag/@context as a category, so it is stripped here.
TAG_SUFFIX = re.compile(r"(\s+[+@][\w-]+)+\s*$")


def clean_tasks_add(a):
    summary = TAG_SUFFIX.sub("", _str(a, "summary", 120, required=True)).strip(" .")
    if not summary:
        raise Refused("summary is empty")
    due = _str(a, "due", 10)
    if due is not None and not DUE.match(due):
        raise Refused("due must be YYYY-MM-DD, today or tomorrow")
    return _drop_none({"summary": summary, "list": _str(a, "list", 60) or "hwc", "due": due})


def clean_tasks_complete(a):
    return {"uid": _str(a, "uid", 200, required=True),
            "action": _enum(a, "action", {"complete"}, None)}


def _fn(name, desc, props, required=()):
    return {"type": "function", "function": {
        "name": name, "description": desc,
        "parameters": {"type": "object", "properties": props, "required": list(required)}}}


TOOLS = {
    "hwc_calendar": ("read", clean_calendar, _fn(
        "hwc_calendar", "List Eric's calendar events. action must be 'list'. "
        "range=today|week, or custom with start/end (YYYY-MM-DD, end defaults to start).",
        {"action": {"type": "string", "enum": ["list"]},
         "range": {"type": "string", "enum": ["today", "week", "custom"]},
         "start": {"type": "string", "description": "YYYY-MM-DD"},
         "end": {"type": "string", "description": "YYYY-MM-DD"}}, ["action"])),
    "hwc_tasks_list": ("read", clean_tasks_list, _fn(
        "hwc_tasks_list", "List Eric's tasks (active by default), optionally one list or a summary substring.",
        {"list": {"type": "string"},
         "status": {"type": "string", "enum": ["active", "completed", "all"]},
         "grep": {"type": "string"}})),
    "hwc_tasks_lists": ("read", clean_tasks_lists, _fn(
        "hwc_tasks_lists", "The names of Eric's task lists with their active counts.",
        {"action": {"type": "string", "enum": ["list"]}})),
    "hwc_today": ("read", clean_today, _fn(
        "hwc_today", "Eric's ranked Today queue from the morning briefing. board = top items, summary = one line.",
        {"action": {"type": "string", "enum": ["board", "summary"]}})),
    "weather": ("local", clean_weather, _fn(
        "weather", "Current conditions, alerts and the daily forecast (NOAA) for home.", {})),
    "hwc_tasks_add": ("write", clean_tasks_add, _fn(
        "hwc_tasks_add", "Add a task to one of Eric's task lists. The system asks Eric to confirm before it is added.",
        {"summary": {"type": "string", "description": "Plain task text, no tags"},
         "list": {"type": "string", "description": "Existing list name, e.g. Groceries"},
         "due": {"type": "string", "description": "YYYY-MM-DD, today or tomorrow"}}, ["summary", "list"])),
    "hwc_tasks_update": ("write", clean_tasks_complete, _fn(
        "hwc_tasks_update", "Mark a task done. Get the uid from hwc_tasks_list first. Only action 'complete' exists. "
        "The system asks Eric to confirm first.",
        {"uid": {"type": "string"}, "action": {"type": "string", "enum": ["complete"]}}, ["uid", "action"])),
}
TOOL_SCHEMAS = [schema for _, _, schema in TOOLS.values()]


# ── gateway (Streamable HTTP MCP, one session per voice request) ────────────

class Gateway:
    def __init__(self, url):
        self.url, self.sid, self.seq = url, None, 0
        self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                "clientInfo": {"name": "wall-display-voice", "version": "1"}})
        self.rpc("notifications/initialized", {})

    def rpc(self, method, params):
        body = {"jsonrpc": "2.0", "method": method, "params": params}
        note = method.startswith("notifications/")
        if not note:
            self.seq += 1
            body["id"] = self.seq
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                   "mcp-protocol-version": "2025-06-18"}
        if self.sid:
            headers["mcp-session-id"] = self.sid
        req = urllib.request.Request(self.url, data=json.dumps(body).encode(), headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=MCP_TIMEOUT) as r:
            self.sid = r.headers.get("mcp-session-id") or self.sid
            text = r.read().decode()
        if note:
            return None
        msg = None
        for line in text.splitlines():
            if line.startswith("data:"):
                try:
                    j = json.loads(line[5:].strip())
                except ValueError:
                    continue
                if j.get("id") == body["id"]:
                    msg = j
        if msg is None:
            msg = json.loads(text)
        if msg.get("error"):
            raise RuntimeError(f"gateway {method}: {msg['error'].get('message')}")
        return msg["result"]

    def close(self):
        """End the session now rather than leave it to the gateway's 30-min reaper."""
        if self.sid:
            try:
                req = urllib.request.Request(self.url, method="DELETE", headers={"mcp-session-id": self.sid})
                urllib.request.urlopen(req, timeout=5).close()
            except Exception:
                pass

    def call(self, name, args):
        """The tool's JSON payload (its `data` when it has one)."""
        r = self.rpc("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text", "") for c in r.get("content") or [] if c.get("type") == "text")
        if r.get("isError"):
            raise RuntimeError(f"{name}: {text[:200] or 'tool error'}")
        try:
            obj = json.loads(text)
        except ValueError:
            return text
        if isinstance(obj, dict) and obj.get("status") not in (None, "ok"):
            raise RuntimeError(f"{name}: {obj.get('message') or obj.get('status')}")
        return obj.get("data", obj) if isinstance(obj, dict) else obj


def task_lists(gw):
    return [l["name"] for l in gw.call("hwc_tasks_lists", {"action": "list"}).get("lists", [])]


_lists_hint = {"names": None, "at": 0.0}


def lists_hint(gw):
    """List names for the system prompt (5 min cache), so "my H W C list" maps
    to a real list without a tool turn. Writes still re-check live names."""
    if _lists_hint["names"] is None or time.time() - _lists_hint["at"] > 300:
        try:
            _lists_hint.update(names=task_lists(gw), at=time.time())
        except Exception as exc:
            _fail("lists", exc)
    return _lists_hint["names"] or []


def dedupe_busy(data):
    """Drop "Busy" blocks (free/busy mirrors) that repeat or overlap a named
    event on the same day; the spike saw Busy 9-10 beside the real 9-10 meeting."""
    events = data.get("events") if isinstance(data, dict) else None
    if not events:
        return data

    def span(e):
        return (e.get("startTime") or "00:00", e.get("endTime") or e.get("startTime") or "23:59")

    named = [e for e in events if (e.get("summary") or "").strip().lower() != "busy"]
    kept, seen = [], set()
    for e in events:
        if (e.get("summary") or "").strip().lower() == "busy":
            s, en = span(e)
            key = (e.get("date"), s, en)
            if key in seen or any(n.get("date") == e.get("date") and n.get("allDay") is not True
                                  and span(n)[0] < en and s < span(n)[1] for n in named):
                continue
            seen.add(key)
        kept.append(e)
    return {**data, "events": kept, "event_count": len(kept)}


def weather_now():
    wx = screens.weather.get()
    if not wx:
        raise RuntimeError("forecast unavailable")
    days = [{"date": d.isoformat(), "weekday": f"{d:%A}", **w}
            for d, w in sorted(wx["days"].items())[:6]]
    return {"place": screens.PLACE, "now": wx["now"], "alerts": wx["alerts"], "days": days}


# ── pending writes (in memory, single use) ──────────────────────────────────

_pending = {}
_pending_lock = threading.Lock()


MAX_WRITES = 6  # writes one confirmation may carry ("milk, eggs and bread")


def new_pending(actions, question):
    """actions: [(tool, args)], already validated. Returns the single-use id."""
    pid = secrets.token_urlsafe(12)
    with _pending_lock:
        now = time.time()
        for k in [k for k, p in _pending.items() if now - p["at"] > PENDING_TTL]:
            del _pending[k]
        _pending[pid] = {"actions": actions, "summary": question, "at": now}
    return pid


def take_pending(pid):
    """The pending action (removed: single use), or None if unknown or expired."""
    with _pending_lock:
        p = _pending.pop(pid, None) if isinstance(pid, str) else None
    if p is None or time.time() - p["at"] > PENDING_TTL:
        return None
    return p


def stage_write(gw, cache, name, args):
    """Validate one write against live data: the args to run on confirmation.
    Names starting with "_" are for speech only and never sent."""
    if name == "hwc_tasks_add":
        if "lists" not in cache:
            cache["lists"] = task_lists(gw)
        match = next((l for l in cache["lists"] if l.lower() == args["list"].lower()), None)
        if match is None:
            raise Refused(f"there is no list named {args['list']!r}; lists are {', '.join(cache['lists'])}")
        return {**args, "list": match}
    if "tasks" not in cache:
        cache["tasks"] = gw.call("hwc_tasks_list", {"status": "active"}).get("tasks", [])
    task = next((t for t in cache["tasks"] if t.get("uid") == args["uid"]), None)
    if task is None:
        raise Refused("no active task has that uid; call hwc_tasks_list to find it")
    return {**args, "_summary": task.get("summary", "that task")}


def spoken_list(items):
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def describe(actions, done=False):
    """'Add milk and eggs to Groceries, and mark change oil done' (or the past tense)."""
    adds, completes = {}, []
    for tool, args in actions:
        if tool == "hwc_tasks_add":
            adds.setdefault(args["list"], []).append(args["summary"])
        else:
            completes.append(args["_summary"])
    verb_add, verb_mark = ("added", "marked") if done else ("add", "mark")
    clauses = [f"{verb_add} {spoken_list(s)} to {l}" for l, s in adds.items()]
    if completes:
        clauses.append(f"{verb_mark} {spoken_list(completes)} done")
    text = spoken_list(clauses)
    return text[0].upper() + text[1:]


def run_pending(pid, p):
    """Execute a confirmed pending action: the spoken reply."""
    gw = Gateway(VOICE["gatewayUrl"])
    done, failed = [], []
    try:
        for i, (tool, args) in enumerate(p["actions"]):
            try:
                if tool == "hwc_tasks_add":
                    gw.call("hwc_tasks_add", {**args, "idempotencyKey": f"wall-voice-{pid}-{i}"})
                else:
                    gw.call("hwc_tasks_update", {"uid": args["uid"], "action": "complete"})
                done.append((tool, args))
            except Exception as exc:
                _fail("confirm", exc)
                failed.append((tool, args))
    finally:
        gw.close()
    if not done:
        raise RuntimeError(_last["error"])
    reply = describe(done, done=True) + "."
    if failed:
        reply += f" But I could not {describe(failed)[0].lower() + describe(failed)[1:]}."
    return reply


# ── whisper and DX2 ─────────────────────────────────────────────────────────

def transcribe(audio, ctype):
    boundary = uuid.uuid4().hex
    ext = "webm" if "webm" in ctype else "ogg" if "ogg" in ctype else "wav" if "wav" in ctype else "webm"
    body = b"".join([
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="voice.{ext}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n".encode(), audio,
        f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="response_format"\r\n\r\njson'
        f"\r\n--{boundary}--\r\n".encode()])
    req = urllib.request.Request(VOICE["whisperUrl"].rstrip("/") + "/v1/audio/transcriptions", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
                                 method="POST")
    with urllib.request.urlopen(req, timeout=WHISPER_TIMEOUT) as r:
        text = json.loads(r.read()).get("text") or ""
    # whisper marks silence and noise as "[BLANK_AUDIO]", "(wind blowing)" ...
    return re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", text)).strip()


def chat(messages, tools):
    with open(VOICE["dx2"]["apiKeyFile"]) as f:
        key = f.read().strip()
    body = {"model": VOICE["dx2"]["model"], "messages": messages, "temperature": 0.2,
            "max_tokens": 400, "chat_template_kwargs": {"enable_thinking": False}}
    if tools:
        body["tools"] = tools
    req = urllib.request.Request(VOICE["dx2"]["baseUrl"].rstrip("/") + "/chat/completions",
                                 data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as r:
            return json.loads(r.read())["choices"][0]["message"]
    except urllib.error.HTTPError as e:  # the body, never the request headers
        raise RuntimeError(f"DX2 HTTP {e.code}: {e.read()[:200].decode(errors='replace')}") from None


SYSTEM = """You are the voice assistant on Eric's kitchen wall tablet. Your reply is spoken aloud.
Answer in one to three short plain sentences. No markdown, lists, emoji or URLs. Say times like "9 AM".
Today is {weekday} {today}; tomorrow is {tomorrow}. Timezone {tz}.
Use the tools for Eric's calendar, tasks, today queue and the weather; never invent events or tasks.
Events named "Busy" are free/busy blocks; ones that duplicated a named event are already removed. Mention any left simply as "busy at 8 AM", without explaining them.
To add tasks or mark them done, call the tool once per item, all in the same turn; the system asks Eric to confirm, so do not ask yourself.
If something cannot be done with these tools, say so briefly.
Eric's task lists: {lists}. Match a spoken list name to one of these, ignoring case and spacing."""


def system_prompt(now, lists):
    return SYSTEM.format(weekday=f"{now:%A}", today=now.date().isoformat(),
                         tomorrow=(now.date() + dt.timedelta(days=1)).isoformat(), tz=CONFIG["timeZone"],
                         lists=", ".join(lists) or "unknown (call hwc_tasks_lists)")


def speakable(text):
    text = re.sub(r"<think>.*?</think>", " ", text or "", flags=re.S)
    text = re.sub(r"[*_#`>|]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()[:500]


def think(heard, record):
    """DX2 tool loop. Returns (reply, pending) where pending is {id, summary} or None.
    `record` gathers the tool calls and per-step timings for the journal line."""
    conn = {}
    try:
        return _think(heard, record, conn)
    finally:
        if conn.get("gw"):
            conn["gw"].close()


def _think(heard, record, conn):
    try:
        gw = conn["gw"] = Gateway(VOICE["gatewayUrl"])
    except Exception as exc:  # reads fail per tool; the weather still works
        _fail("gateway", exc)
        gw = None
    messages = [{"role": "system", "content": system_prompt(dt.datetime.now(TZ), lists_hint(gw) if gw else [])},
                {"role": "user", "content": heard}]
    cache = {}
    for turn in range(MAX_TOOL_TURNS + 1):
        t = time.time()
        msg = chat(messages, TOOL_SCHEMAS if turn < MAX_TOOL_TURNS else None)
        record["llm_turn_ms"].append(round((time.time() - t) * 1000))
        calls = msg.get("tool_calls") or []
        if not calls:
            return speakable(msg.get("content")) or "Sorry, I have no answer for that.", None
        messages.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": calls})
        staged = []
        for tc in calls:
            name = tc.get("function", {}).get("name")
            try:
                raw = json.loads(tc["function"].get("arguments") or "{}")
            except ValueError:
                raw = {}
            entry = {"tool": name, "args": raw}
            record["tools"].append(entry)
            t = time.time()
            try:
                if name not in TOOLS or not isinstance(raw, dict):
                    raise Refused(f"{name} is not available by voice")
                kind, clean, _ = TOOLS[name]
                args = clean(raw)
                if kind == "local":
                    out = weather_now()
                else:
                    gw = conn["gw"] = gw or Gateway(VOICE["gatewayUrl"])
                    if kind == "write":
                        if len(staged) >= MAX_WRITES:
                            raise Refused(f"at most {MAX_WRITES} changes per request")
                        staged.append((name, stage_write(gw, cache, name, args)))
                        out = "Staged; Eric will be asked to confirm."
                    else:
                        out = gw.call(name, args)
                        if name == "hwc_calendar":
                            out = dedupe_busy(out)
                entry["result"] = "staged" if kind == "write" else "ok"
                content = out if isinstance(out, str) else json.dumps(out, default=str, separators=(",", ":"))
            except Refused as e:
                entry["result"] = f"refused: {e}"
                content = f"Refused: {e}"
            except Exception as e:  # a tool failure is the model's to explain
                entry["result"] = f"error: {type(e).__name__}: {e}"[:200]
                content = f"Error: {e}"[:300]
            entry["ms"] = round((time.time() - t) * 1000)
            messages.append({"role": "tool", "tool_call_id": tc.get("id"), "content": content[:TOOL_OUT_CAP]})
        if staged:
            # Writes never run here: one question covers every write of the turn.
            question = describe(staged) + "?"
            return question, {"id": new_pending(staged, question), "summary": question}
    return "Sorry, I could not finish that.", None


YES = re.compile(r"^(yes|yeah|yep|yup|sure|ok|okay|confirm|do it|please do|go ahead|correct)\b", re.I)
NO = re.compile(r"^(no|nope|nah|cancel|stop|never ?mind|don'?t)\b", re.I)


# ── Piper: one resident process, supervised ────────────────────────────────

class Piper:
    """`piper -d DIR` reads one line of text per utterance on stdin and logs
    "Wrote DIR/<n>.wav" on stderr when the WAV is complete. The process keeps
    the model loaded (~0.45 s per reply vs ~1.3 s per call). A supervisor
    thread restarts it when it exits; while it is down replies are text only."""

    def __init__(self, exe, model):
        # piper 1.4 ignores -c and reads <model>.json beside the model.
        self.cmd = [exe, "-m", model]
        self.proc, self.lines = None, queue.Queue()
        self.lock = threading.Lock()
        self.tail = []
        self.up_since, self.down_since = None, time.time()
        self.last_error, self.restarts = None, 0
        self.outdir = tempfile.mkdtemp(prefix="piper-")

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def _spawn(self):
        self.lines = queue.Queue()
        self.proc = subprocess.Popen(self.cmd + ["-d", self.outdir], stdin=subprocess.PIPE,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, bufsize=1)
        threading.Thread(target=self._read, args=(self.proc, self.lines), daemon=True, name="piper-err").start()

    def _read(self, proc, lines):
        for line in proc.stderr:
            line = line.rstrip()
            if "Wrote " not in line:  # keep the last real messages for /healthz
                self.tail = (self.tail + [line])[-5:]
            lines.put(line)
        lines.put(None)  # EOF: the process is gone

    def supervise(self):
        backoff = 5
        while True:
            if not self.alive():
                if self.proc is not None:
                    self.last_error = f"piper exited {self.proc.returncode}: {' | '.join(self.tail)[-300:]}"
                    log(f"voice: {self.last_error}")
                    self.up_since, self.proc = None, None
                    self.down_since = self.down_since or time.time()
                try:
                    with self.lock:
                        self._spawn()
                    if self.synth("Ready.") is None:
                        raise RuntimeError(self.last_error or "warm-up produced no audio")
                    self.up_since, self.down_since, backoff = time.time(), None, 5
                    self.restarts += 1
                    log("voice: piper up")
                except Exception as exc:
                    self.last_error = f"piper start failed: {exc}"
                    log(f"voice: {self.last_error}")
                    if self.alive():
                        self.proc.kill()
                    time.sleep(backoff)
                    backoff = min(backoff * 2, 60)
                    continue
            time.sleep(5)

    def synth(self, text):
        """WAV bytes for one line of text, or None (Piper down or timed out)."""
        line = re.sub(r"\s+", " ", text).strip()
        if not line:
            return None
        with self.lock:
            if not self.alive():
                return None
            while not self.lines.empty():
                self.lines.get_nowait()
            try:
                self.proc.stdin.write(line + "\n")
                self.proc.stdin.flush()
            except OSError as exc:
                self.last_error = f"piper stdin: {exc}"
                return None
            deadline = time.time() + TTS_TIMEOUT
            while time.time() < deadline:
                try:
                    msg = self.lines.get(timeout=max(0.05, deadline - time.time()))
                except queue.Empty:
                    break
                if msg is None:
                    self.last_error = f"piper exited: {' | '.join(self.tail)[-300:]}"
                    return None
                m = re.search(r"Wrote (\S+\.wav)\s*$", msg)
                if m:
                    path = m.group(1)
                    try:
                        with open(path, "rb") as f:
                            return f.read()
                    finally:
                        os.remove(path)
            self.last_error = "piper timed out; restarting it"
            self.proc.kill()  # the supervisor restarts it
            return None

    def status(self):
        return {"up": self.alive() and self.up_since is not None, "up_since": self.up_since,
                "down_since": self.down_since, "restarts": max(self.restarts - 1, 0),
                "last_error": self.last_error}


piper = Piper(VOICE["piper"], VOICE["model"]) if ENABLED else None
_last = {"error": None, "at": None}


def to_opus(wav):
    r = subprocess.run([VOICE["ffmpeg"], "-hide_banner", "-loglevel", "error", "-f", "wav", "-i", "pipe:0",
                        "-c:a", "libopus", "-b:a", "24k", "-f", "ogg", "pipe:1"],
                       input=wav, capture_output=True, timeout=TTS_TIMEOUT)
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg exited {r.returncode}: {r.stderr.decode(errors='replace')[-200:]}")
    return r.stdout


def speak(text):
    """data: URL of the spoken reply, or None (text-only)."""
    wav = piper.synth(text) if piper else None
    if wav is None:
        return None
    return "data:audio/ogg;base64," + base64.b64encode(to_opus(wav)).decode()


def start():
    if ENABLED:
        threading.Thread(target=piper.supervise, daemon=True, name="piper").start()


def status():
    if not ENABLED:
        return {"enabled": False}
    return {"enabled": True, "piper": piper.status(), "last_error": _last["error"], "last_error_at": _last["at"]}


def healthy():
    """Voice only fails /healthz when it is on and Piper has been down too long."""
    if not ENABLED or piper.down_since is None:
        return True
    return time.time() - piper.down_since < PIPER_DOWN_FAIL


# ── HTTP handlers (registered in server.POST_ROUTES) ────────────────────────

def _fail(stage, exc):
    _last["error"], _last["at"] = f"{stage}: {type(exc).__name__}: {exc}"[:300], time.time()


def _respond(handler, code, heard, reply, pending=None, extra=None):
    t = time.time()
    audio = None
    try:
        audio = speak(reply)
    except Exception as exc:
        _fail("tts", exc)
    body = {"heard": heard, "reply": reply, "pending": pending, "audio": audio, **(extra or {})}
    handler.json(code, body)
    return round((time.time() - t) * 1000)


def handle_voice(handler):
    if handler.refuse_unless_tailnet():
        return
    t0 = time.time()
    record = {"heard": None, "tools": [], "llm_turn_ms": [], "decision": None}
    try:
        try:
            audio = handler.read_body(MAX_AUDIO)
        except ValueError:
            return handler.json(413, {"error": f"recording over {MAX_AUDIO} bytes"})
        if not audio:
            return handler.json(400, {"error": "empty recording"})
        ctype = (handler.headers.get("Content-Type") or "audio/webm").split(";")[0].strip()
        query = dict(p.partition("=")[::2] for p in handler.path.partition("?")[2].split("&") if p)
        marks = {}
        try:
            t = time.time()
            heard = transcribe(audio, ctype)
            marks["stt_ms"] = round((time.time() - t) * 1000)
        except Exception as exc:
            _fail("whisper", exc)
            record["decision"] = "stt-failed"
            return handler.json(502, {"heard": None, "reply": "Sorry, I could not hear that.",
                                      "pending": None, "audio": None, "error": "transcription failed"})
        record["heard"] = heard
        if not heard:
            record["decision"] = "silence"
            marks["tts_ms"] = _respond(handler, 200, "", "I didn't catch that.")
            return
        pid = query.get("pending")
        if pid and (YES.match(heard) or NO.match(heard)):
            record["decision"] = confirm(handler, pid, "yes" if YES.match(heard) else "no", heard, record)
            return
        t = time.time()
        try:
            reply, pending = think(heard, record)
        except Exception as exc:
            _fail("dx2", exc)
            reply, pending = "Sorry, the assistant is not answering right now.", None
            record["decision"] = "llm-failed"
        marks["llm_ms"] = round((time.time() - t) * 1000)
        record["decision"] = record["decision"] or ("pending" if pending else "answered")
        record["reply"] = reply
        marks["tts_ms"] = _respond(handler, 200, heard, reply, pending)
        record.update(marks)
    finally:
        record["ms"] = round((time.time() - t0) * 1000)
        log("voice " + json.dumps(record, default=str))


def confirm(handler, pid, decision, heard, record):
    p = take_pending(pid)
    if p is None:
        _respond(handler, 410, heard, "That request expired. Please ask again.", extra={"error": "expired"})
        return "expired"
    record["actions"] = [{"tool": tool, "args": {k: v for k, v in args.items() if not k.startswith("_")}}
                           for tool, args in p["actions"]]
    if decision != "yes":
        _respond(handler, 200, heard, "Okay, I won't.")
        return "declined"
    try:
        reply = run_pending(pid, p)
    except Exception as exc:
        _fail("confirm", exc)
        _respond(handler, 502, heard, "Sorry, that didn't work.", extra={"error": str(exc)[:200]})
        return "failed"
    _respond(handler, 200, heard, reply)
    return "executed"


def handle_confirm(handler):
    if handler.refuse_unless_tailnet():
        return
    t0 = time.time()
    record = {"heard": None, "tools": [], "decision": None}
    try:
        try:
            body = json.loads(handler.read_body(4096) or b"{}")
        except ValueError:
            record["decision"] = "bad-request"
            return handler.json(400, {"error": "body must be JSON {id, decision}"})
        decision = body.get("decision") if isinstance(body, dict) else None
        if decision not in ("yes", "no"):
            record["decision"] = "bad-request"
            return handler.json(400, {"error": "decision must be yes or no"})
        record["decision"] = confirm(handler, body.get("id"), decision, None, record)
    finally:
        record["ms"] = round((time.time() - t0) * 1000)
        log("voice confirm " + json.dumps(record, default=str))


# ── web client UI (inserted by server.web_client) ───────────────────────────

def _silent_wav():
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        w.writeframes(b"\0\0" * 80)
    return "data:audio/wav;base64," + base64.b64encode(buf.getvalue()).decode()


SILENT = _silent_wav()

CLIENT_CSS = """
#mic{position:fixed;right:2.5vw;bottom:3vh;width:13vh;height:13vh;border-radius:50%;border:.5vh solid #000;
 background:#fff;color:#000;font:700 3vh sans-serif;z-index:3;display:flex;align-items:center;justify-content:center}
#mic svg{width:55%;height:55%}
#mic.rec{background:#000;color:#fff}
#mic.busy{opacity:.5}
#vo{position:fixed;left:6vw;right:6vw;bottom:19vh;background:#fff;border:.5vh solid #000;padding:2vh 2.5vw;
 font:3.2vh/1.3 sans-serif;z-index:2;display:none}
#vo.on{display:block}
#vo .st{font-weight:700}
#vo .heard{font-style:italic;margin-top:1vh}
#vo .reply{font-size:4vh;margin-top:1vh}
#vo .yn{display:none;gap:3vw;margin-top:2vh}
#vo .yn.on{display:flex}
#vo button{flex:1;font:700 4vh sans-serif;padding:1.5vh 0;border:.5vh solid #000;background:#fff;color:#000}
#vo button.yes{background:#000;color:#fff}
"""

CLIENT_HTML = """<div id="vo" role="status" aria-live="polite"><div class="st"></div><div class="heard"></div>
<div class="reply"></div><div class="yn"><button class="yes" type="button">Yes</button><button class="no" type="button">No</button></div></div>
<button id="mic" type="button" aria-label="talk"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
<path d="M12 15a4 4 0 0 0 4-4V5a4 4 0 0 0-8 0v6a4 4 0 0 0 4 4zm7-4a1 1 0 1 0-2 0 5 5 0 0 1-10 0 1 1 0 1 0-2 0 7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11z"/></svg></button>
<audio id="va" preload="none"></audio>"""

# One inline script, no external JS. ES2017 (the tablet runs WebView 108).
CLIENT_JS = """(function(){
var HERE=%(here)s, WAIT=%(wait)d*1000, SILENT=%(silent)s, MAXREC=15000, SHOW=20000, PTTL=%(pttl)d*1000;
var mic=document.getElementById('mic'), vo=document.getElementById('vo'), va=document.getElementById('va');
var st=vo.querySelector('.st'), heard=vo.querySelector('.heard'), reply=vo.querySelector('.reply'), yn=vo.querySelector('.yn');
var state='idle', rec=null, chunks=[], stopT=null, hideT=null, pending=null, pendingAt=0;
function unlock(){ try{ va.src=SILENT; var p=va.play(); if(p&&p.catch)p.catch(function(){}); }catch(e){} }
function show(s,h,r){ st.textContent=s||''; heard.textContent=h?('\\u201c'+h+'\\u201d'):''; reply.textContent=r||'';
  vo.className='on'; clearTimeout(hideT); if(state==='idle') hideT=setTimeout(hide,SHOW); }
function hide(){ if(state!=='idle'){return;} vo.className=''; yn.className='yn'; }
function setState(s){ state=s; mic.className=s==='rec'?'rec':(s==='busy'?'busy':''); }
function play(src){ if(!src)return; try{ va.src=src; var p=va.play(); if(p&&p.catch)p.catch(function(){}); }catch(e){} }
function done(j){ setState('idle'); pending=j.pending||null; pendingAt=pending?Date.now():0;
  yn.className=pending?'yn on':'yn'; show(j.error&&!j.reply?'Error':'',j.heard,j.reply||j.error||''); play(j.audio); }
function fail(msg){ setState('idle'); yn.className='yn'; show('',null,msg); }
function post(url,type,body){ setState('busy'); show('thinking\\u2026','','');
  return fetch(url,{method:'POST',headers:{'Content-Type':type},body:body,credentials:'same-origin'})
   .then(function(r){ return r.json().catch(function(){ return {reply:'Error '+r.status}; }); })
   .then(done, function(){ fail('Could not reach the server.'); }); }
function stop(){ clearTimeout(stopT); if(rec&&rec.state==='recording') rec.stop(); }
function start(){
  if(!navigator.mediaDevices||!navigator.mediaDevices.getUserMedia||!window.MediaRecorder){
    show('',null,'Voice is not available on this device (no microphone access).'); return; }
  setState('busy'); show('starting microphone\\u2026','','');
  navigator.mediaDevices.getUserMedia({audio:true}).then(function(stream){
    var type='audio/webm;codecs=opus', opts=MediaRecorder.isTypeSupported(type)?{mimeType:type}:{};
    chunks=[]; rec=new MediaRecorder(stream,opts);
    rec.ondataavailable=function(e){ if(e.data&&e.data.size) chunks.push(e.data); };
    rec.onstop=function(){ stream.getTracks().forEach(function(t){t.stop();});
      var blob=new Blob(chunks,{type:rec.mimeType||'audio/webm'}); rec=null;
      if(!blob.size){ fail('Nothing was recorded.'); return; }
      var q=(pending&&Date.now()-pendingAt<PTTL)?('?pending='+encodeURIComponent(pending.id)):'';
      post('/voice'+q,blob.type.split(';')[0]||'audio/webm',blob); };
    rec.start(); setState('rec'); show('listening\\u2026 tap to stop','','');
    stopT=setTimeout(stop,MAXREC);
  }, function(e){ fail('Microphone not allowed ('+(e&&e.name||'error')+').'); });
}
mic.addEventListener('click',function(ev){ ev.preventDefault(); unlock();
  if(state==='rec'){ stop(); } else if(state==='idle'){ start(); } });
function decide(d){ return function(ev){ ev.preventDefault(); unlock(); if(!pending||state!=='idle')return;
  var id=pending.id; pending=null; yn.className='yn';
  post('/voice/confirm','application/json',JSON.stringify({id:id,decision:d})); }; }
vo.querySelector('.yes').addEventListener('click',decide('yes'));
vo.querySelector('.no').addEventListener('click',decide('no'));
vo.addEventListener('click',function(ev){ ev.stopPropagation(); });
(function tick(){ setTimeout(function(){ if(state==='idle'&&vo.className!=='on'){ location.href=HERE; } else { WAIT=30000; tick(); } },WAIT); })();
})();"""


def client(here, wait):
    """(head, body) fragments for the web client; empty when voice is off."""
    if not ENABLED:
        return "", ""
    js = CLIENT_JS % {"here": json.dumps(here), "wait": wait, "silent": json.dumps(SILENT), "pttl": PENDING_TTL}
    return f"<style>{CLIENT_CSS}</style>", f"{CLIENT_HTML}<script>{js}</script>"
