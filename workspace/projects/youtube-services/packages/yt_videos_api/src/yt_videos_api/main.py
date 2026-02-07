"""FastAPI application for video download API"""

from contextlib import asynccontextmanager
from fastapi import FastAPI
from yt_core.database import DatabasePool
from yt_core.utils import configure_logging
from .config import config
from .api.routes import jobs, health
import structlog

logger = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifecycle manager for FastAPI app.

    NOTE: Worker runs as separate systemd unit, NOT embedded here.
    """
    # Configure structured logging
    configure_logging("yt-videos-api", level=config.log_level)

    logger.info(
        "api.starting",
        host=config.host,
        port=config.port,
        output_dir=config.output_directory,
    )

    # Initialize database pool
    db_pool = DatabasePool(config.database_url, min_size=5, max_size=20)
    await db_pool.connect()

    # Store in app state for dependency injection
    app.state.db_pool = db_pool
    app.state.config = config

    logger.info("api.started")

    yield

    # Shutdown
    logger.info("api.shutting_down")
    await db_pool.close()
    logger.info("api.shutdown_complete")


# Create FastAPI app
app = FastAPI(
    title="YouTube Videos API",
    description="Download and archive YouTube videos with metadata",
    version="0.1.0",
    lifespan=lifespan,
)

# Include routers
app.include_router(jobs.router, prefix="/jobs", tags=["jobs"])
app.include_router(health.router, tags=["health"])


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "yt-videos-api",
        "version": "0.1.0",
        "status": "running",
    }
