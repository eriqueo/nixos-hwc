"""yt-dlp wrapper with multi-extractor fallback"""

import asyncio
import subprocess
from pathlib import Path
from typing import Optional, Dict
import structlog
import json

logger = structlog.get_logger()

# Extractor fallback chain (most reliable first)
EXTRACTOR_SEQUENCE = [
    "android",  # Most reliable
    "tv_embedded",  # Fallback 1
    "web",  # Fallback 2
    "default",  # Last resort (no player_client override)
]


async def download_video(
    video_id: str,
    output_path: Path,
    container_policy: str = "webm",
    quality: str = "best",
    extractor: Optional[str] = None,
) -> Dict:
    """
    Download video using yt-dlp.

    Args:
        video_id: YouTube video ID
        output_path: Output file path (including extension)
        container_policy: webm, mp4, or mkv
        quality: Quality selector (default: "best")
        extractor: Specific extractor to use (None = try all)

    Returns:
        Dict with download info

    Raises:
        Exception if download fails
    """
    extractors_to_try = [extractor] if extractor else EXTRACTOR_SEQUENCE

    last_error = None
    for ext in extractors_to_try:
        try:
            logger.info(
                "ytdlp.attempting_download",
                video_id=video_id,
                extractor=ext,
                output=str(output_path),
            )

            # Build yt-dlp command
            cmd = _build_ytdlp_command(
                video_id, output_path, container_policy, quality, ext
            )

            # Run yt-dlp
            result = await _run_ytdlp(cmd)

            # Success!
            logger.info(
                "ytdlp.download_success",
                video_id=video_id,
                extractor=ext,
                file_size_bytes=output_path.stat().st_size,
            )

            return {
                "extractor": ext,
                "file_path": str(output_path),
                "file_size": output_path.stat().st_size,
                "stdout": result["stdout"],
                "stderr": result["stderr"],
            }

        except Exception as e:
            last_error = e
            logger.warning(
                "ytdlp.extractor_failed",
                video_id=video_id,
                extractor=ext,
                error=str(e),
            )
            continue

    # All extractors failed
    raise Exception(f"All extractors failed for {video_id}: {last_error}")


def _build_ytdlp_command(
    video_id: str,
    output_path: Path,
    container_policy: str,
    quality: str,
    extractor: str,
) -> list:
    """Build yt-dlp command arguments"""
    cmd = [
        "yt-dlp",
        f"https://www.youtube.com/watch?v={video_id}",
        "-o",
        str(output_path),
        "-f",
        quality,
        "--merge-output-format",
        container_policy,
        # Don't embed metadata yet (we'll do it with ffmpeg)
        "--no-embed-metadata",
        "--no-embed-thumbnail",
        # Download thumbnail separately for metadata embedding
        "--write-thumbnail",
        # JSON output for metadata
        "--write-info-json",
        "--no-overwrites",
        "--no-continue",  # Start fresh
    ]

    # Extractor-specific args
    if extractor != "default":
        cmd.extend(["--extractor-args", f"youtube:player_client={extractor}"])

    return cmd


async def _run_ytdlp(cmd: list) -> Dict:
    """Run yt-dlp command asynchronously"""
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    stdout, stderr = await proc.communicate()

    if proc.returncode != 0:
        raise Exception(
            f"yt-dlp failed with code {proc.returncode}: {stderr.decode()}"
        )

    return {
        "returncode": proc.returncode,
        "stdout": stdout.decode(),
        "stderr": stderr.decode(),
    }


async def get_video_info(video_id: str) -> Optional[Dict]:
    """
    Get video metadata using yt-dlp without downloading.

    Returns dict with title, channel, duration, etc.
    """
    cmd = [
        "yt-dlp",
        f"https://www.youtube.com/watch?v={video_id}",
        "--dump-json",
        "--no-download",
    ]

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        stdout, stderr = await proc.communicate()

        if proc.returncode == 0:
            info = json.loads(stdout.decode())
            return {
                "title": info.get("title"),
                "channel_name": info.get("uploader") or info.get("channel"),
                "channel_id": info.get("channel_id"),
                "duration_seconds": info.get("duration"),
                "published_at": info.get("upload_date"),  # YYYYMMDD format
            }
    except Exception as e:
        logger.error("ytdlp.get_info_failed", video_id=video_id, error=str(e))

    return None
