"""PostgreSQL advisory locks for distributed coordination"""

import hashlib
from contextlib import asynccontextmanager
import asyncpg
import structlog

logger = structlog.get_logger()


class AdvisoryLock:
    """
    PostgreSQL advisory lock for distributed coordination.

    Uses pg_advisory_xact_lock for transaction-scoped locks
    that automatically release on commit/rollback.
    """

    def __init__(self, conn: asyncpg.Connection, key: str):
        self.conn = conn
        # Hash key to 64-bit signed integer for PostgreSQL
        self.lock_id = int.from_bytes(
            hashlib.sha256(key.encode()).digest()[:8],
            "big",
            signed=True,
        )
        self.key = key

    async def acquire(self):
        """Acquire lock (blocks until available)"""
        logger.debug("advisory_lock.acquiring", key=self.key, lock_id=self.lock_id)
        await self.conn.execute("SELECT pg_advisory_xact_lock($1)", self.lock_id)
        logger.debug("advisory_lock.acquired", key=self.key)

    async def try_acquire(self) -> bool:
        """Try to acquire lock (returns immediately)"""
        logger.debug(
            "advisory_lock.try_acquiring", key=self.key, lock_id=self.lock_id
        )
        result = await self.conn.fetchval(
            "SELECT pg_try_advisory_xact_lock($1)", self.lock_id
        )
        if result:
            logger.debug("advisory_lock.acquired", key=self.key)
        else:
            logger.debug("advisory_lock.not_acquired", key=self.key)
        return result


@asynccontextmanager
async def advisory_lock(conn: asyncpg.Connection, key: str):
    """
    Context manager for advisory locks.

    Args:
        conn: Database connection (must be in a transaction)
        key: String key to lock on

    Example:
        async with db_pool.acquire() as conn:
            async with conn.transaction():
                async with advisory_lock(conn, f"download:{video_id}"):
                    # Exclusively locked work here
                    await finalize_download(video_id)
    """
    lock = AdvisoryLock(conn, key)
    await lock.acquire()
    try:
        yield lock
    finally:
        # Lock releases automatically on transaction end
        logger.debug("advisory_lock.released", key=key)
