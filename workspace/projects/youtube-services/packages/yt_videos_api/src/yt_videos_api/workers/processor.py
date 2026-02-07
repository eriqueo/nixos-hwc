"""Main job processor - claims and processes video download jobs"""

import asyncio
from pathlib import Path
from yt_core.database import DatabasePool
from yt_core.jobs import claim_jobs, update_job_status
from yt_core.youtube import YouTubeClient
from yt_core.ratelimit import YouTubeRateLimiter, YouTubeQuotaTracker
import structlog
from ..config import Config
from ..download import ytdlp, atomic, metadata

logger = structlog.get_logger()


class VideoProcessor:
    """Processes video download jobs"""

    def __init__(self, db_pool: DatabasePool, config: Config):
        self.db_pool = db_pool
        self.config = config
        self.running = False

        # Rate limiters
        self.http_limiter = YouTubeRateLimiter(
            requests_per_second=config.rate_limit_rps,
            burst=config.rate_limit_burst,
        )
        self.quota_tracker = YouTubeQuotaTracker(quota_limit=config.quota_limit)

        # YouTube client (only if API key provided)
        self.youtube_client = None
        if config.youtube_api_key:
            self.youtube_client = YouTubeClient(config.youtube_api_key)

    async def run(self, shutdown_event: asyncio.Event):
        """Main worker loop"""
        self.running = True
        logger.info("processor.started")

        while not shutdown_event.is_set():
            try:
                # Claim pending jobs
                async with self.db_pool.acquire() as conn:
                    jobs = await claim_jobs(conn, "yt_videos", max_jobs=1)

                if not jobs:
                    # No jobs available, sleep briefly
                    await asyncio.sleep(1)
                    continue

                # Process each job
                for job in jobs:
                    if shutdown_event.is_set():
                        break
                    await self._process_job(job)

            except Exception as e:
                logger.exception("processor.error", error=str(e))
                await asyncio.sleep(5)

        logger.info("processor.stopped")

    async def stop(self):
        """Stop the processor"""
        self.running = False

    async def _process_job(self, job):
        """Process a single job"""
        job_id = str(job["id"])
        entity_type = job["entity_type"]
        entity_id = job["entity_id"]

        logger.info(
            "job.processing",
            job_id=job_id,
            entity_type=entity_type,
            entity_id=entity_id,
        )

        try:
            # Get list of video IDs
            if entity_type == "video":
                video_ids = [entity_id]
            elif entity_type == "playlist":
                if not self.youtube_client:
                    raise ValueError("YouTube API key required for playlist expansion")
                video_ids = await self.youtube_client.get_playlist_videos(entity_id)
            elif entity_type == "channel":
                if not self.youtube_client:
                    raise ValueError("YouTube API key required for channel expansion")
                uploads_playlist = await self.youtube_client.get_channel_uploads_playlist(
                    entity_id
                )
                if not uploads_playlist:
                    raise ValueError(f"Channel {entity_id} not found")
                video_ids = await self.youtube_client.get_playlist_videos(
                    uploads_playlist
                )
            else:
                raise ValueError(f"Unknown entity type: {entity_type}")

            # Create job_videos records and ensure video metadata
            async with self.db_pool.acquire() as conn:
                for position, video_id in enumerate(video_ids):
                    # Get/create video metadata
                    await self._ensure_video_metadata(conn, video_id)

                    # Link video to job
                    await conn.execute(
                        """
                        INSERT INTO yt_videos.job_videos (job_id, video_id, position)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (job_id, video_id) DO NOTHING
                        """,
                        job["id"],
                        video_id,
                        position,
                    )

            # Download videos
            successful = 0
            failed = 0
            total_bytes = 0

            for video_id in video_ids:
                try:
                    # Check if already downloaded with this container policy
                    existing = await self._check_existing_download(
                        video_id, job["container_policy"]
                    )

                    if existing:
                        logger.info(
                            "job.video_already_downloaded",
                            job_id=job_id,
                            video_id=video_id,
                        )
                        successful += 1
                        total_bytes += existing["file_size_bytes"]

                        # Mark as downloaded in job_videos
                        async with self.db_pool.acquire() as conn:
                            await conn.execute(
                                """
                                UPDATE yt_videos.job_videos
                                SET downloaded = true
                                WHERE job_id = $1 AND video_id = $2
                                """,
                                job["id"],
                                video_id,
                            )
                        continue

                    # Download the video
                    result = await self._download_video(job, video_id)

                    if result:
                        successful += 1
                        total_bytes += result["file_size"]

                        # Mark as downloaded
                        async with self.db_pool.acquire() as conn:
                            await conn.execute(
                                """
                                UPDATE yt_videos.job_videos
                                SET downloaded = true
                                WHERE job_id = $1 AND video_id = $2
                                """,
                                job["id"],
                                video_id,
                            )
                    else:
                        failed += 1

                except Exception as e:
                    logger.error(
                        "job.video_failed",
                        job_id=job_id,
                        video_id=video_id,
                        error=str(e),
                    )
                    failed += 1

            # Mark job as completed
            async with self.db_pool.acquire() as conn:
                await update_job_status(
                    conn,
                    "yt_videos",
                    job_id,
                    "completed",
                    total_videos=len(video_ids),
                    successful_downloads=successful,
                    failed_downloads=failed,
                    total_bytes_downloaded=total_bytes,
                )

            logger.info(
                "job.completed",
                job_id=job_id,
                total=len(video_ids),
                successful=successful,
                failed=failed,
                bytes=total_bytes,
            )

        except Exception as e:
            logger.exception("job.failed", job_id=job_id, error=str(e))
            async with self.db_pool.acquire() as conn:
                await update_job_status(
                    conn, "yt_videos", job_id, "failed", error_message=str(e)
                )

    async def _ensure_video_metadata(self, conn, video_id: str):
        """Ensure video metadata exists in database"""
        existing = await conn.fetchrow(
            "SELECT * FROM yt_videos.videos WHERE video_id = $1", video_id
        )

        if existing:
            return

        # Fetch metadata using yt-dlp
        info = await ytdlp.get_video_info(video_id)

        if info:
            await conn.execute(
                """
                INSERT INTO yt_videos.videos (
                    video_id, title, channel_id, channel_name, duration_seconds, published_at
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
                video_id,
                info.get("title"),
                info.get("channel_id"),
                info.get("channel_name"),
                info.get("duration_seconds"),
                info.get("published_at"),
            )
        else:
            # Insert minimal record
            await conn.execute(
                """
                INSERT INTO yt_videos.videos (video_id)
                VALUES ($1)
                ON CONFLICT (video_id) DO NOTHING
                """,
                video_id,
            )

    async def _check_existing_download(self, video_id: str, container_policy: str):
        """Check if video already downloaded with this container policy"""
        async with self.db_pool.acquire() as conn:
            return await conn.fetchrow(
                """
                SELECT * FROM yt_videos.downloads
                WHERE video_id = $1 AND container_policy = $2
                """,
                video_id,
                container_policy,
            )

    async def _download_video(self, job, video_id: str):
        """Download a single video with atomic finalization"""
        # Get video metadata
        async with self.db_pool.acquire() as conn:
            video_meta = await conn.fetchrow(
                "SELECT * FROM yt_videos.videos WHERE video_id = $1", video_id
            )

        # Build filename
        title = video_meta.get("title") or video_id
        # Sanitize filename
        safe_title = "".join(c for c in title if c.isalnum() or c in (" ", "-", "_"))[:100]
        filename = f"{safe_title} [{video_id}].{job['container_policy']}"

        # Use atomic download (staging is derived from output_directory)
        async with atomic.AtomicDownload(
            self.db_pool,
            video_id,
            job["output_directory"],
            filename,
        ) as staging_path:
            # Download with multi-extractor fallback
            download_result = await ytdlp.download_video(
                video_id,
                staging_path,
                container_policy=job["container_policy"],
                quality=self.config.quality_preference,
            )

            # Embed metadata if requested
            if job["embed_metadata"]:
                # Find thumbnail (yt-dlp downloads it)
                thumbnail_path = staging_path.with_suffix(".jpg")
                if not thumbnail_path.exists():
                    thumbnail_path = staging_path.with_suffix(".webp")

                await metadata.embed_metadata(
                    staging_path,
                    {
                        "title": video_meta.get("title"),
                        "channel_name": video_meta.get("channel_name"),
                        "published_at": video_meta.get("published_at"),
                        "video_id": video_id,
                    },
                    thumbnail_path=thumbnail_path if thumbnail_path.exists() and job["embed_cover_art"] else None,
                    container=job["container_policy"],
                )

                # Clean up thumbnail
                if thumbnail_path.exists():
                    thumbnail_path.unlink()

            # Atomic finalization happens on context exit

        # Store download record in database
        async with self.db_pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO yt_videos.downloads (
                    video_id, container_policy, extractor_used,
                    file_path, file_size_bytes
                )
                VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT (video_id, container_policy) DO UPDATE SET
                    extractor_used = EXCLUDED.extractor_used,
                    file_path = EXCLUDED.file_path,
                    file_size_bytes = EXCLUDED.file_size_bytes,
                    completed_at = NOW()
                """,
                video_id,
                job["container_policy"],
                download_result["extractor"],
                str(final_path),
                download_result["file_size"],
            )

        logger.info(
            "job.video_downloaded",
            video_id=video_id,
            file_path=str(final_path),
            file_size_bytes=download_result["file_size"],
            extractor=download_result["extractor"],
        )

        return download_result
