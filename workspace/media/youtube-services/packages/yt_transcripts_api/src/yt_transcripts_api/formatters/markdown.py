"""Markdown transcript formatter"""

from typing import Dict, Any


def format_transcript(video_meta: Dict, transcript: Dict, result: Dict) -> str:
    """
    Format transcript as Markdown.

    Args:
        video_meta: Video metadata from database
        transcript: Transcript record from database
        result: Extraction result with segments

    Returns:
        Markdown-formatted transcript
    """
    lines = []

    # Header with metadata
    lines.append(f"# {video_meta['title']}")
    lines.append("")
    lines.append(f"**Video ID**: {video_meta['video_id']}")
    lines.append(f"**Channel**: {video_meta['channel_name']}")

    if video_meta.get("published_at"):
        lines.append(f"**Published**: {video_meta['published_at']}")

    if video_meta.get("duration_seconds"):
        duration = video_meta["duration_seconds"]
        minutes = duration // 60
        seconds = duration % 60
        lines.append(f"**Duration**: {minutes}:{seconds:02d}")

    lines.append(f"**Transcript Language**: {result['language']}")
    lines.append(f"**Transcript Source**: {result['strategy']}")
    lines.append("")
    lines.append("---")
    lines.append("")

    # Transcript text
    if result.get("text"):
        lines.append("## Transcript")
        lines.append("")
        lines.append(result["text"])
        lines.append("")

    # Timestamped segments (optional)
    if result.get("segments"):
        lines.append("## Segments")
        lines.append("")
        for segment in result["segments"]:
            timestamp = _format_timestamp(segment.get("start", 0))
            text = segment.get("text", "")
            lines.append(f"**[{timestamp}]** {text}")
            lines.append("")

    return "\n".join(lines)


def _format_timestamp(seconds: float) -> str:
    """Format seconds as MM:SS or HH:MM:SS"""
    total_seconds = int(seconds)
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    secs = total_seconds % 60

    if hours > 0:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    else:
        return f"{minutes}:{secs:02d}"
