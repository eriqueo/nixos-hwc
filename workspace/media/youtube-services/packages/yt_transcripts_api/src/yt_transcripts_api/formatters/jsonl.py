"""JSONL transcript formatter"""

import json
from typing import Dict, Any


def format_transcript(video_meta: Dict, transcript: Dict, result: Dict) -> str:
    """
    Format transcript as JSONL (one JSON object per line).

    Args:
        video_meta: Video metadata from database
        transcript: Transcript record from database
        result: Extraction result with segments

    Returns:
        JSONL-formatted transcript
    """
    lines = []

    # Metadata line
    metadata = {
        "type": "metadata",
        "video_id": video_meta["video_id"],
        "title": video_meta["title"],
        "channel_name": video_meta["channel_name"],
        "channel_id": video_meta.get("channel_id"),
        "published_at": (
            video_meta["published_at"].isoformat()
            if video_meta.get("published_at")
            else None
        ),
        "duration_seconds": video_meta.get("duration_seconds"),
        "transcript_language": result.get("language"),
        "transcript_source": result["strategy"],
    }
    lines.append(json.dumps(metadata))

    # Full text line
    if result.get("text"):
        text_obj = {"type": "text", "content": result["text"]}
        lines.append(json.dumps(text_obj))

    # Segment lines
    if result.get("segments"):
        for segment in result["segments"]:
            segment_obj = {
                "type": "segment",
                "start": segment.get("start"),
                "duration": segment.get("duration"),
                "text": segment.get("text"),
            }
            lines.append(json.dumps(segment_obj))

    return "\n".join(lines) + "\n"
