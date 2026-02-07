"""
Separate worker entry point for processing video download jobs.

Runs independently from FastAPI server.
"""

import asyncio
import signal
from yt_core.database import DatabasePool
from yt_core.utils import configure_logging
from .config import config
from .workers.processor import VideoProcessor
import structlog

logger = structlog.get_logger()


class WorkerService:
    """Worker service that processes video download jobs"""

    def __init__(self):
        self.db_pool: DatabasePool | None = None
        self.processor: VideoProcessor | None = None
        self.shutdown_event = asyncio.Event()

    async def start(self):
        """Start the worker service"""
        # Configure logging
        configure_logging("yt-videos-worker", level=config.log_level)

        logger.info(
            "worker.starting",
            workers=config.workers,
            output_dir=config.output_directory,
        )

        # Initialize database pool
        self.db_pool = DatabasePool(config.database_url, min_size=5, max_size=20)
        await self.db_pool.connect()

        # Create processor
        self.processor = VideoProcessor(self.db_pool, config)

        logger.info("worker.started")

        # Run processor until shutdown
        await self.processor.run(self.shutdown_event)

    async def stop(self):
        """Graceful shutdown"""
        logger.info("worker.shutting_down")
        self.shutdown_event.set()

        if self.processor:
            await self.processor.stop()

        if self.db_pool:
            await self.db_pool.close()

        logger.info("worker.shutdown_complete")


async def main():
    """Main entry point for worker"""
    service = WorkerService()

    # Setup signal handlers for graceful shutdown
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(service.stop()))

    try:
        await service.start()
    except Exception as e:
        logger.exception("worker.fatal_error", error=str(e))
        raise
    finally:
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())
