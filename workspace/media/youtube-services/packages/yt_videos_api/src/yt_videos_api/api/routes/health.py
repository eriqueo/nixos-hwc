"""Health check endpoint"""

from fastapi import APIRouter, Depends
from yt_core.database import DatabasePool
import structlog
import subprocess
import shutil
import os

from ..dependencies import get_db_pool, get_config
from ..models import HealthResponse
from ...config import Config

router = APIRouter()
logger = structlog.get_logger()


@router.get("/health", response_model=HealthResponse)
async def health_check(
    db_pool: DatabasePool = Depends(get_db_pool),
    config: Config = Depends(get_config),
):
    """
    Health check endpoint.

    Returns service status, database connectivity, yt-dlp version,
    and disk space information.
    """
    # Check database connectivity
    db_status = "disconnected"
    try:
        async with db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        db_status = "connected"
    except Exception as e:
        logger.error("health.database_error", error=str(e))

    # Get yt-dlp version
    ytdlp_version = "unknown"
    try:
        result = subprocess.run(
            ["yt-dlp", "--version"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            ytdlp_version = result.stdout.strip()
    except Exception as e:
        logger.error("health.ytdlp_version_error", error=str(e))

    # Get worker status (count of pending/processing jobs)
    worker_status = None
    try:
        async with db_pool.acquire() as conn:
            pending = await conn.fetchval(
                "SELECT COUNT(*) FROM yt_videos.jobs WHERE status = 'pending'"
            )
            processing = await conn.fetchval(
                "SELECT COUNT(*) FROM yt_videos.jobs WHERE status = 'processing'"
            )
            worker_status = {
                "pending_jobs": pending,
                "processing_jobs": processing,
            }
    except Exception as e:
        logger.error("health.worker_status_error", error=str(e))

    # Check disk space
    disk_space = None
    try:
        stat = shutil.disk_usage(config.output_directory)
        disk_space = {
            "output_directory": config.output_directory,
            "total_bytes": stat.total,
            "used_bytes": stat.used,
            "available_bytes": stat.free,
            "percent_used": (stat.used / stat.total * 100),
        }
    except Exception as e:
        logger.error("health.disk_space_error", error=str(e))

    status = "healthy" if db_status == "connected" else "unhealthy"

    return HealthResponse(
        status=status,
        database=db_status,
        yt_dlp_version=ytdlp_version,
        worker_status=worker_status,
        disk_space=disk_space,
    )
