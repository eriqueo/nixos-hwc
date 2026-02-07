"""FFmpeg metadata embedding"""

import asyncio
from pathlib import Path
from typing import Dict, Optional
import structlog

logger = structlog.get_logger()


async def embed_metadata(
    video_path: Path,
    metadata: Dict,
    thumbnail_path: Optional[Path] = None,
    container: str = "webm",
) -> None:
    """
    Embed metadata and cover art using ffmpeg.

    Args:
        video_path: Path to video file (will be modified in place)
        metadata: Dict with title, artist (channel), date, etc.
        thumbnail_path: Path to thumbnail image
        container: Container format (webm, mp4, mkv)

    Container-specific behavior:
    - mkv/webm: Attach cover art as separate stream
    - mp4: Use attached_pic stream (or skip cover art)
    """
    logger.info(
        "ffmpeg.embedding_metadata",
        video_path=str(video_path),
        has_thumbnail=thumbnail_path is not None,
    )

    # Build ffmpeg command
    cmd = ["ffmpeg", "-i", str(video_path)]

    # Add thumbnail if provided and container supports it
    if thumbnail_path and thumbnail_path.exists():
        if container in ("mkv", "webm"):
            # Attach cover art as separate stream
            cmd.extend(["-attach", str(thumbnail_path)])
            cmd.extend(["-metadata:s:t:0", "mimetype=image/jpeg"])
        # Note: For mp4, cover art is more complex and yt-dlp handles it better
        # We skip it here to avoid compatibility issues

    # Add metadata tags
    if metadata.get("title"):
        cmd.extend(["-metadata", f"title={metadata['title']}"])

    if metadata.get("channel_name"):
        cmd.extend(["-metadata", f"artist={metadata['channel_name']}"])
        cmd.extend(["-metadata", f"album_artist={metadata['channel_name']}"])

    if metadata.get("published_at"):
        cmd.extend(["-metadata", f"date={metadata['published_at']}"])

    if metadata.get("video_id"):
        cmd.extend(["-metadata", f"comment=YouTube ID: {metadata['video_id']}"])

    # Copy streams (no re-encoding)
    cmd.extend(["-codec", "copy"])

    # Output to temporary file
    tmp_path = video_path.with_suffix(video_path.suffix + ".tmp")
    cmd.append(str(tmp_path))

    # Overwrite without asking
    cmd.insert(1, "-y")

    try:
        # Run ffmpeg
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        stdout, stderr = await proc.communicate()

        if proc.returncode != 0:
            raise Exception(
                f"ffmpeg failed with code {proc.returncode}: {stderr.decode()}"
            )

        # Replace original file with metadata-embedded version
        tmp_path.replace(video_path)

        logger.info("ffmpeg.metadata_embedded", video_path=str(video_path))

    except Exception as e:
        logger.error(
            "ffmpeg.embedding_failed",
            video_path=str(video_path),
            error=str(e),
        )
        # Clean up tmp file if it exists
        if tmp_path.exists():
            tmp_path.unlink()
        raise
