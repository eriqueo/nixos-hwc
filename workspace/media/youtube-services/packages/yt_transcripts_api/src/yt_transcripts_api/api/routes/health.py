"""Health check endpoint"""

from fastapi import APIRouter, Depends
from yt_core.database import DatabasePool
import structlog

from ..dependencies import get_db_pool
from ..models import HealthResponse

router = APIRouter()
logger = structlog.get_logger()


@router.get("/health", response_model=HealthResponse)
async def health_check(
    db_pool: DatabasePool = Depends(get_db_pool),
):
    """
    Health check endpoint.

    Returns service status, database connectivity, and worker information.
    """
    # Check database connectivity
    db_status = "disconnected"
    try:
        async with db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        db_status = "connected"
    except Exception as e:
        logger.error("health.database_error", error=str(e))

    # Get worker status (count of pending/processing jobs)
    worker_status = None
    try:
        async with db_pool.acquire() as conn:
            pending = await conn.fetchval(
                "SELECT COUNT(*) FROM yt_transcripts.jobs WHERE status = 'pending'"
            )
            processing = await conn.fetchval(
                "SELECT COUNT(*) FROM yt_transcripts.jobs WHERE status = 'processing'"
            )
            worker_status = {
                "pending_jobs": pending,
                "processing_jobs": processing,
            }
    except Exception as e:
        logger.error("health.worker_status_error", error=str(e))

    status = "healthy" if db_status == "connected" else "unhealthy"

    return HealthResponse(
        status=status,
        database=db_status,
        worker_status=worker_status,
    )
