"""Atomic download finalization with staging area (uses yt_core.paths)"""

import hashlib
from pathlib import Path
from datetime import datetime, timedelta
from yt_core.database import DatabasePool
from yt_core.locking import advisory_lock
from yt_core.paths import get_staging_path, atomic_move
import structlog

logger = structlog.get_logger()


class AtomicDownload:
    """
    Atomic download with staging area.

    Pattern:
    1. Download to staging area inside output_directory (ensures same-FS)
    2. Run ffmpeg metadata embedding in staging
    3. Atomically move to final location using atomic_move()
    4. Update database with final path + hash
    5. Clean up staging entry

    On failure: staging file remains for debugging (cleaned by cleanup_staging)

    CRITICAL: Staging is ALWAYS derived from output_directory to ensure same-filesystem
    atomic rename. Cross-filesystem scenarios are handled transparently by atomic_move().
    """

    def __init__(
        self,
        db_pool: DatabasePool,
        video_id: str,
        output_directory: str,
        final_filename: str,
    ):
        """
        Initialize atomic download.

        Args:
            db_pool: Database connection pool
            video_id: YouTube video ID
            output_directory: Final output directory (staging is <output>/.staging/)
            final_filename: Final filename (e.g., "Video Title [vid123].webm")
        """
        self.db_pool = db_pool
        self.video_id = video_id
        self.output_directory = Path(output_directory)
        self.final_path = self.output_directory / final_filename
        self.staging_id = None
        self.staging_path = None

    async def __aenter__(self):
        """Set up staging area"""
        # Get staging path inside output_directory (enforces same-FS)
        extension = self.final_path.suffix.lstrip(".")
        self.staging_path = get_staging_path(
            str(self.output_directory),
            self.video_id,
            extension,
        )

        # Record staging entry in database
        async with self.db_pool.acquire() as conn:
            lock_expires = datetime.now() + timedelta(hours=6)
            self.staging_id = await conn.fetchval(
                """
                INSERT INTO yt_videos.staging
                (video_id, staging_path, final_path, lock_expires_at)
                VALUES ($1, $2, $3, $4)
                RETURNING id
                """,
                self.video_id,
                str(self.staging_path),
                str(self.final_path),
                lock_expires,
            )

        logger.info(
            "atomic.staging_ready",
            video_id=self.video_id,
            staging_path=str(self.staging_path),
        )

        return self.staging_path

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Finalize or cleanup on exit"""
        if exc_type is None:
            # Success: atomically finalize
            await self.finalize()
        else:
            # Failure: keep staging file for debugging
            # (cleanup_staging() will remove after configurable age)
            logger.warning(
                "atomic.download_failed",
                video_id=self.video_id,
                error=str(exc_val),
                staging_path=str(self.staging_path),
            )

    async def finalize(self):
        """Atomically finalize the download"""
        if not self.staging_path.exists():
            raise FileNotFoundError(f"Staging file not found: {self.staging_path}")

        # Calculate file hash
        file_hash = await self._calculate_hash(self.staging_path)
        file_size = self.staging_path.stat().st_size

        try:
            # Atomically move from staging to final location
            # Handles both same-FS (os.rename) and cross-FS (copy+fsync+rename)
            atomic_move(self.staging_path, self.final_path)

            # Update database with advisory lock
            async with self.db_pool.acquire() as conn:
                async with conn.transaction():
                    async with advisory_lock(conn, f"download:{self.video_id}"):
                        # Mark staging as finalized
                        await conn.execute(
                            """
                            UPDATE yt_videos.staging
                            SET finalized = true, finalized_at = NOW()
                            WHERE id = $1
                            """,
                            self.staging_id,
                        )

                        logger.info(
                            "atomic.finalized",
                            video_id=self.video_id,
                            final_path=str(self.final_path),
                            file_size_bytes=file_size,
                            file_hash=file_hash[:16],
                        )

        except Exception as e:
            logger.error(
                "atomic.finalization_failed",
                video_id=self.video_id,
                error=str(e),
            )
            raise

    async def _calculate_hash(self, filepath: Path) -> str:
        """Calculate SHA256 hash of file"""
        sha256_hash = hashlib.sha256()
        with open(filepath, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
