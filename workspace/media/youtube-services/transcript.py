"""
YouTube transcript extraction and cleaning.

Captions come from youtube-transcript-api, with yt-dlp subtitles as a fallback;
when neither yields captions, Deepgram transcribes the audio.
yt-dlp also supplies metadata. No NLP libraries, no LLM.
"""

import asyncio
import html
import sys
import json
import logging
import math
import os
import re
import tempfile
import time
import wave
from dataclasses import asdict, dataclass, field
from typing import Callable, Optional




logger = logging.getLogger("transcripts")


# ---------------------------------------------------------------------------
# Failure vocabulary — every per-video failure carries exactly one reason
# ---------------------------------------------------------------------------
REASON_TEXT = {
    "rate_limited": "YouTube is rate-limiting or blocking this server",
    "no_captions": "Video has no captions",
    "unavailable": "Unavailable (private, removed, age- or member-restricted)",
    "invalid_url": "Not a YouTube or X URL",
    "deepgram_failed": "Deepgram audio transcription failed",
    "transcription_busy": "Another audio transcription is running; retry this item when it finishes",
    "too_long": "Video is too long for audio transcription",
    "timeout": "Timed out",
    "login_required": "X login is missing or expired; import the cookies again",
    "error": "Unexpected error",
}


class TranscriptError(Exception):
    def __init__(self, reason: str, detail: str = ""):
        if reason not in REASON_TEXT:
            raise ValueError(f"unknown failure reason {reason!r}")
        self.reason = reason
        self.detail = detail
        super().__init__(REASON_TEXT[reason] + (f" — {detail}" if detail else ""))


# When several caption sources fail differently, the reported reason is the
# most telling one: the video itself being unavailable outranks a block, and
# a block outranks "no captions" because a blocked source never got to look.
_REASON_RANK = ["unavailable", "rate_limited", "error", "no_captions"]


def most_telling(failures: list[TranscriptError]) -> TranscriptError:
    return min(failures, key=lambda e: _REASON_RANK.index(e.reason) if e.reason in _REASON_RANK else len(_REASON_RANK))


def classify_ytdlp_error(stderr: str) -> TranscriptError:
    """Map yt-dlp stderr to a failure reason. Permanent by design: the yt-dlp
    CLI reports failures only as text, with no code that separates a 429 from
    a private video. Age checks precede the bot check: both say "Sign in to
    confirm", only one is about the video."""
    s = stderr.lower()
    errors = [line for line in stderr.splitlines() if line.startswith("ERROR")]
    detail = (errors[-1] if errors else stderr.strip().splitlines()[-1] if stderr.strip() else "")[:300]
    if "confirm your age" in s or "private video" in s or "video unavailable" in s \
            or "video is unavailable" in s \
            or "members-only" in s or "has been removed" in s:
        return TranscriptError("unavailable", detail)
    if "429" in s or "too many requests" in s or "not a bot" in s:
        return TranscriptError("rate_limited", detail)
    if "no subtitles" in s:
        return TranscriptError("no_captions", detail)
    return TranscriptError("error", detail)


async def _run(args: list[str], timeout: float) -> tuple[int, str, str]:
    """Run a subprocess; kill it if the caller is cancelled or it overruns, so a
    timed-out video never leaves yt-dlp or ffmpeg running behind it."""
    proc = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except BaseException:
        if proc.returncode is None:
            proc.kill()
            await proc.wait()
        raise
    return proc.returncode or 0, out.decode(errors="replace"), err.decode(errors="replace")


# ---------------------------------------------------------------------------
# Video ID extraction
# ---------------------------------------------------------------------------
_YT_PATTERNS = [
    re.compile(r"(?:youtube\.com/watch\?.*v=|youtu\.be/|youtube\.com/shorts/|youtube\.com/embed/)([a-zA-Z0-9_-]{11})"),
]


def extract_video_id(url: str) -> Optional[str]:
    for pat in _YT_PATTERNS:
        m = pat.search(url)
        if m:
            return m.group(1)
    return None


def is_playlist_url(url: str) -> bool:
    return "list=" in url


# ---------------------------------------------------------------------------
# Metadata via yt-dlp (single async call)
# ---------------------------------------------------------------------------
@dataclass
class VideoMeta:
    video_id: str
    title: str
    channel: str
    duration: int  # seconds
    upload_date: str  # YYYYMMDD
    url: str


async def fetch_metadata(video_id: str) -> VideoMeta:
    url = f"https://www.youtube.com/watch?v={video_id}"
    code, stdout, stderr = await _run(
        ["yt-dlp", "--dump-json", "--no-download", "--no-warnings", "-q", url], timeout=20,
    )
    if code != 0:
        raise classify_ytdlp_error(stderr)

    info = json.loads(stdout)
    return VideoMeta(
        video_id=video_id,
        title=info.get("title", "Unknown"),
        channel=info.get("channel", info.get("uploader", "Unknown")),
        duration=int(info.get("duration", 0)),
        upload_date=info.get("upload_date", ""),
        url=url,
    )


# ---------------------------------------------------------------------------
# Playlist expansion via yt-dlp (flat listing — IDs + title only, no per-video calls)
# ---------------------------------------------------------------------------
@dataclass
class PlaylistInfo:
    title: str
    video_ids: list[str]


async def fetch_playlist(url: str) -> PlaylistInfo:
    """Expand a playlist URL into its video IDs + the playlist title.

    Uses `--flat-playlist` so this is one cheap call that does NOT fetch each
    video; per-video metadata/transcripts are fetched later, one at a time.
    """
    code, stdout, stderr = await _run(
        ["yt-dlp", "--flat-playlist", "--dump-single-json", "--no-warnings", "-q", url], timeout=45,
    )
    if code != 0:
        raise classify_ytdlp_error(stderr)

    info = json.loads(stdout)
    entries = info.get("entries") or []
    video_ids = [e["id"] for e in entries if isinstance(e, dict) and e.get("id")]
    title = info.get("title") or info.get("id") or "playlist"
    return PlaylistInfo(title=title, video_ids=video_ids)


def format_duration(seconds: int) -> str:
    h, r = divmod(seconds, 3600)
    m, s = divmod(r, 60)
    if h:
        return f"{h}h {m:02d}m {s:02d}s"
    return f"{m}m {s:02d}s"


# ---------------------------------------------------------------------------
# Transcript sources: captions (youtube-transcript-api, then yt-dlp subtitles),
# then Deepgram over the audio. Each source returns segments or raises a
# TranscriptError carrying one reason from REASON_TEXT.
# ---------------------------------------------------------------------------
@dataclass
class Segment:
    text: str
    start: float
    duration: float


@dataclass
class Transcript:
    segments: list[Segment]
    source: str  # human label written into the markdown, e.g. "YouTube captions (auto-generated)"
    kind: str    # "captions" | "deepgram"
    request_ids: list[str] = field(default_factory=list)
    language: str | None = None
    model: str | None = None
    track: str | None = None
    generated: bool = False


# A 429 is per-IP, not per-video, so the cooldown is process-wide: after any
# source is rate-limited, the next caption request waits this long first.
RATE_LIMIT_COOLDOWN = 20.0
RATE_LIMIT_RETRY_DELAY = 10.0
_last_rate_limited: float = 0.0


def _note_rate_limit() -> None:
    global _last_rate_limited
    _last_rate_limited = time.monotonic()


async def _respect_cooldown() -> None:
    wait = _last_rate_limited + RATE_LIMIT_COOLDOWN - time.monotonic()
    if _last_rate_limited and wait > 0:
        logger.info(f"rate-limit cooldown: waiting {wait:.0f}s")
        await asyncio.sleep(wait)


async def fetch_captions(video_id: str, langs: list[str]) -> Transcript:
    """Captions only. youtube-transcript-api first (retried once after a block),
    then yt-dlp subtitles. Raises the most telling TranscriptError if both fail."""
    await _respect_cooldown()
    failures: list[TranscriptError] = []

    for attempt in range(2):
        try:
            return await _fetch_yta(video_id, langs)
        except TranscriptError as e:
            failures.append(e)
            logger.warning(f"{video_id}: youtube-transcript-api: {e.reason}: {e.detail}")
            if e.reason == "unavailable":
                raise
            if e.reason == "rate_limited" and attempt == 0:
                _note_rate_limit()
                await asyncio.sleep(RATE_LIMIT_RETRY_DELAY)
                continue
            break

    try:
        return await _try_ytdlp_subs(video_id, langs)
    except TranscriptError as e:
        failures.append(e)
        logger.warning(f"{video_id}: yt-dlp subtitles: {e.reason}: {e.detail}")

    if any(f.reason == "rate_limited" for f in failures):
        _note_rate_limit()
    raise most_telling(failures)


def _classify_yta_error(exc: Exception) -> TranscriptError:
    import youtube_transcript_api as yta
    from requests import Timeout
    if isinstance(exc, Timeout):
        return TranscriptError("timeout", "caption network request")
    name = type(exc).__name__
    if isinstance(exc, (yta.RequestBlocked, yta.PoTokenRequired)):
        return TranscriptError("rate_limited", name)
    if isinstance(exc, yta.YouTubeRequestFailed) and "429" in str(exc):
        return TranscriptError("rate_limited", name)
    if isinstance(exc, (yta.TranscriptsDisabled, yta.NoTranscriptFound)):
        return TranscriptError("no_captions", name)
    if isinstance(exc, (yta.VideoUnavailable, yta.VideoUnplayable, yta.AgeRestricted, yta.InvalidVideoId)):
        return TranscriptError("unavailable", name)
    return TranscriptError("error", f"{name}: {str(exc).strip().splitlines()[0][:200] if str(exc).strip() else ''}")


def select_track(tracks, langs):
    """Manual before generated; within each class use configured language order.
    Unrequested languages are never selected. Both providers share this policy.
    """
    return next((t for generated in (False, True) for lang in langs for t in tracks
                 if t["generated"] == generated and t["language"] == lang), None)


async def _fetch_yta(video_id: str, langs: list[str]) -> Transcript:
    # A subprocess provides a hard deadline even for a peer that trickles bytes.
    # _run kills and reaps it on cancellation; no abandoned executor threads.
    try:
        code, out, _ = await _run([sys.executable, os.path.abspath(__file__),
                                  video_id, json.dumps(langs)], timeout=25)
    except asyncio.TimeoutError:
        raise TranscriptError("timeout", "primary captions deadline") from None
    if code:
        raise TranscriptError("error", "primary caption worker failed")
    data = json.loads(out)
    if "error" in data:
        raise TranscriptError(data["error"], data["detail"])
    data["segments"] = [Segment(**s) for s in data["segments"]]
    return Transcript(**data)


def _fetch_yta_sync(video_id: str, langs: list[str]) -> Transcript:
    from youtube_transcript_api import YouTubeTranscriptApi
    from requests import Session

    class BoundedSession(Session):
        def request(self, method, url, **kwargs):
            kwargs["timeout"] = (5, 10)  # connect/read; worker also caps total time
            return super().request(method, url, **kwargs)

    try:
        with BoundedSession() as session:
            tracks = [{"language": t.language_code, "generated": t.is_generated, "value": t}
                      for t in YouTubeTranscriptApi(http_client=session).list(video_id)]
            selected = select_track(tracks, langs)
            if selected is None:
                raise TranscriptError("no_captions", "no requested language track")
            chosen = selected["value"]
            fetched = chosen.fetch()
    except TranscriptError:
        raise
    except Exception as e:
        raise _classify_yta_error(e) from e
    segments = [Segment(text=s.text, start=s.start, duration=s.duration) for s in fetched]
    if not segments:
        raise TranscriptError("no_captions", "caption track is empty")
    kind = "auto-generated" if chosen.is_generated else "manual"
    return Transcript(segments, f"YouTube captions ({kind}, {chosen.language_code})", "captions",
                      language=chosen.language_code, track=f"youtube-transcript-api:{chosen.language_code}:{kind}",
                      generated=chosen.is_generated)


async def _try_ytdlp_subs(video_id: str, langs: list[str]) -> Transcript:
    """Select the same language/type policy as the primary, then fetch one track."""
    url = f"https://www.youtube.com/watch?v={video_id}"
    code, out, err = await _run(["yt-dlp", "--dump-json", "--skip-download", url], timeout=20)
    if code:
        raise classify_ytdlp_error(err)
    info = json.loads(out)
    tracks = [{"language": lang, "generated": generated}
              for generated, key in ((False, "subtitles"), (True, "automatic_captions"))
              for lang, formats in info.get(key, {}).items() if any(f.get("ext") == "vtt" for f in formats)]
    chosen = select_track(tracks, langs)
    if chosen is None:
        raise TranscriptError("no_captions", "no requested language VTT track")
    lang, generated = chosen["language"], chosen["generated"]
    with tempfile.TemporaryDirectory() as tmpdir:
        code, _, err = await _run(
            ["yt-dlp", "--write-auto-subs" if generated else "--write-subs",
             "--sub-langs", "^" + re.escape(lang) + "$", "--sub-format", "vtt", "--skip-download",
             "-o", os.path.join(tmpdir, "sub"), url], timeout=25)
        if code:
            raise classify_ytdlp_error(err)
        path = os.path.join(tmpdir, f"sub.{lang}.vtt")
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                segments = _parse_vtt(fh.read())
            if segments:
                kind = "auto-generated" if generated else "manual"
                return Transcript(segments, f"YouTube captions (yt-dlp, {kind}, {lang})", "captions",
                                  language=lang, track=f"yt-dlp:{lang}:{kind}:vtt", generated=generated)
    raise TranscriptError("no_captions", "selected subtitle track is empty")


# Bounded uploads: 180 s of mono 16 kHz PCM is under 8 MiB. Chunks run
# sequentially; billed requests are non-retriable, including timeouts/429s.
AUDIO_CHUNK_SECONDS = 180
AUDIO_FORMAT = "bestaudio[acodec=opus]/bestaudio"
DEEPGRAM_CHUNK_TIMEOUT = 120
MAX_AUDIO_BYTES = 8 * 1024 * 1024
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
DEEPGRAM_URL = "https://api.deepgram.com/v1/listen"
AUDIO_PROVIDER = "deepgram"
AUDIO_PROVIDER_LABEL = "Deepgram"


def audio_budget(duration: int) -> float:
    return 900 + 600 + math.ceil(max(1, duration) / AUDIO_CHUNK_SECONDS) * DEEPGRAM_CHUNK_TIMEOUT


@dataclass
class AudioChunk:
    segments: list[Segment]
    request_id: str


def deepgram_chunk(result: dict) -> AudioChunk:
    """Parse untrusted provider data once, before it enters the audio pipeline."""
    try:
        request_id = result["metadata"]["request_id"]
        utterances = result["results"]["utterances"]
        if not isinstance(request_id, str) or not request_id or len(request_id) > 128:
            raise ValueError()
        if not isinstance(utterances, list):
            raise ValueError()
        segments = []
        for utterance in utterances:
            text, start, end = (utterance[k] for k in ("transcript", "start", "end"))
            if (not isinstance(text, str) or type(start) not in (int, float)
                    or type(end) not in (int, float) or not math.isfinite(start)
                    or not math.isfinite(end) or start < 0 or end < start):
                raise ValueError()
            if text.strip():
                segments.append(Segment(text.strip(), float(start), float(end - start)))
        return AudioChunk(segments, request_id)
    except (KeyError, TypeError, ValueError, OverflowError):
        raise TranscriptError("deepgram_failed", "invalid provider response") from None


async def _post_deepgram_chunk(client, api_key: str, model: str, path: str) -> AudioChunk:
    """One billed attempt. Async HTTP cancellation closes the upload/response."""
    import httpx
    try:
        with open(path, "rb") as audio:
            content = audio.read(MAX_AUDIO_BYTES + 1)
        if len(content) > MAX_AUDIO_BYTES:
            raise TranscriptError("deepgram_failed", "audio chunk exceeds upload limit")
        async with asyncio.timeout(DEEPGRAM_CHUNK_TIMEOUT):
            async with client.stream(
                "POST", DEEPGRAM_URL, content=content,
                headers={"Authorization": f"Token {api_key}", "Content-Type": "audio/wav"},
                params={"model": model, "language": "en", "smart_format": "true", "utterances": "true"},
            ) as response:
                if response.status_code != 200:
                    # Never expose response bodies, headers, or exception text.
                    raise TranscriptError("deepgram_failed", f"Deepgram HTTP {response.status_code}")
                body = bytearray()
                async for block in response.aiter_bytes():
                    body.extend(block)
                    if len(body) > MAX_RESPONSE_BYTES:
                        raise TranscriptError("deepgram_failed", "provider response exceeds limit")
        return deepgram_chunk(json.loads(body))
    except (httpx.HTTPError, TimeoutError):
        raise TranscriptError("deepgram_failed", "request failed or timed out; not retried") from None
    except (json.JSONDecodeError, UnicodeError):
        raise TranscriptError("deepgram_failed", "invalid provider response") from None


async def transcribe_audio(
    video_id: str,
    api_key: str,
    model_label: str,
    on_stage: Callable[[str], None] = lambda s: None,
    *, client, max_seconds: int,
) -> Transcript:
    url = f"https://www.youtube.com/watch?v={video_id}"
    with tempfile.TemporaryDirectory() as tmpdir:
        on_stage("downloading audio")
        # Best audio, never worst: on 2026-10-06 the 52 kbps track (format 249)
        # turned a clearly spoken video into fluent nonsense on both GPU and
        # CPU, while the 125 kbps track of the same minute matched the
        # captions nearly word for word. ~15 MB per 15 min is cheap.
        code, _, stderr = await _run(
            ["yt-dlp", "-f", AUDIO_FORMAT, "--no-playlist",
             "-o", os.path.join(tmpdir, "audio.%(ext)s"), url],
            timeout=900,
        )
        audio = [f for f in os.listdir(tmpdir) if f.startswith("audio.")]
        if code != 0 or not audio:
            err = classify_ytdlp_error(stderr)
            if err.reason == "rate_limited":
                _note_rate_limit()
            raise TranscriptError(err.reason if err.reason in ("rate_limited", "unavailable") else "deepgram_failed",
                                  f"audio download: {err.detail}")
        audio_path = os.path.join(tmpdir, audio[0])

        on_stage("splitting audio")
        code, _, stderr = await _run(
            ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", audio_path, "-ac", "1", "-ar", "16000",
             "-c:a", "pcm_s16le", "-f", "segment", "-segment_time", str(AUDIO_CHUNK_SECONDS),
             os.path.join(tmpdir, "chunk%04d.wav")],
            timeout=600,
        )
        os.remove(audio_path)
        chunks = sorted(f for f in os.listdir(tmpdir) if f.startswith("chunk"))
        if code != 0 or not chunks:
            raise TranscriptError("deepgram_failed", f"ffmpeg: {stderr.strip()[-200:]}")

        # Check actual decoded audio as well as metadata before any billed call.
        durations = []
        for name in chunks:
            with wave.open(os.path.join(tmpdir, name)) as audio:
                durations.append(audio.getnframes() / audio.getframerate())
        if sum(durations) > max_seconds:
            raise TranscriptError("too_long", "decoded audio exceeds the configured duration limit")

        segments: list[Segment] = []
        request_ids: list[str] = []
        offset = 0.0
        for i, name in enumerate(chunks, 1):
            on_stage(f"transcribing with Deepgram {i}/{len(chunks)}")
            path = os.path.join(tmpdir, name)
            try:
                chunk = await _post_deepgram_chunk(client, api_key, model_label, path)
            except TranscriptError as e:
                raise TranscriptError(e.reason, f"chunk {i}/{len(chunks)}: {e.detail}") from None
            request_ids.append(chunk.request_id)
            logger.info("Deepgram request completed: %s", chunk.request_id)
            segments.extend(Segment(s.text, offset + s.start, s.duration) for s in chunk.segments)
            # Offset by the chunk's real length; the segment muxer cuts on
            # packet boundaries, so i * AUDIO_CHUNK_SECONDS drifts.
            with wave.open(path) as w:
                offset += w.getnframes() / w.getframerate()
            os.remove(path)

    if not segments:
        raise TranscriptError("deepgram_failed", "no speech recognised")
    return Transcript(segments, f"{AUDIO_PROVIDER_LABEL} speech-to-text ({model_label}) — machine transcription of the audio",
                      AUDIO_PROVIDER, request_ids, language="en", model=model_label)


def _parse_vtt(vtt_text: str) -> list[Segment]:
    """Parse cues without deduplicating them. Invalid timing fails the source."""
    def timestamp(value):
        if not re.fullmatch(r"(?:[0-9]{2,}:)?[0-5][0-9]:[0-5][0-9]\.[0-9]{3}", value):
            raise TranscriptError("error", "invalid VTT timestamp")
        fields = value.split(":")
        return sum(float(v) * factor for v, factor in zip(reversed(fields), (1, 60, 3600)))

    segments = []
    for block in re.split(r"\n[ \t]*\n", vtt_text.lstrip("\ufeff").replace("\r\n", "\n").strip()):
        lines = block.splitlines()
        if not lines or lines[0].startswith(("WEBVTT", "NOTE", "STYLE", "REGION")):
            continue
        idx = 0 if "-->" in lines[0] else 1
        if idx >= len(lines) or "-->" not in lines[idx]:
            raise TranscriptError("error", "invalid VTT cue")
        start_text, end_text = lines[idx].split("-->", 1)
        end_fields = end_text.split()
        if not end_fields:
            raise TranscriptError("error", "invalid VTT timing")
        start, end = timestamp(start_text.strip()), timestamp(end_fields[0])
        if end <= start:
            raise TranscriptError("error", "invalid VTT interval")
        text = html.unescape(re.sub(r"<[^>]*>", "", " ".join(lines[idx + 1:]))).strip()
        if text:
            segments.append(Segment(text, start, end - start))
    return segments


# Compare complete words only; apostrophes within words remain significant.
_WORD = re.compile(r"\w+(?:['’]\w+)*", re.UNICODE)
_FILLER_START = re.compile(r"^(?:um|uh)[, ]+", re.IGNORECASE)


def reconcile_captions(segments: list[Segment], *, generated: bool) -> tuple[list[Segment], list[dict]]:
    """Only overlapping generated cues qualify. At least two matching boundary
    words are required. Punctuation/case are ignored for comparison only.
    Keep the first spelling/punctuation, append the incoming original suffix.
    Revised words, interior containment and single-word overlaps stay verbatim.
    Each deletion records original segment indexes and the exact removed text.
    """
    result, changes = [], []
    for i, seg in enumerate(segments):
        text = seg.text.strip()
        if generated and i:
            prev = segments[i - 1]
            if max(prev.start, seg.start) < min(prev.start + prev.duration, seg.start + seg.duration):
                left, right = list(_WORD.finditer(prev.text)), list(_WORD.finditer(text))
                normalize = lambda m: m.group().casefold().replace("’", "'")
                for n in range(min(len(left), len(right)), 1, -1):
                    if [normalize(m) for m in left[-n:]] == [normalize(m) for m in right[:n]]:
                        cut = right[n].start() if n < len(right) else len(text)
                        changes.append({"segment": i, "previous_segment": i - 1, "removed_words": n,
                                        "removed_text": text[:cut]})
                        text = text[cut:]
                        break
        if text:
            result.append(Segment(text, seg.start, seg.duration))
    return result, changes


def clean_transcript(segments: list[Segment], gap_threshold: float = 5.0, *,
                     remove_fillers: bool = False) -> str:
    """Layout only by default. Reconcile known rolling captions before calling.
    Optional filler removal covers only um/uh at a known paragraph boundary.
    """
    cleaned = [Segment(s.text.strip(), s.start, s.duration) for s in segments if s.text.strip()]
    paragraphs = _group_by_gaps(cleaned, gap_threshold)
    total_text = " ".join(s.text for s in cleaned)
    if len(paragraphs) <= 2 and len(total_text) > 2000:
        paragraphs = _split_by_sentences(total_text, every=5)
    if remove_fillers:
        paragraphs = [_FILLER_START.sub("", p) for p in paragraphs]
    return "\n\n".join(paragraphs)


def raw_transcript(segments: list[Segment]) -> str:
    """Raw mode: just join all text, strip timestamps."""
    return " ".join(s.text.strip() for s in segments if s.text.strip())


def _group_by_gaps(segments: list[Segment], gap_threshold: float) -> list[str]:
    """Group segments into paragraphs based on timestamp gaps."""
    if not segments:
        return []

    paragraphs = []
    current: list[str] = [segments[0].text]

    for i in range(1, len(segments)):
        prev = segments[i - 1]
        curr = segments[i]
        gap = curr.start - (prev.start + prev.duration)

        if gap >= gap_threshold:
            paragraphs.append(" ".join(current))
            current = [curr.text]
        else:
            current.append(curr.text)

    if current:
        paragraphs.append(" ".join(current))

    return paragraphs


def _split_by_sentences(text: str, every: int = 5) -> list[str]:
    """Insert paragraph breaks; never discard any non-whitespace character."""
    if every < 1:
        raise ValueError("every must be positive")
    sentences = re.findall(r"[^.?!]*[.?!]+|[^.?!]+$", text)
    return [" ".join(sentences[i:i + every]).strip()
            for i in range(0, len(sentences), every)]


# ---------------------------------------------------------------------------
# Markdown formatting
# ---------------------------------------------------------------------------
def format_markdown(meta: VideoMeta, transcript_text: str, source: str) -> str:
    """Format transcript as markdown with metadata header."""
    return f"""# {meta.title}

**Channel:** {meta.channel}
**Duration:** {format_duration(meta.duration)}
**URL:** {meta.url}
**Source:** {source}

---

{transcript_text}
"""


def saved_video_id(header: str) -> Optional[str]:
    """Video ID of a saved transcript, read from its header — the inverse of
    format_markdown. Only header lines (before the first `---`) that carry a
    URL label count, so a link quoted in the transcript body never matches.
    Also reads the older `- **URL**: ...` header used by earlier versions."""
    for line in header.splitlines():
        if line.strip() == "---":
            break
        if "URL" in line:
            video_id = extract_video_id(line)
            if video_id:
                return video_id
    return None


if __name__ == "__main__":
    try:
        result = asdict(_fetch_yta_sync(sys.argv[1], json.loads(sys.argv[2])))
    except TranscriptError as exc:
        result = {"error": exc.reason, "detail": exc.detail}
    print(json.dumps(result))
