"""Main job processor - claims and processes transcript jobs"""

import asyncio
from yt_core.database import DatabasePool
from yt_core.jobs import claim_jobs, update_job_status
from yt_core.youtube import YouTubeClient
from yt_core.ratelimit import YouTubeRateLimiter, YouTubeQuotaTracker
import structlog
from ..config import Config
from ..extractors import video, playlist
from .strategies import extract_transcript
from ..formatters import markdown, jsonl
from pathlib import Path
import hashlib

logger = structlog.get_logger()


class TranscriptProcessor:
    """Processes transcript extraction jobs"""

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
                    jobs = await claim_jobs(conn, "yt_transcripts", max_jobs=1)

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
                video_ids = await playlist.expand_playlist(
                    self.db_pool, entity_id, self.youtube_client, self.quota_tracker
                )
            elif entity_type == "channel":
                # Get uploads playlist, then expand it
                if not self.youtube_client:
                    raise ValueError("YouTube API key required for channel expansion")
                uploads_playlist = await self.youtube_client.get_channel_uploads_playlist(
                    entity_id
                )
                if not uploads_playlist:
                    raise ValueError(f"Channel {entity_id} not found")
                video_ids = await playlist.expand_playlist(
                    self.db_pool, uploads_playlist, self.youtube_client, self.quota_tracker
                )
            else:
                raise ValueError(f"Unknown entity type: {entity_type}")

            # Create job_videos records
            async with self.db_pool.acquire() as conn:
                for position, video_id in enumerate(video_ids):
                    # Ensure video metadata exists
                    await video.ensure_video_metadata(
                        conn, video_id, self.youtube_client, self.quota_tracker
                    )

                    # Link video to job
                    await conn.execute(
                        """
                        INSERT INTO yt_transcripts.job_videos (job_id, video_id, position)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (job_id, video_id) DO NOTHING
                        """,
                        job["id"],
                        video_id,
                        position,
                    )

            # Extract transcripts for all videos
            successful = 0
            failed = 0
            language_prefs = job["language_preference"] or ["en", "en-US"]

            for video_id in video_ids:
                try:
                    result = await extract_transcript(
                        self.db_pool,
                        video_id,
                        language_prefs,
                        self.http_limiter,
                    )
                    if result["strategy"] != "none":
                        successful += 1

                        # Write output file
                        await self._write_output(job, video_id, result)
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
                    "yt_transcripts",
                    job_id,
                    "completed",
                    total_videos=len(video_ids),
                    successful_videos=successful,
                    failed_videos=failed,
                    output_location=str(self._get_output_dir(job)),
                )

            logger.info(
                "job.completed",
                job_id=job_id,
                total=len(video_ids),
                successful=successful,
                failed=failed,
            )

        except Exception as e:
            logger.exception("job.failed", job_id=job_id, error=str(e))
            async with self.db_pool.acquire() as conn:
                await update_job_status(
                    conn, "yt_transcripts", job_id, "failed", error_message=str(e)
                )

    def _get_output_dir(self, job) -> Path:
        """Get output directory for job"""
        output_dir = Path(self.config.output_directory) / str(job["id"])
        output_dir.mkdir(parents=True, exist_ok=True)
        return output_dir

    async def _write_output(self, job, video_id: str, result: dict):
        """Write transcript to output file"""
        output_dir = self._get_output_dir(job)
        output_format = job["output_format"]

        # Get video metadata
        async with self.db_pool.acquire() as conn:
            video_meta = await conn.fetchrow(
                "SELECT * FROM yt_transcripts.videos WHERE video_id = $1", video_id
            )
            transcript = await conn.fetchrow(
                """
                SELECT * FROM yt_transcripts.transcripts
                WHERE video_id = $1 AND language_code = $2
                """,
                video_id,
                result["language"],
            )

        if output_format == "markdown":
            content = markdown.format_transcript(video_meta, transcript, result)
            ext = "md"
        else:  # jsonl
            content = jsonl.format_transcript(video_meta, transcript, result)
            ext = "jsonl"

        # Write file
        filename = f"{video_id}.{ext}"
        filepath = output_dir / filename
        filepath.write_text(content, encoding="utf-8")

        logger.info(
            "job.output_written",
            video_id=video_id,
            filepath=str(filepath),
            size_bytes=len(content),
        )
