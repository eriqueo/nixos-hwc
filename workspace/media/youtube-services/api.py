"""
YouTube Transcript API — hwc-server
FastAPI service for extracting YouTube transcripts.
"""

import asyncio
import logging
import os
import shutil
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
import uvicorn

from transcript import (
    TranscriptError, extract_video_id, is_playlist_url, fetch_metadata, fetch_playlist,
    fetch_captions, transcribe_audio, clean_transcript, raw_transcript, format_markdown,
    format_duration, saved_video_id,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("transcripts")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
OUTPUT_DIR = Path(os.getenv("YT_TRANSCRIPTS_OUTPUT_DIR", "/mnt/media/transcripts"))
# Whitelisted base locations the user can save into. Colon-separated, set from
# Nix (`hwc.media.youtube.transcripts.outputRoots`). The systemd sandbox only
# grants ReadWritePaths to exactly these, so an out-of-list base fails to write —
# we reject it at the API boundary first so the error is clear, not an EACCES.
OUTPUT_ROOTS = [Path(p) for p in os.getenv("YT_TRANSCRIPTS_OUTPUT_ROOTS", str(OUTPUT_DIR)).split(":") if p]
if OUTPUT_DIR not in OUTPUT_ROOTS:
    OUTPUT_ROOTS.insert(0, OUTPUT_DIR)

HOST = os.getenv("YT_TRANSCRIPTS_HOST", "127.0.0.1")
PORT = int(os.getenv("YT_TRANSCRIPTS_PORT", "8100"))
DEFAULT_MODE = os.getenv("YT_TRANSCRIPTS_DEFAULT_MODE", "clean")
LANGUAGES = os.getenv("YT_TRANSCRIPTS_LANGUAGES", "en,en-US,en-GB").split(",")

# Whisper fallback. An empty URL disables it (Nix sets it only when the local
# whisper-server is enabled). Videos longer than WHISPER_MAX_SECONDS are not
# transcribed: at the measured ~10x real time a 3 h video holds the shared GPU
# server for ~18 min.
WHISPER_URL = os.getenv("YT_TRANSCRIPTS_WHISPER_URL", "")
WHISPER_MODEL = os.getenv("YT_TRANSCRIPTS_WHISPER_MODEL", "whisper")
WHISPER_MAX_SECONDS = int(os.getenv("YT_TRANSCRIPTS_WHISPER_MAX_SECONDS", "10800"))

# Wall-clock budgets. /transcript is synchronous and captions-only, so it keeps
# the old 60 s ceiling; job videos bound each stage separately instead
# (metadata 20 s inside fetch_metadata, captions CAPTION_TIMEOUT, Whisper a
# budget scaled by duration — 5x the measured 0.1 s per audio second, plus
# queueing behind other whisper-server users).
VIDEO_TIMEOUT = 60
CAPTION_TIMEOUT = 75
def whisper_budget(duration: int) -> float:
    return 120 + duration * 0.5

# Pause between videos in a job, so a batch is not a burst.
PACE_SECONDS = 2.0

# HTTP status for each failure reason on the synchronous /transcript endpoint.
STATUS_FOR_REASON = {"invalid_url": 400, "no_captions": 404, "unavailable": 404,
                     "rate_limited": 503, "timeout": 504}

app = FastAPI(title="YouTube Transcripts", version="4.0.0")


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class TranscriptRequest(BaseModel):
    url: str
    mode: str = Field(default="", description="clean or raw")


class JobRequest(BaseModel):
    urls: list[str]
    mode: str = Field(default="")
    base: str = Field(default="", description="one of OUTPUT_ROOTS; blank = first root")
    subfolder: str = Field(default="", description="optional named folder under base")
    force: bool = Field(default=False, description="re-extract videos that are already saved")


class JobStatus(BaseModel):
    job_id: str
    status: str = "queued"
    completed: int = 0
    total: int = 0
    output_dir: str = ""
    results: list[dict] = Field(default_factory=list)
    current: dict = Field(default_factory=dict, description="{url, stage} of the video in progress")
    retryable: int = Field(default=0, description="failed items POST /job/{id}/retry would re-run")
    error: str = ""


# ---------------------------------------------------------------------------
# Job store — in memory, newest MAX_JOBS kept
# ---------------------------------------------------------------------------
MAX_JOBS = 200


@dataclass
class WorkItem:
    url: str        # canonical watch URL
    dest: Path      # folder the transcript is written to
    playlist: str   # playlist title, "" for a single video


@dataclass
class RetrySpec:
    """What POST /job/{id}/retry re-runs. Held server-side so a retry never
    takes a save path from the client."""
    urls: list[str]        # playlist URLs whose expansion failed
    items: list[WorkItem]  # videos whose extraction failed
    mode: str
    out_dir: Path
    force: bool


_jobs: dict[str, JobStatus] = {}
_retry_specs: dict[str, RetrySpec] = {}

# Video IDs being extracted right now, across all jobs. The check and the add
# happen with no await between them, so on the single event loop a video can
# never be extracted by two jobs at once.
_inflight: set[str] = set()


def _new_job(output_dir: Path) -> JobStatus:
    job = JobStatus(job_id=uuid.uuid4().hex[:12], output_dir=str(output_dir))
    _jobs[job.job_id] = job
    while len(_jobs) > MAX_JOBS:  # dicts keep insertion order: drop the oldest
        old = next(iter(_jobs))
        del _jobs[old]
        _retry_specs.pop(old, None)
    return job


# ---------------------------------------------------------------------------
# Output-path resolution (whitelist base + sanitized subfolder)
# ---------------------------------------------------------------------------
def _sanitize_component(name: str) -> str:
    """Sanitize a user-supplied folder name into safe path segments.

    Splits on `/` so a nested name like 'woodworking/lathe' is allowed, drops
    empty/`.`/`..` segments (no traversal), and strips odd characters per
    segment. Returns a relative path string (possibly empty).
    """
    parts = []
    for seg in name.strip().replace("\\", "/").split("/"):
        seg = seg.strip()
        if not seg or seg in (".", ".."):
            continue
        seg = "".join(c if (c.isalnum() or c in " -_.") else "_" for c in seg)[:100].strip()
        if seg:
            parts.append(seg)
    return "/".join(parts)


def resolve_base(base: str) -> Path:
    """Return the whitelisted root matching `base`, or the default root if blank."""
    if not base:
        return OUTPUT_ROOTS[0]
    candidate = Path(base)
    for root in OUTPUT_ROOTS:
        if candidate == root:
            return root
    allowed = ", ".join(str(r) for r in OUTPUT_ROOTS)
    raise ValueError(f"Base '{base}' is not an allowed location. Allowed: {allowed}")


def resolve_output_dir(base: str, subfolder: str) -> Path:
    """Resolve base + subfolder to an absolute dir contained within the base root."""
    root = resolve_base(base).resolve()
    sub = _sanitize_component(subfolder)
    out = (root / sub).resolve() if sub else root
    if out != root and root not in out.parents:
        raise ValueError("Resolved path escapes the allowed location")
    return out


# ---------------------------------------------------------------------------
# Saved-transcript library (idempotency). The files are the source of truth:
# the index is rebuilt from their headers whenever it is needed, never stored.
# ---------------------------------------------------------------------------
HEADER_BYTES = 2048


def _read_header(path: Path) -> str:
    with path.open(encoding="utf-8", errors="replace") as fh:
        return fh.read(HEADER_BYTES)


def scan_saved(roots: list[Path]) -> dict[str, Path]:
    """Map video ID -> first saved transcript, across every save location."""
    index: dict[str, Path] = {}
    for root in roots:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.md")):
            try:
                video_id = saved_video_id(_read_header(path))
            except OSError:
                continue
            if video_id:
                index.setdefault(video_id, path)
    return index


def _saved_result(url: str, path: Path, playlist: str) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    title = next((l[2:].strip() for l in text.splitlines() if l.startswith("# ")), path.stem)
    body = text.split("\n---\n", 1)[1].strip() if "\n---\n" in text else text
    return {"url": url, "title": title, "filename": str(path), "transcript": body,
            "status": "exists", "playlist": playlist}


def write_transcript(out_dir: Path, title: str, video_id: str, md: str) -> Path:
    """Write atomically (temp file + rename, so a half-written file is never
    indexed). A same-day, same-title file of a different video keeps its name;
    this one gets the video ID appended instead of overwriting it."""
    safe_title = "".join(c if c.isalnum() or c in " -_" else "" for c in title)[:80].strip()
    stem = f"{datetime.now().strftime('%Y-%m-%d')} - {safe_title}"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{stem}.md"
    if path.exists() and saved_video_id(_read_header(path)) != video_id:
        path = out_dir / f"{stem} [{video_id}].md"
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(md, encoding="utf-8")
    os.replace(tmp, path)
    return path


# ---------------------------------------------------------------------------
# Core extraction
# ---------------------------------------------------------------------------
async def _extract(url: str, mode: str, out_dir: Path, allow_whisper: bool = False,
                   on_stage=lambda stage: None) -> dict:
    """Extract one video's transcript and write it into out_dir. Returns result dict.

    Raises TranscriptError; every failure carries one reason from REASON_TEXT.
    """
    video_id = extract_video_id(url)
    if not video_id:
        raise TranscriptError("invalid_url")

    on_stage("fetching metadata")
    try:
        meta = await fetch_metadata(video_id)
    except asyncio.TimeoutError:
        raise TranscriptError("timeout", "metadata")

    on_stage("fetching captions")
    caption_failure = None
    try:
        transcript = await asyncio.wait_for(fetch_captions(video_id, LANGUAGES), timeout=CAPTION_TIMEOUT)
    except asyncio.TimeoutError:
        caption_failure = TranscriptError("timeout", "caption sources")
    except TranscriptError as e:
        caption_failure = e

    if caption_failure:
        if not (allow_whisper and WHISPER_URL) or caption_failure.reason == "unavailable":
            raise caption_failure
        captions_said = f"captions: {caption_failure.reason}"
        if meta.duration > WHISPER_MAX_SECONDS:
            raise TranscriptError("too_long", f"{format_duration(meta.duration)} is over the "
                                  f"{format_duration(WHISPER_MAX_SECONDS)} limit; {captions_said}")
        budget = whisper_budget(meta.duration)
        logger.info(f"{video_id}: {captions_said}; transcribing audio with Whisper (budget {budget:.0f}s)")
        try:
            transcript = await asyncio.wait_for(
                transcribe_audio(video_id, WHISPER_URL, WHISPER_MODEL, on_stage), timeout=budget)
        except asyncio.TimeoutError:
            raise TranscriptError("timeout", f"audio transcription passed {budget:.0f}s; {captions_said}")
        except TranscriptError as e:
            raise TranscriptError(e.reason, f"{e.detail}; {captions_said}")

    on_stage("writing file")
    segments = transcript.segments
    mode = mode if mode in ("clean", "raw") else DEFAULT_MODE
    text = raw_transcript(segments) if mode == "raw" else clean_transcript(segments)

    md = format_markdown(meta, text, transcript.source)
    filepath = write_transcript(out_dir, meta.title, video_id, md)

    return {
        "url": meta.url,
        "title": meta.title,
        "channel": meta.channel,
        "duration": f"{meta.duration}s",
        "transcript": text,
        "filename": str(filepath),
        "source": transcript.kind,
    }


# ---------------------------------------------------------------------------
# POST /transcript — single video, default location (n8n integration path)
# ---------------------------------------------------------------------------
@app.post("/transcript")
async def post_transcript(body: TranscriptRequest):
    """Captions only: synchronous callers cannot wait minutes for Whisper.
    A video that is already saved anywhere returns the saved file instead."""
    video_id = extract_video_id(body.url)
    if video_id:
        saved = (await asyncio.to_thread(scan_saved, OUTPUT_ROOTS)).get(video_id)
        if saved:
            return _saved_result(f"https://www.youtube.com/watch?v={video_id}", saved, "")
    try:
        return await asyncio.wait_for(_extract(body.url, body.mode, OUTPUT_ROOTS[0]), timeout=VIDEO_TIMEOUT)
    except asyncio.TimeoutError:
        raise HTTPException(504, f"Extraction timed out ({VIDEO_TIMEOUT}s limit)")
    except TranscriptError as e:
        logger.warning(f"/transcript {body.url}: {e.reason}: {e.detail}")
        raise HTTPException(STATUS_FOR_REASON.get(e.reason, 500), str(e))


# ---------------------------------------------------------------------------
# POST /job + GET /job/{id} — batch of videos and/or playlists
# ---------------------------------------------------------------------------
@app.post("/job")
async def post_job(body: JobRequest, bg: BackgroundTasks):
    urls = [u.strip() for u in body.urls if u.strip()]
    if not urls:
        raise HTTPException(400, "No URLs provided")
    try:
        out_dir = resolve_output_dir(body.base, body.subfolder)
    except ValueError as e:
        raise HTTPException(400, str(e))

    job = _new_job(out_dir)
    bg.add_task(_run_job, job.job_id, urls, [], body.mode, out_dir, body.force)
    return {"job_id": job.job_id, "status": "queued", "output_dir": str(out_dir)}


@app.post("/job/{job_id}/retry")
async def retry_job(job_id: str, bg: BackgroundTasks):
    """Re-run a finished job's failed items into their original folders."""
    job, spec = _jobs.get(job_id), _retry_specs.get(job_id)
    if job is None or spec is None:
        raise HTTPException(404, "Job not found. The service may have restarted; submit the URLs again.")
    if not (spec.urls or spec.items):
        raise HTTPException(400, "Nothing to retry")
    new = _new_job(spec.out_dir)
    bg.add_task(_run_job, new.job_id, spec.urls, spec.items, spec.mode, spec.out_dir, spec.force)
    return {"job_id": new.job_id, "status": "queued", "output_dir": str(spec.out_dir)}


def _failure(url: str, e: TranscriptError, playlist: str, prefix: str = "") -> dict:
    # An invalid URL fails the same way every time; everything else may not.
    return {"url": url, "error": prefix + str(e), "reason": e.reason, "playlist": playlist,
            "retryable": e.reason != "invalid_url"}


async def _run_job(job_id: str, urls: list[str], items: list[WorkItem], mode: str,
                   out_dir: Path, force: bool):
    job = _jobs.get(job_id)
    if not job:
        return
    job.status = "running"
    retry = RetrySpec(urls=[], items=[], mode=mode, out_dir=out_dir, force=force)

    # Phase 1 — classify + expand. Playlists expand into their own titled
    # subfolder under out_dir.
    work: list[WorkItem] = list(items)
    for raw in urls:
        video_id = extract_video_id(raw)
        if video_id:
            work.append(WorkItem(f"https://www.youtube.com/watch?v={video_id}", out_dir, ""))
        elif is_playlist_url(raw):
            try:
                pl = await fetch_playlist(raw)
            except Exception as e:
                err = e if isinstance(e, TranscriptError) else TranscriptError("error", f"{type(e).__name__}: {e}")
                job.results.append(_failure(raw, err, "", prefix="Playlist: "))
                retry.urls.append(raw)
                job.completed += 1
                continue
            if not pl.video_ids:
                job.results.append(_failure(raw, TranscriptError("unavailable", "playlist has no videos"), pl.title))
                retry.urls.append(raw)
                job.completed += 1
                continue
            dest = out_dir / (_sanitize_component(pl.title) or "playlist")
            for vid in pl.video_ids:
                work.append(WorkItem(f"https://www.youtube.com/watch?v={vid}", dest, pl.title))
        else:
            job.results.append(_failure(raw, TranscriptError("invalid_url"), ""))
            job.completed += 1

    # The same video listed twice (or as a video and inside a playlist) runs once.
    seen: set[str] = set()
    unique: list[WorkItem] = []
    for item in work:
        video_id = extract_video_id(item.url)
        if video_id in seen:
            continue
        seen.add(video_id)
        unique.append(item)
    work = unique
    job.total = job.completed + len(work)

    job.current = {"url": "", "stage": "checking saved transcripts"}
    saved = {} if force else await asyncio.to_thread(scan_saved, OUTPUT_ROOTS)

    # Phase 2 — extract each video sequentially, paced (rate-limit friendly).
    fetched_any = False
    for item in work:
        video_id = extract_video_id(item.url)
        if video_id in saved:
            job.results.append(_saved_result(item.url, saved[video_id], item.playlist))
            job.completed += 1
            continue
        if video_id in _inflight:
            job.results.append({"url": item.url, "status": "duplicate", "playlist": item.playlist,
                                "note": "Already being extracted by another job"})
            job.completed += 1
            continue

        if fetched_any:
            await asyncio.sleep(PACE_SECONDS)
        fetched_any = True

        def stage(name: str, _url: str = item.url) -> None:
            job.current = {"url": _url, "stage": name}

        _inflight.add(video_id)
        try:
            result = await _extract(item.url, mode, item.dest, allow_whisper=True, on_stage=stage)
            result["playlist"] = item.playlist
            job.results.append(result)
        except TranscriptError as e:
            job.results.append(_failure(item.url, e, item.playlist))
            retry.items.append(item)
        except Exception as e:
            logger.exception(f"{item.url}: unexpected failure")
            job.results.append(_failure(item.url, TranscriptError("error", f"{type(e).__name__}: {e}"), item.playlist))
            retry.items.append(item)
        finally:
            _inflight.discard(video_id)
        job.completed += 1

    _retry_specs[job_id] = retry
    job.retryable = len(retry.urls) + len(retry.items)
    job.current = {}
    job.status = "complete"


@app.get("/job/{job_id}")
async def get_job(job_id: str):
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return job.model_dump()


# ---------------------------------------------------------------------------
# GET /config — locations + defaults for the UI
# ---------------------------------------------------------------------------
@app.get("/config")
async def config():
    return {"roots": [str(r) for r in OUTPUT_ROOTS], "default_mode": DEFAULT_MODE}


# ---------------------------------------------------------------------------
# GET /health
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    disk = shutil.disk_usage(OUTPUT_DIR) if OUTPUT_DIR.exists() else None
    return {
        "status": "healthy",
        "disk_free_gb": round(disk.free / (1024**3), 1) if disk else None,
        "output_dir": str(OUTPUT_DIR),
        "output_roots": [str(r) for r in OUTPUT_ROOTS],
        "whisper": {"url": WHISPER_URL or None, "model": WHISPER_MODEL,
                    "max_seconds": WHISPER_MAX_SECONDS, "ffmpeg": shutil.which("ffmpeg")},
    }


# ---------------------------------------------------------------------------
# GET / — Web UI
# ---------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
async def ui():
    return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>YouTube Transcripts</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f5f5f5; color: #222; padding: 1.5rem;
         display: flex; flex-direction: column; align-items: center; min-height: 100vh; }
  h1 { font-size: 1.3rem; margin-bottom: 1rem; }
  .card { background: #fff; border-radius: 10px; padding: 1.25rem; width: 100%; max-width: 720px;
          box-shadow: 0 1px 4px rgba(0,0,0,.1); margin-bottom: 1rem; }
  .card h2 { font-size: .9rem; color: #666; margin-bottom: .6rem; }
  label { display: block; font-size: .78rem; color: #666; margin-bottom: .25rem; }
  .urlrow { display: flex; gap: .4rem; margin-bottom: .5rem; }
  input[type=text], select { padding: .6rem .7rem; border-radius: 7px; border: 1px solid #ccc;
                             font-size: 1rem; outline: none; }
  input[type=text] { flex: 1; }
  input:focus, select:focus { border-color: #2563eb; }
  .urlrow .del { background: #f3f4f6; color: #6b7280; border: 1px solid #e5e7eb; border-radius: 7px;
                 min-width: 44px; font-size: 1.1rem; cursor: pointer; }
  .urlrow .del:hover { background: #fee2e2; color: #dc2626; }
  .addbtn { background: #eef2ff; color: #2563eb; border: 1px dashed #93c5fd; border-radius: 7px;
            padding: .55rem 1rem; font-size: .85rem; font-weight: 600; cursor: pointer; margin-bottom: 1rem; }
  .addbtn:hover { background: #e0e7ff; }
  .opts { display: grid; grid-template-columns: 1fr 2fr; gap: .6rem; margin-bottom: .5rem; }
  .opts .full { grid-column: 1 / -1; }
  .opts select, .opts input[type=text] { width: 100%; font-size: .9rem; }
  .go { padding: .7rem 1.4rem; border-radius: 7px; border: none; background: #2563eb; color: #fff;
        font-weight: 600; font-size: 1rem; cursor: pointer; min-height: 46px; width: 100%; margin-top: .4rem; }
  .go:hover { background: #1d4ed8; }
  .go:disabled { opacity: .5; cursor: wait; }
  .msg { font-size: .85rem; color: #666; min-height: 1.2em; margin: .6rem 0 .2rem; }
  .msg.err { color: #dc2626; }
  .results { list-style: none; margin-top: .3rem; }
  .results li { font-size: .85rem; padding: .5rem .1rem; border-bottom: 1px solid #f0f0f0;
                display: flex; gap: .5rem; align-items: flex-start; }
  .results .body { flex: 1; min-width: 0; }
  .results .ok .title { color: #111; font-weight: 600; }
  .results .path { color: #059669; word-break: break-all; font-size: .78rem; }
  .results .fail .title { color: #dc2626; }
  .results .fail .path { color: #b91c1c; }
  .badge.whisper { background: #fef3c7; color: #92400e; }
  .badge { display: inline-block; background: #ede9fe; color: #6d28d9; border-radius: 5px;
           padding: .05rem .4rem; font-size: .68rem; margin-right: .35rem; vertical-align: middle; }
  .results .skip .title { color: #444; font-weight: 600; }
  .results .skip .path { color: #6b7280; }
  .badge.saved { background: #e0f2fe; color: #075985; }
  .check { display: flex; gap: .4rem; align-items: center; font-size: .82rem; color: #444; }
  .check input { width: auto; }
  .retry { display: none; padding: .55rem 1rem; border-radius: 7px; border: 1px solid #fca5a5;
           background: #fef2f2; color: #b91c1c; font-weight: 600; cursor: pointer; margin-top: .4rem; }
  .copy { background: #e5e7eb; color: #222; border: none; border-radius: 6px; padding: .35rem .7rem;
          font-size: .78rem; cursor: pointer; }
  .copy:hover { background: #d1d5db; }
</style>
</head>
<body>
<h1>YouTube Transcripts</h1>

<div class="card">
  <h2>URLs — videos or playlists</h2>
  <div id="urls"></div>
  <button class="addbtn" id="add" onclick="addRow()">+ URL</button>

  <div class="opts">
    <div>
      <label>Format</label>
      <select id="mode">
        <option value="clean">Clean</option>
        <option value="raw">Raw</option>
      </select>
    </div>
    <div>
      <label>Save location</label>
      <select id="base"></select>
    </div>
    <div class="full">
      <label>Folder name (optional — nest with "/", e.g. woodworking/lathe)</label>
      <input type="text" id="subfolder" placeholder="leave blank to save in the location root">
    </div>
    <label class="check full"><input type="checkbox" id="force"> Re-extract videos that are already saved</label>
  </div>

  <button class="go" id="go" onclick="run()">Extract</button>
  <div class="msg" id="msg"></div>
  <button class="retry" id="retry" onclick="retry()"></button>
  <ul class="results" id="results"></ul>
</div>

<script>
const $=id=>document.getElementById(id);
let _results=[], _base=[], _jobId=null;

function rowHtml() {
  return `<div class="urlrow">
    <input type="text" placeholder="Paste a YouTube video or playlist URL..." class="u">
    <button class="del" onclick="delRow(this)" title="remove">&times;</button>
  </div>`;
}
function addRow() {
  $('urls').insertAdjacentHTML('beforeend', rowHtml());
  const rows=$('urls').querySelectorAll('.u');
  rows[rows.length-1].focus();
  rows[rows.length-1].addEventListener('keydown',e=>{if(e.key==='Enter')run();});
}
function delRow(btn) {
  const rows=$('urls').querySelectorAll('.urlrow');
  if(rows.length<=1){ btn.closest('.urlrow').querySelector('.u').value=''; return; }
  btn.closest('.urlrow').remove();
}

async function loadConfig() {
  try {
    const r=await fetch('/config'); const d=await r.json();
    $('base').innerHTML=d.roots.map(p=>`<option value="${p}">${p}</option>`).join('');
    if(d.default_mode) $('mode').value=d.default_mode==='raw'?'raw':'clean';
  } catch(e) { $('base').innerHTML='<option value="">(default)</option>'; }
}

function renderResults(status) {
  $('results').innerHTML='';
  _results.forEach((r,i)=>{
    const li=document.createElement('li');
    const badge=r.playlist?`<span class="badge">${r.playlist}</span>`:'';
    if(r.status==='duplicate'){
      li.className='skip';
      li.innerHTML=`<div class="body"><div class="title">${badge}${r.url}</div><div class="path">${r.note||''}</div></div>`;
    } else if(r.error){
      li.className='fail';
      li.innerHTML=`<div class="body"><div class="title">${badge}${r.url||''}</div><div class="path">${r.error}</div></div>`;
    } else {
      li.className='ok';
      if(r.status==='exists') li.className='skip';
      const src=r.status==='exists'?'<span class="badge saved" title="Found an existing transcript for this video; not fetched again">Already saved</span>'
        :r.source==='whisper'?'<span class="badge whisper" title="No captions could be fetched; transcribed from the audio">Whisper</span>':'';
      li.innerHTML=`<div class="body"><div class="title">${badge}${src}${r.title||''}</div><div class="path">${r.filename||''}</div></div>`;
      const b=document.createElement('button'); b.className='copy'; b.textContent='Copy';
      b.onclick=()=>{navigator.clipboard.writeText(_results[i].transcript||'');b.textContent='Copied!';setTimeout(()=>b.textContent='Copy',1200);};
      li.appendChild(b);
    }
    $('results').appendChild(li);
  });
}

function poll(jobId) {
  _jobId=jobId;
  const timer=setInterval(async()=>{
    const pr=await fetch('/job/'+jobId);
    if(!pr.ok) return;
    const pd=await pr.json();
    _results=_base.concat(pd.results);
    const totalTxt=pd.total?('/'+pd.total):'';
    const cur=(pd.current&&pd.current.stage)?' — '+pd.current.stage:'';
    $('msg').textContent=(pd.status==='complete'?'Done ':'Processing... ')
      +'('+pd.completed+totalTxt+') → '+pd.output_dir+cur;
    renderResults(pd.status);
    if(pd.status==='complete'){
      clearInterval(timer); $('go').disabled=false;
      $('retry').textContent='Retry failed ('+pd.retryable+')';
      $('retry').style.display=pd.retryable?'block':'none';
    }
  },1500);
}

async function run() {
  const urls=[...$('urls').querySelectorAll('.u')].map(i=>i.value.trim()).filter(Boolean);
  if(!urls.length){ $('msg').className='msg err'; $('msg').textContent='Add at least one URL.'; return; }
  $('go').disabled=true; $('retry').style.display='none'; _results=[]; _base=[];
  $('msg').className='msg'; $('msg').textContent='Submitting '+urls.length+' URL(s)...';
  $('results').innerHTML='';
  try {
    const r=await fetch('/job',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({urls,mode:$('mode').value,base:$('base').value,
        subfolder:$('subfolder').value.trim(),force:$('force').checked})});
    if(!r.ok){const e=await r.json();throw new Error(e.detail||r.statusText);}
    const d=await r.json();
    $('msg').textContent='Saving to '+d.output_dir+' — expanding...';
    poll(d.job_id);
  } catch(e) {
    $('msg').className='msg err'; $('msg').textContent=e.message; $('go').disabled=false;
  }
}

// Re-run the finished job's failed items; their new results replace the old
// failures in the list, everything that already worked stays.
async function retry() {
  $('retry').style.display='none'; $('go').disabled=true; $('msg').className='msg';
  try {
    const r=await fetch('/job/'+_jobId+'/retry',{method:'POST'});
    if(!r.ok){const e=await r.json();throw new Error(e.detail||r.statusText);}
    const d=await r.json();
    _base=_results.filter(x=>!x.retryable);
    poll(d.job_id);
  } catch(e) {
    $('msg').className='msg err'; $('msg').textContent=e.message; $('go').disabled=false;
  }
}

addRow();
loadConfig();
</script>
</body>
</html>"""


if __name__ == "__main__":
    # Refuse to run half-alive: the Whisper fallback shells out to ffmpeg.
    if WHISPER_URL and not shutil.which("ffmpeg"):
        raise SystemExit("YT_TRANSCRIPTS_WHISPER_URL is set but ffmpeg is not on PATH")
    uvicorn.run(app, host=HOST, port=PORT, workers=1, log_level="info")
