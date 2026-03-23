"""Video metadata extraction"""

import asyncpg
from yt_core.youtube import YouTubeClient
from yt_core.ratelimit import YouTubeQuotaTracker
from typing import Optional
import structlog

logger = structlog.get_logger()


async def ensure_video_metadata(
    conn: asyncpg.Connection,
    video_id: str,
    youtube_client: Optional[YouTubeClient],
    quota_tracker: Optional[YouTubeQuotaTracker],
):
    """
    Ensure video metadata exists in database.
    Fetches from YouTube API if not present.
    """
    # Check if metadata already exists
    existing = await conn.fetchrow(
        "SELECT * FROM yt_transcripts.videos WHERE video_id = $1", video_id
    )

    if existing:
        return existing

    # Fetch from YouTube API
    if not youtube_client or not quota_tracker:
        logger.warning(
            "video.metadata_unavailable",
            video_id=video_id,
            reason="no_youtube_client",
        )
        # Insert minimal record
        await conn.execute(
            """
            INSERT INTO yt_transcripts.videos (video_id)
            VALUES ($1)
            ON CONFLICT (video_id) DO NOTHING
            """,
            video_id,
        )
        return None

    # Consume quota
    await quota_tracker.consume(1)  # videos.list costs 1 unit

    metadata = await youtube_client.get_video_metadata(video_id)

    if metadata:
        await conn.execute(
            """
            INSERT INTO yt_transcripts.videos (
                video_id, title, channel_id, channel_name,
                duration_seconds, published_at
            )
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (video_id) DO UPDATE SET
                title = EXCLUDED.title,
                channel_id = EXCLUDED.channel_id,
                channel_name = EXCLUDED.channel_name,
                duration_seconds = EXCLUDED.duration_seconds,
                published_at = EXCLUDED.published_at,
                last_fetched_at = NOW()
            """,
            metadata["video_id"],
            metadata["title"],
            metadata["channel_id"],
            metadata["channel_name"],
            metadata["duration_seconds"],
            metadata["published_at"],
        )

        logger.info("video.metadata_stored", video_id=video_id)

    return metadata
