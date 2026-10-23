"""
Transcripts — hwc-server
FastAPI service that saves YouTube transcripts and X posts/threads as Markdown.
"""

import asyncio
import logging
import os
import shutil
import uuid
import httpx
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, BackgroundTasks, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field, field_validator
import uvicorn

from transcript import (
    TranscriptError, extract_video_id, is_playlist_url, fetch_metadata, fetch_playlist,
    fetch_captions, transcribe_audio, clean_transcript, raw_transcript, format_markdown,
    format_duration, saved_video_id,
    audio_budget, AUDIO_PROVIDER, AUDIO_PROVIDER_LABEL, DEEPGRAM_CHUNK_TIMEOUT,
)
import xbrowser
import xpost

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

# The composition root owns configuration and credential reads. Only the key
# file path enters the environment; the adapter receives the key explicitly.
DEEPGRAM_KEY_FILE = os.getenv("YT_TRANSCRIPTS_DEEPGRAM_KEY_FILE", "")
DEEPGRAM_MODEL = os.getenv("YT_TRANSCRIPTS_DEEPGRAM_MODEL", "")
DEEPGRAM_MAX_SECONDS = int(os.getenv("YT_TRANSCRIPTS_DEEPGRAM_MAX_SECONDS", "0"))
# One audio job at a time. At capacity reject, rather than queue billed work.
_audio_lock = asyncio.Lock()


def read_deepgram_key() -> str:
    try:
        key = Path(DEEPGRAM_KEY_FILE).read_text().strip()
    except (OSError, UnicodeError):
        raise TranscriptError("deepgram_failed", "API key file is unreadable") from None
    if not key or any(c.isspace() for c in key):
        raise TranscriptError("deepgram_failed", "API key file is empty or malformed")
    return key

# English translation of non-English X posts through DX2. An empty URL
# disables it and posts save in their original language.
DX2_URL = os.getenv("YT_TRANSCRIPTS_DX2_URL", "")
DX2_KEY_FILE = os.getenv("YT_TRANSCRIPTS_DX2_KEY_FILE", "")
translator = (xpost.dx2_translator(DX2_URL, os.getenv("YT_TRANSCRIPTS_DX2_MODEL", "llm"), DX2_KEY_FILE)
              if DX2_URL else None)

# Wall-clock budgets. /transcript is synchronous and captions-only, so it keeps
# the old 60 s ceiling; job videos bound each stage separately instead
# (metadata 20 s inside fetch_metadata, captions CAPTION_TIMEOUT, audio bounded
# by its download/conversion budgets and the number of HTTP upload chunks).
VIDEO_TIMEOUT = 60
CAPTION_TIMEOUT = 75
POST_TIMEOUT = 120  # an X thread walk: up to xpost.MAX_THREAD posts, ~1 s each
# A logged-in capture: the scroll budget plus browser start, page load and the
# wait for its first response.
CAPTURE_TIMEOUT = xbrowser.CAPTURE_BUDGET_SECONDS + 90

# Pause between videos in a job, so a batch is not a burst.
PACE_SECONDS = 2.0

# HTTP status for each failure reason on the synchronous /transcript endpoint.
STATUS_FOR_REASON = {"invalid_url": 400, "no_captions": 404, "unavailable": 404,
                     "rate_limited": 503, "timeout": 504, "login_required": 409}

app = FastAPI(title="Transcripts", version="4.2.0")


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class TranscriptRequest(BaseModel):
    url: str
    mode: str = Field(default="", description="clean or raw")


class XOptions(BaseModel):
    """What to save from an X post; ignored for YouTube URLs."""
    x_mode: str = Field(default="post", description="one of xpost.X_MODES")
    limit: int = Field(default=xpost.REPLY_LIMIT_DEFAULT, ge=1, le=xpost.REPLY_LIMIT_MAX,
                       description="direct replies to save in `replies` mode")

    @field_validator("x_mode")
    @classmethod
    def _known_mode(cls, value: str) -> str:
        if value not in xpost.X_MODES:
            raise ValueError(f"must be one of {', '.join(xpost.X_MODES)}")
        return value


class PostRequest(XOptions):
    url: str


class JobRequest(XOptions):
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
    url: str        # canonical watch URL or X post URL
    dest: Path      # folder the transcript is written to
    playlist: str   # playlist title, "" for a single video
    x_mode: str = "post"                     # X posts only; retry replays these two
    limit: int = xpost.REPLY_LIMIT_DEFAULT


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

# Item keys (see item_key) being extracted right now, across all jobs. The check and the add
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


def item_key(url: str, x_mode: str = "post") -> str | None:
    """Library key of a URL: the YouTube video ID, or xpost.x_key for an X
    post. X is checked first, so a YouTube link quoted inside a post URL never wins."""
    post_id = xpost.extract_post_id(url)
    return xpost.x_key(post_id, x_mode) if post_id else extract_video_id(url)


def saved_key(header: str) -> str | None:
    """Library key of a saved file, read from its header."""
    return xpost.saved_x_key(header) or saved_video_id(header)


def _read_header(path: Path) -> str:
    with path.open(encoding="utf-8", errors="replace") as fh:
        return fh.read(HEADER_BYTES)


def scan_saved(roots: list[Path]) -> dict[str, Path]:
    """Map item key -> first saved file, across every save location."""
    index: dict[str, Path] = {}
    for root in roots:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.md")):
            try:
                key = saved_key(_read_header(path))
            except OSError:
                continue
            if key:
                index.setdefault(key, path)
    return index


def _saved_result(url: str, path: Path, playlist: str) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    title = next((l[2:].strip() for l in text.splitlines() if l.startswith("# ")), path.stem)
    body = text.split("\n---\n", 1)[1].strip() if "\n---\n" in text else text
    return {"url": url, "title": title, "filename": str(path), "transcript": body,
            "status": "exists", "playlist": playlist}


def write_transcript(out_dir: Path, title: str, key: str, md: str) -> Path:
    """Write atomically (temp file + rename, so a half-written file is never
    indexed). A same-day, same-title file of a different item keeps its name;
    this one gets the item's ID appended instead of overwriting it."""
    safe_title = "".join(c if c.isalnum() or c in " -_" else "" for c in title)[:80].strip()
    stem = f"{datetime.now().strftime('%Y-%m-%d')} - {safe_title}"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{stem}.md"
    if path.exists() and saved_key(_read_header(path)) != key:
        path = out_dir / f"{stem} [{key.removeprefix('x:').replace(':', ' ')}].md"
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(md, encoding="utf-8")
    os.replace(tmp, path)
    return path


# ---------------------------------------------------------------------------
# Core extraction
# ---------------------------------------------------------------------------
async def _extract(url: str, mode: str, out_dir: Path, allow_audio: bool = False,
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
        if not (allow_audio and DEEPGRAM_KEY_FILE) or caption_failure.reason == "unavailable":
            raise caption_failure
        captions_said = f"captions: {caption_failure.reason}"
        if meta.duration > DEEPGRAM_MAX_SECONDS:
            raise TranscriptError("too_long", f"{format_duration(meta.duration)} is over the "
                                  f"{format_duration(DEEPGRAM_MAX_SECONDS)} limit; {captions_said}")
        if _audio_lock.locked():
            raise TranscriptError("transcription_busy")
        budget = audio_budget(meta.duration or DEEPGRAM_MAX_SECONDS)
        logger.info(f"{video_id}: {captions_said}; transcribing audio with Deepgram (budget {budget:.0f}s)")
        try:
            async with _audio_lock:
                key = read_deepgram_key()
                async with httpx.AsyncClient(timeout=DEEPGRAM_CHUNK_TIMEOUT, trust_env=False) as client:
                    transcript = await asyncio.wait_for(
                        transcribe_audio(video_id, key, DEEPGRAM_MODEL, on_stage,
                                         client=client, max_seconds=DEEPGRAM_MAX_SECONDS), timeout=budget)
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
        "transcription_request_ids": transcript.request_ids,
    }


@dataclass
class XResult:
    thread: list[dict]         # the post, with the author's thread around it in `thread` mode
    listed: list[dict] | None  # the replies / author's replies section, None for post/thread
    coverage: str              # xpost.coverage of `listed`


async def _thread_above(post_id: str, on_stage) -> list[dict]:
    """The logged-out walk: the post and the author's thread above it. Runs in
    a worker thread; MAX_THREAD and the per-request HTTP timeout bound it,
    POST_TIMEOUT bounds the wait."""
    try:
        return await asyncio.wait_for(asyncio.to_thread(xpost.fetch_thread, post_id, on_stage),
                                      timeout=POST_TIMEOUT)
    except asyncio.TimeoutError:
        raise TranscriptError("timeout", f"X thread walk passed {POST_TIMEOUT}s")


async def _fetch_x(post_id: str, x_mode: str, limit: int, on_stage=lambda stage: None) -> XResult:
    """What one X mode saves. `post` is the logged-out walk; the other modes
    read the conversation through the logged-in browser (xbrowser.capture)."""
    if x_mode == "post":
        return XResult(await _thread_above(post_id, on_stage), None, "")
    try:
        cap = await asyncio.wait_for(xbrowser.capture(post_id, x_mode, limit, on_stage),
                                     timeout=CAPTURE_TIMEOUT)
    except asyncio.TimeoutError:
        raise TranscriptError("timeout", f"X capture passed {CAPTURE_TIMEOUT}s")
    conv = cap.conversation
    focal = conv.posts.get(post_id) or await asyncio.to_thread(xpost.fetch_post, post_id)
    handle = focal["author"]["handle"] or ""
    if x_mode == "thread":
        above = await _thread_above(post_id, on_stage)
        return XResult(above + xpost.author_thread_below(conv, post_id, handle), None, "")
    if x_mode == "replies":
        listed = xpost.direct_replies(conv, post_id)[:limit]
        total = focal["metrics"]["replies"]
    else:
        listed = xpost.author_posts(conv, post_id, handle)
        total = None
    return XResult([focal], listed, xpost.coverage(total, cap.reached_end, cap.hit_limit, cap.hit_budget))


async def _extract_post(url: str, out_dir: Path, x_mode: str = "post",
                        limit: int = xpost.REPLY_LIMIT_DEFAULT, on_stage=lambda stage: None) -> dict:
    """Save one X post in one mode (xpost.X_MODES) into out_dir."""
    post_id = xpost.extract_post_id(url)
    if not post_id:
        raise TranscriptError("invalid_url")
    x = await _fetch_x(post_id, x_mode, limit, on_stage)
    translated = ""
    if translator:
        posts = x.thread + (x.listed or [])
        translated = (await asyncio.to_thread(xpost.translate_posts, posts, translator, on_stage)).note()

    on_stage("writing file")
    md = xpost.format_markdown(x.thread, post_id, x_mode, x.listed, x.coverage, translated)
    title = xpost.post_title(x.thread, x_mode)
    filepath = write_transcript(out_dir, title, xpost.x_key(post_id, x_mode), md)
    return {
        "url": x.thread[-1]["url"],
        "title": title,
        "channel": f"@{x.thread[0]['author']['handle']}",
        "transcript": md.split("\n---\n", 1)[1].strip(),
        "filename": str(filepath),
        "source": "x",
        "x_mode": x_mode,
        "posts": len(x.thread),
        "listed": None if x.listed is None else len(x.listed),
    }


# ---------------------------------------------------------------------------
# POST /transcript — single video, default location (n8n integration path)
# ---------------------------------------------------------------------------
@app.post("/transcript")
async def post_transcript(body: TranscriptRequest):
    """Captions only: synchronous callers cannot wait minutes for Whisper.
    A video or post that is already saved anywhere returns the saved file instead."""
    key = item_key(body.url)
    if key:
        saved = (await asyncio.to_thread(scan_saved, OUTPUT_ROOTS)).get(key)
        if saved:
            return _saved_result(_canonical_url(key), saved, "")
    try:
        if key and key.startswith("x:"):
            return await _extract_post(body.url, OUTPUT_ROOTS[0])
        return await asyncio.wait_for(_extract(body.url, body.mode, OUTPUT_ROOTS[0]), timeout=VIDEO_TIMEOUT)
    except asyncio.TimeoutError:
        raise HTTPException(504, f"Extraction timed out ({VIDEO_TIMEOUT}s limit)")
    except TranscriptError as e:
        logger.warning(f"/transcript {body.url}: {e.reason}: {e.detail}")
        raise HTTPException(STATUS_FOR_REASON.get(e.reason, 500), str(e))


def _canonical_url(key: str) -> str:
    if key.startswith("x:"):
        return xpost.post_url(key[2:])
    return f"https://www.youtube.com/watch?v={key}"


# ---------------------------------------------------------------------------
# POST /xpost — an X post and its thread as JSON; writes nothing
# ---------------------------------------------------------------------------
@app.post("/xpost")
async def post_xpost(body: PostRequest):
    post_id = xpost.extract_post_id(body.url)
    if not post_id:
        raise HTTPException(400, str(TranscriptError("invalid_url")))
    try:
        x = await _fetch_x(post_id, body.x_mode, body.limit)
    except TranscriptError as e:
        raise HTTPException(STATUS_FOR_REASON.get(e.reason, 500), str(e))
    return {"id": post_id, "mode": body.x_mode, "count": len(x.thread), "posts": x.thread,
            "listed": x.listed, "coverage": x.coverage}


# ---------------------------------------------------------------------------
# POST /job + GET /job/{id} — batch of videos, playlists and X posts
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
    bg.add_task(_run_job, job.job_id, urls, [], body.mode, out_dir, body.force, body.x_mode, body.limit)
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
                   out_dir: Path, force: bool, x_mode: str = "post",
                   limit: int = xpost.REPLY_LIMIT_DEFAULT):
    """`x_mode`/`limit` apply to the X URLs in `urls`; `items` carry their own."""
    job = _jobs.get(job_id)
    if not job:
        return
    job.status = "running"
    retry = RetrySpec(urls=[], items=[], mode=mode, out_dir=out_dir, force=force)

    # Phase 1 — classify + expand. Playlists expand into their own titled
    # subfolder under out_dir.
    work: list[WorkItem] = list(items)
    for raw in urls:
        key = item_key(raw)
        if key:
            work.append(WorkItem(_canonical_url(key), out_dir, "", x_mode, limit))
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

    # The same item listed twice (or as a video and inside a playlist) runs once.
    seen: set[str] = set()
    unique: list[WorkItem] = []
    for item in work:
        key = item_key(item.url, item.x_mode)
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)
    work = unique
    job.total = job.completed + len(work)

    job.current = {"url": "", "stage": "checking saved transcripts"}
    saved = {} if force else await asyncio.to_thread(scan_saved, OUTPUT_ROOTS)

    # Phase 2 — extract each item sequentially, paced (rate-limit friendly).
    fetched_any = False
    for item in work:
        key = item_key(item.url, item.x_mode)
        if key in saved:
            job.results.append(_saved_result(item.url, saved[key], item.playlist))
            job.completed += 1
            continue
        if key in _inflight:
            job.results.append({"url": item.url, "status": "duplicate", "playlist": item.playlist,
                                "note": "Already being extracted by another job"})
            job.completed += 1
            continue

        if fetched_any:
            await asyncio.sleep(PACE_SECONDS)
        fetched_any = True

        def stage(name: str, _url: str = item.url) -> None:
            job.current = {"url": _url, "stage": name}

        _inflight.add(key)
        try:
            if key.startswith("x:"):
                result = await _extract_post(item.url, item.dest, item.x_mode, item.limit, on_stage=stage)
            else:
                result = await _extract(item.url, mode, item.dest, allow_audio=True, on_stage=stage)
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
            _inflight.discard(key)
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
    return {"roots": [str(r) for r in OUTPUT_ROOTS], "default_mode": DEFAULT_MODE,
            "x_modes": xpost.X_MODE_LABELS, "x_login_modes": sorted(xpost.LOGIN_MODES),
            "x_limit_default": xpost.REPLY_LIMIT_DEFAULT, "x_limit_max": xpost.REPLY_LIMIT_MAX,
            "audio_provider": {"id": AUDIO_PROVIDER, "label": AUDIO_PROVIDER_LABEL}}


# ---------------------------------------------------------------------------
# /x/session — the X login the browser captures use (imported cookies)
# ---------------------------------------------------------------------------
@app.get("/x/session")
async def get_x_session():
    return xbrowser.session_status()


@app.post("/x/session")
async def post_x_session(request: Request):
    body = await request.body()
    if len(body) > 64 * 1024:
        raise HTTPException(413, "Cookie export is larger than 64 KB")
    try:
        return await xbrowser.import_session(body.decode("utf-8", errors="replace"))
    except ValueError as e:
        raise HTTPException(400, str(e))


# ---------------------------------------------------------------------------
# GET /health
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    disk = shutil.disk_usage(OUTPUT_DIR) if OUTPUT_DIR.exists() else None
    return {
        "status": "healthy",
        "schema_version": 2,
        "disk_free_gb": round(disk.free / (1024**3), 1) if disk else None,
        "output_dir": str(OUTPUT_DIR),
        "output_roots": [str(r) for r in OUTPUT_ROOTS],
        "deepgram": {"enabled": bool(DEEPGRAM_KEY_FILE), "model": DEEPGRAM_MODEL or None,
                     "max_seconds": DEEPGRAM_MAX_SECONDS, "active": _audio_lock.locked()},
        # Additive health compatibility, permanent by design: old probes see
        # Whisper disabled; no Whisper execution/configuration path remains.
        "whisper": {"url": None, "model": None, "max_seconds": 0, "ffmpeg": shutil.which("ffmpeg")},
        "x_session": xbrowser.session_status(),
        "translate": {"url": DX2_URL or None},
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
<title>Transcripts</title>
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
  .badge.audio { background: #fef3c7; color: #92400e; }
  .badge { display: inline-block; background: #ede9fe; color: #6d28d9; border-radius: 5px;
           padding: .05rem .4rem; font-size: .68rem; margin-right: .35rem; vertical-align: middle; }
  .results .skip .title { color: #444; font-weight: 600; }
  .results .skip .path { color: #6b7280; }
  .badge.saved { background: #e0f2fe; color: #075985; }
  .badge.x { background: #111; color: #fff; }
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
<h1>Transcripts</h1>

<div class="card">
  <h2>URLs — YouTube videos or playlists, X posts (choose what to save under X capture)</h2>
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
    <div>
      <label>X capture</label>
      <select id="xmode" onchange="showLimit()"></select>
    </div>
    <div id="limitbox">
      <label>Replies to save (top-ranked first, max <span id="limitmax"></span>)</label>
      <input type="number" id="limit" min="1" style="width:100%;padding:.6rem .7rem;border-radius:7px;border:1px solid #ccc;font-size:.9rem">
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

<div class="card">
  <h2>X login — needed for replies and the author's full thread</h2>
  <div class="msg" id="xstatus">Checking…</div>
  <label>Log in to the spare X account in a browser, export its x.com cookies with a
    cookies.txt extension (Netscape format or JSON), and paste the file here.</label>
  <textarea id="xcookies" rows="4" style="width:100%;font-family:monospace;font-size:.75rem"
    placeholder="# Netscape HTTP Cookie File ..."></textarea>
  <button class="addbtn" onclick="importX()">Import X login</button>
</div>

<script>
const $=id=>document.getElementById(id);
let _results=[], _base=[], _jobId=null, _xmodes={post:'Post'}, _audioProvider=null;

function rowHtml() {
  return `<div class="urlrow">
    <input type="text" placeholder="Paste a YouTube or X URL..." class="u">
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
    _audioProvider=d.audio_provider;
    $('base').innerHTML=d.roots.map(p=>`<option value="${p}">${p}</option>`).join('');
    if(d.default_mode) $('mode').value=d.default_mode==='raw'?'raw':'clean';
    _xmodes=d.x_modes;
    $('xmode').innerHTML=Object.entries(d.x_modes).map(([v,l])=>
      `<option value="${v}">${l}${d.x_login_modes.includes(v)?' (needs X login)':''}</option>`).join('');
    $('limit').value=d.x_limit_default; $('limit').max=d.x_limit_max; $('limitmax').textContent=d.x_limit_max;
  } catch(e) {
    $('base').innerHTML='<option value="">(default)</option>';
    $('xmode').innerHTML='<option value="post">Post</option>';
  }
  showLimit();
}
function showLimit() { $('limitbox').style.visibility=$('xmode').value==='replies'?'visible':'hidden'; }
function xBadge(r) {
  if(r.x_mode&&r.x_mode!=='post'&&r.x_mode!=='thread') return `X ${_xmodes[r.x_mode]||r.x_mode} · ${r.listed}`;
  return r.posts>1?'X thread · '+r.posts:'X post';
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
        :r.source===_audioProvider?.id?`<span class="badge audio" title="No captions could be fetched; transcribed from the audio">${_audioProvider.label}</span>`
        :r.source==='x'?`<span class="badge x">${xBadge(r)}</span>`:'';
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
        subfolder:$('subfolder').value.trim(),force:$('force').checked,
        x_mode:$('xmode').value,limit:parseInt($('limit').value,10)||undefined})});
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

function showX(s) {
  $('xstatus').className='msg'+(s.linked?'':' err');
  $('xstatus').textContent=s.linked?('Logged in as @'+s.handle+' (imported '+(s.imported_at||'?')+')')
    :'Not logged in. Post captures work; replies need a login.';
}
async function loadX() {
  try { showX(await (await fetch('/x/session')).json()); }
  catch(e) { $('xstatus').textContent='X login status unavailable'; }
}
async function importX() {
  const text=$('xcookies').value.trim();
  if(!text) return;
  $('xstatus').className='msg'; $('xstatus').textContent='Checking the login with X (up to 30 s)...';
  try {
    const r=await fetch('/x/session',{method:'POST',headers:{'Content-Type':'text/plain'},body:text});
    const d=await r.json();
    if(!r.ok) throw new Error(d.detail||r.statusText);
    $('xcookies').value=''; showX(d);
  } catch(e) { $('xstatus').className='msg err'; $('xstatus').textContent=e.message; }
}

addRow();
loadConfig();
loadX();
</script>
</body>
</html>"""


if __name__ == "__main__":
    # Refuse to start with a fallback that cannot download/convert/authenticate.
    if DEEPGRAM_KEY_FILE:
        if not DEEPGRAM_MODEL or DEEPGRAM_MAX_SECONDS <= 0 or any(not shutil.which(tool) for tool in ("ffmpeg", "yt-dlp")):
            raise SystemExit("Deepgram needs a model, ffmpeg and yt-dlp")
        try:
            read_deepgram_key()
        except TranscriptError:
            raise SystemExit("Deepgram API key file is unreadable, empty or malformed") from None
    # X captures need the bundled Chromium.
    browsers = os.getenv("PLAYWRIGHT_BROWSERS_PATH", "")
    if not browsers or not any(Path(browsers).glob("chromium-*")):
        raise SystemExit(f"PLAYWRIGHT_BROWSERS_PATH has no Chromium: {browsers!r}")
    # Translation reads the DX2 key per request; an unreadable key would fail every one.
    if DX2_URL and not os.access(DX2_KEY_FILE, os.R_OK):
        raise SystemExit(f"YT_TRANSCRIPTS_DX2_URL is set but the key file is unreadable: {DX2_KEY_FILE!r}")
    uvicorn.run(app, host=HOST, port=PORT, workers=1, log_level="info")
