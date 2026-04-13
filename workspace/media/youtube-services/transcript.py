"""
YouTube transcript extraction and cleaning.

Uses youtube-transcript-api for captions, yt-dlp for metadata only.
No NLP libraries, no LLM, no spaCy.
"""

import asyncio
import re
from dataclasses import dataclass
from typing import Optional


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
    proc = await asyncio.create_subprocess_exec(
        "yt-dlp", "--dump-json", "--no-download", "--no-warnings", "-q", url,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
    if proc.returncode != 0:
        raise RuntimeError(f"yt-dlp failed: {stderr.decode().strip()}")

    import json
    info = json.loads(stdout)
    return VideoMeta(
        video_id=video_id,
        title=info.get("title", "Unknown"),
        channel=info.get("channel", info.get("uploader", "Unknown")),
        duration=int(info.get("duration", 0)),
        upload_date=info.get("upload_date", ""),
        url=url,
    )


def format_duration(seconds: int) -> str:
    h, r = divmod(seconds, 3600)
    m, s = divmod(r, 60)
    if h:
        return f"{h}h {m:02d}m {s:02d}s"
    return f"{m}m {s:02d}s"


# ---------------------------------------------------------------------------
# Transcript fetching (youtube-transcript-api primary, yt-dlp VTT fallback)
# ---------------------------------------------------------------------------
@dataclass
class Segment:
    text: str
    start: float
    duration: float


async def fetch_transcript(video_id: str, langs: list[str] | None = None) -> list[Segment]:
    """Fetch transcript segments. Tries youtube-transcript-api first, yt-dlp VTT fallback."""
    if langs is None:
        langs = ["en", "en-US", "en-GB"]

    segments = await _try_youtube_transcript_api(video_id, langs)
    if segments:
        return segments

    segments = await _try_ytdlp_vtt(video_id, langs)
    if segments:
        return segments

    raise RuntimeError("No transcript available for this video")


async def _try_youtube_transcript_api(video_id: str, langs: list[str]) -> list[Segment]:
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        # Run in thread since this library is sync
        loop = asyncio.get_event_loop()
        raw = await loop.run_in_executor(None, _fetch_yta_sync, video_id, langs)
        return [Segment(text=s["text"], start=s["start"], duration=s["duration"]) for s in raw]
    except Exception:
        return []


def _fetch_yta_sync(video_id: str, langs: list[str]) -> list[dict]:
    from youtube_transcript_api import YouTubeTranscriptApi
    transcript_list = YouTubeTranscriptApi.list_transcripts(video_id)

    # Try manual captions first
    for lang in langs:
        try:
            t = transcript_list.find_manually_created_transcript([lang])
            return t.fetch()
        except Exception:
            continue

    # Fall back to auto-generated
    for lang in langs:
        try:
            t = transcript_list.find_generated_transcript([lang])
            return t.fetch()
        except Exception:
            continue

    # Last resort: any available transcript
    for t in transcript_list:
        try:
            return t.fetch()
        except Exception:
            continue

    return []


async def _try_ytdlp_vtt(video_id: str, langs: list[str]) -> list[Segment]:
    """Fallback: download VTT subtitles via yt-dlp and parse them."""
    import tempfile, os
    url = f"https://www.youtube.com/watch?v={video_id}"
    lang_str = ",".join(langs)

    with tempfile.TemporaryDirectory() as tmpdir:
        out_template = os.path.join(tmpdir, "sub")
        proc = await asyncio.create_subprocess_exec(
            "yt-dlp", "--write-auto-sub", "--sub-lang", lang_str,
            "--sub-format", "vtt", "--skip-download",
            "-o", out_template, url,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await asyncio.wait_for(proc.communicate(), timeout=20)

        # Find the .vtt file
        for f in os.listdir(tmpdir):
            if f.endswith(".vtt"):
                vtt_path = os.path.join(tmpdir, f)
                text = open(vtt_path, encoding="utf-8").read()
                return _parse_vtt(text)

    return []


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
def format_markdown(meta: VideoMeta, transcript_text: str) -> str:
    """Format transcript as markdown with metadata header."""
    return f"""# {meta.title}

**Channel:** {meta.channel}
**Duration:** {format_duration(meta.duration)}
**URL:** {meta.url}

---

{transcript_text}
"""
