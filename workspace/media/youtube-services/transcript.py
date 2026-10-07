"""
YouTube transcript extraction and cleaning.

Captions come from youtube-transcript-api, with yt-dlp subtitles as a fallback;
when neither yields captions, the audio is transcribed by the local
whisper-server. yt-dlp also supplies metadata. No NLP libraries, no LLM.
"""

import asyncio
import json
import logging
import os
import re
import tempfile
import time
import wave
from dataclasses import dataclass
from typing import Callable, Optional

logger = logging.getLogger("transcripts")


# ---------------------------------------------------------------------------
# Failure vocabulary — every per-video failure carries exactly one reason
# ---------------------------------------------------------------------------
REASON_TEXT = {
    "rate_limited": "YouTube is rate-limiting or blocking this server",
    "no_captions": "Video has no captions",
    "unavailable": "Video is unavailable (private, removed, age- or member-restricted)",
    "invalid_url": "Invalid YouTube URL",
    "whisper_failed": "Audio transcription failed",
    "too_long": "Video is too long for audio transcription",
    "timeout": "Timed out",
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
# then Whisper over the audio. Each source returns segments or raises a
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
    kind: str    # "captions" | "whisper"


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
            return await asyncio.to_thread(_fetch_yta_sync, video_id, langs)
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


def _fetch_yta_sync(video_id: str, langs: list[str]) -> Transcript:
    """youtube-transcript-api >= 1.0: instance API, snippets are objects."""
    from youtube_transcript_api import YouTubeTranscriptApi, NoTranscriptFound
    try:
        transcripts = YouTubeTranscriptApi().list(video_id)
        chosen = None
        for find in (transcripts.find_manually_created_transcript, transcripts.find_generated_transcript):
            try:
                chosen = find(langs)
                break
            except NoTranscriptFound:
                continue
        if chosen is None:
            chosen = next(iter(transcripts), None)  # any language beats none
        if chosen is None:
            raise TranscriptError("no_captions", "no caption tracks")
        fetched = chosen.fetch()
    except TranscriptError:
        raise
    except Exception as e:
        raise _classify_yta_error(e) from e

    segments = [Segment(text=s.text, start=s.start, duration=s.duration) for s in fetched]
    if not segments:
        raise TranscriptError("no_captions", "caption track is empty")
    kind = "auto-generated" if chosen.is_generated else "manual"
    return Transcript(segments, f"YouTube captions ({kind}, {chosen.language_code})", "captions")


async def _try_ytdlp_subs(video_id: str, langs: list[str]) -> Transcript:
    """Fallback: download manual or auto VTT subtitles via yt-dlp and parse them."""
    url = f"https://www.youtube.com/watch?v={video_id}"
    with tempfile.TemporaryDirectory() as tmpdir:
        code, _, stderr = await _run(
            ["yt-dlp", "--write-subs", "--write-auto-subs", "--sub-langs", ",".join(langs),
             "--sub-format", "vtt", "--skip-download", "-o", os.path.join(tmpdir, "sub"), url],
            timeout=30,
        )
        for f in sorted(os.listdir(tmpdir)):
            if f.endswith(".vtt"):
                with open(os.path.join(tmpdir, f), encoding="utf-8") as fh:
                    segments = _parse_vtt(fh.read())
                if segments:
                    return Transcript(segments, "YouTube captions (yt-dlp)", "captions")
    if code != 0 or "ERROR" in stderr:
        raise classify_ytdlp_error(stderr)
    raise TranscriptError("no_captions", "yt-dlp found no subtitles")


# Whisper (whisper.cpp server, OpenAI-compatible). Audio is cut into chunks so
# the shared server — also used for phone dictation and the inbox processor —
# is held for one chunk (~20 s at the measured 10x real time on the P1000),
# never for a whole 90-minute video.
WHISPER_CHUNK_SECONDS = 180
WHISPER_AUDIO_FORMAT = "bestaudio[acodec=opus]/bestaudio"
# Whisper marks non-speech with bracketed tags ("[BLANK_AUDIO]", "[Music]").
_NON_SPEECH = re.compile(r"^\s*[\[\(][^\]\)]*[\]\)]\s*$")


async def transcribe_audio(
    video_id: str,
    whisper_url: str,
    model_label: str,
    on_stage: Callable[[str], None] = lambda s: None,
) -> Transcript:
    url = f"https://www.youtube.com/watch?v={video_id}"
    with tempfile.TemporaryDirectory() as tmpdir:
        on_stage("downloading audio")
        # Best audio, never worst: on 2026-10-06 the 52 kbps track (format 249)
        # turned a clearly spoken video into fluent nonsense on both GPU and
        # CPU, while the 125 kbps track of the same minute matched the
        # captions nearly word for word. ~15 MB per 15 min is cheap.
        code, _, stderr = await _run(
            ["yt-dlp", "-f", WHISPER_AUDIO_FORMAT, "--no-playlist",
             "-o", os.path.join(tmpdir, "audio.%(ext)s"), url],
            timeout=900,
        )
        audio = [f for f in os.listdir(tmpdir) if f.startswith("audio.")]
        if code != 0 or not audio:
            err = classify_ytdlp_error(stderr)
            if err.reason == "rate_limited":
                _note_rate_limit()
            raise TranscriptError(err.reason if err.reason in ("rate_limited", "unavailable") else "whisper_failed",
                                  f"audio download: {err.detail}")
        audio_path = os.path.join(tmpdir, audio[0])

        on_stage("splitting audio")
        code, _, stderr = await _run(
            ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", audio_path, "-ac", "1", "-ar", "16000",
             "-c:a", "pcm_s16le", "-f", "segment", "-segment_time", str(WHISPER_CHUNK_SECONDS),
             os.path.join(tmpdir, "chunk%04d.wav")],
            timeout=600,
        )
        os.remove(audio_path)
        chunks = sorted(f for f in os.listdir(tmpdir) if f.startswith("chunk"))
        if code != 0 or not chunks:
            raise TranscriptError("whisper_failed", f"ffmpeg: {stderr.strip()[-200:]}")

        segments: list[Segment] = []
        offset = 0.0
        for i, name in enumerate(chunks, 1):
            on_stage(f"transcribing audio {i}/{len(chunks)}")
            path = os.path.join(tmpdir, name)
            try:
                result = await asyncio.to_thread(_post_whisper_chunk, whisper_url, path)
            except Exception as e:
                raise TranscriptError("whisper_failed", f"chunk {i}/{len(chunks)}: {type(e).__name__}: {e}"[:300]) from e
            segments.extend(whisper_segments(result, offset))
            # Offset by the chunk's real length; the segment muxer cuts on
            # packet boundaries, so i * WHISPER_CHUNK_SECONDS drifts.
            with wave.open(path) as w:
                offset += w.getnframes() / w.getframerate()
            os.remove(path)

    if not segments:
        raise TranscriptError("whisper_failed", "no speech recognised")
    return Transcript(segments, f"Whisper speech-to-text ({model_label}) — machine transcription of the audio", "whisper")


def _post_whisper_chunk(whisper_url: str, path: str) -> dict:
    import requests
    with open(path, "rb") as fh:
        r = requests.post(
            whisper_url,
            files={"file": (os.path.basename(path), fh, "audio/wav")},
            data={"response_format": "verbose_json"},
            timeout=600,
        )
    r.raise_for_status()
    return r.json()


def whisper_segments(result: dict, offset: float) -> list[Segment]:
    """Turn one verbose_json response into segments on the video's timeline."""
    out = []
    for s in result.get("segments") or []:
        text = (s.get("text") or "").strip()
        if not text or _NON_SPEECH.match(text):
            continue
        start = float(s.get("start", 0.0))
        out.append(Segment(text=text, start=offset + start, duration=float(s.get("end", start)) - start))
    return out


def _parse_vtt(vtt_text: str) -> list[Segment]:
    """Parse VTT subtitle file into segments."""
    segments = []
    time_pattern = re.compile(r"(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})")
    tag_pattern = re.compile(r"<[^>]+>")

    lines = vtt_text.split("\n")
    i = 0
    while i < len(lines):
        m = time_pattern.match(lines[i])
        if m:
            start = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3)) + int(m.group(4)) / 1000
            end = int(m.group(5)) * 3600 + int(m.group(6)) * 60 + int(m.group(7)) + int(m.group(8)) / 1000
            i += 1
            text_lines = []
            while i < len(lines) and lines[i].strip():
                text_lines.append(lines[i].strip())
                i += 1
            text = " ".join(text_lines)
            text = tag_pattern.sub("", text).strip()
            if text:
                segments.append(Segment(text=text, start=start, duration=end - start))
        i += 1

    # Deduplicate VTT (often has overlapping repeated lines)
    deduped = []
    for seg in segments:
        if not deduped or seg.text != deduped[-1].text:
            deduped.append(seg)
    return deduped


# ---------------------------------------------------------------------------
# Cleaning
# ---------------------------------------------------------------------------
_FILLER_START = re.compile(
    r"^(?:um|uh|you know|i mean|like|so)(?:[,\s])\s*",
    re.IGNORECASE,
)


def _find_overlap(prev: str, curr: str) -> int:
    """Find how many characters at the start of curr overlap with the end of prev."""
    max_check = min(len(prev), len(curr))
    for size in range(max_check, 0, -1):
        if prev.endswith(curr[:size]):
            return size
    return 0


def clean_transcript(segments: list[Segment], gap_threshold: float = 5.0) -> str:
    """Clean mode: dedup, strip fillers, paragraph by gaps."""
    if not segments:
        return ""

    # Merge overlapping auto-caption segments.
    # YouTube auto-captions use a rolling window: each segment contains the
    # tail of the previous segment plus new words. We extract only the NEW
    # words from each segment to avoid duplication.
    merged_texts: list[str] = []
    merged_segments: list[Segment] = []
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        if merged_texts:
            prev = merged_texts[-1].lower()
            curr = text.lower()
            # If previous text is contained in current, keep only the new suffix
            if prev in curr:
                idx = curr.index(prev) + len(prev)
                new_part = text[idx:].strip()
                if new_part:
                    merged_texts.append(text)
                    merged_segments.append(Segment(text=new_part, start=seg.start, duration=seg.duration))
                continue
            # If current is contained in previous, skip entirely (subset)
            if curr in prev:
                continue
            # If they share a long common suffix/prefix overlap, extract new part
            overlap = _find_overlap(prev, curr)
            if overlap > len(curr) * 0.4:
                new_part = text[overlap:].strip()
                if new_part:
                    merged_texts.append(text)
                    merged_segments.append(Segment(text=new_part, start=seg.start, duration=seg.duration))
                continue
        merged_texts.append(text)
        merged_segments.append(Segment(text=text, start=seg.start, duration=seg.duration))

    if not merged_segments:
        return ""

    # Strip filler words at start of segments
    cleaned = []
    for seg in merged_segments:
        text = _FILLER_START.sub("", seg.text).strip()
        if text:
            cleaned.append(Segment(text=text, start=seg.start, duration=seg.duration))

    # Group into paragraphs by timestamp gaps
    paragraphs = _group_by_gaps(cleaned, gap_threshold)

    # If too few paragraphs for a long transcript, fall back to sentence-based breaks
    total_text = " ".join(s.text for s in cleaned)
    if len(paragraphs) <= 2 and len(total_text) > 2000:
        paragraphs = _split_by_sentences(total_text, every=5)

    # Join and capitalize first letter of each paragraph
    result = []
    for para in paragraphs:
        para = para.strip()
        if para and para[0].islower():
            para = para[0].upper() + para[1:]
        result.append(para)

    return "\n\n".join(result)


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


_SENTENCE_END = re.compile(r"[.?!]\s+|\s*[.?!]$")


def _split_by_sentences(text: str, every: int = 5) -> list[str]:
    """Split text into paragraphs every N sentences."""
    # Split on sentence boundaries
    parts = _SENTENCE_END.split(text)
    # Reconstruct sentences with their terminators
    sentences = []
    for m in re.finditer(r"[^.?!]+[.?!]", text):
        sentences.append(m.group().strip())

    if not sentences:
        return [text]

    paragraphs = []
    for i in range(0, len(sentences), every):
        chunk = " ".join(sentences[i:i + every])
        if chunk:
            paragraphs.append(chunk)

    return paragraphs if paragraphs else [text]


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
