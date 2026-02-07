"""Playlist expansion"""

from yt_core.database import DatabasePool
from yt_core.youtube import YouTubeClient
from yt_core.ratelimit import YouTubeQuotaTracker
from typing import List, Optional
from datetime import datetime, timedelta
import structlog

logger = structlog.get_logger()


async def expand_playlist(
    db_pool: DatabasePool,
    playlist_id: str,
    youtube_client: Optional[YouTubeClient],
    quota_tracker: Optional[YouTubeQuotaTracker],
    cache_expiry_seconds: int = 3600,
) -> List[str]:
    """
    Expand playlist to list of video IDs.

    Uses cache to avoid redundant API calls.
    """
    # Check cache
    async with db_pool.acquire() as conn:
        cached = await conn.fetchrow(
            """
            SELECT * FROM yt_transcripts.playlist_cache
            WHERE playlist_id = $1
            AND expires_at > NOW()
            """,
            playlist_id,
        )

        if cached:
            logger.info(
                "playlist.cache_hit",
                playlist_id=playlist_id,
                video_count=len(cached["video_ids"]),
            )
            return cached["video_ids"]

    # Fetch from YouTube API
    if not youtube_client or not quota_tracker:
        raise ValueError("YouTube client required for playlist expansion")

    # Consume quota (1 unit per 50 videos)
    await quota_tracker.consume(1)

    video_ids = await youtube_client.get_playlist_videos(playlist_id)

    # Cache result
    expires_at = datetime.now() + timedelta(seconds=cache_expiry_seconds)
    async with db_pool.acquire() as conn:
        await conn.execute(
            """
            INSERT INTO yt_transcripts.playlist_cache (
                playlist_id, video_ids, expires_at
            )
            VALUES ($1, $2, $3)
            ON CONFLICT (playlist_id) DO UPDATE SET
                video_ids = EXCLUDED.video_ids,
                fetched_at = NOW(),
                expires_at = EXCLUDED.expires_at
            """,
            playlist_id,
            video_ids,
            expires_at,
        )

    logger.info(
        "playlist.expanded", playlist_id=playlist_id, video_count=len(video_ids)
    )

    return video_ids
