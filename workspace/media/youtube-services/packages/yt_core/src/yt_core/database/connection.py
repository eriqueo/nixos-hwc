"""Database connection pooling with asyncpg"""

import asyncpg
from typing import Optional
import structlog

logger = structlog.get_logger()


class DatabasePool:
    """
    Async PostgreSQL connection pool.

    Uses asyncpg for efficient connection pooling
    and prepared statement caching.
    """

    def __init__(self, dsn: str, min_size: int = 5, max_size: int = 20):
        self.dsn = dsn
        self.min_size = min_size
        self.max_size = max_size
        self._pool: Optional[asyncpg.Pool] = None

    async def connect(self):
        """Initialize connection pool"""
        logger.info(
            "database_pool.connecting",
            min_size=self.min_size,
            max_size=self.max_size,
        )
        self._pool = await asyncpg.create_pool(
            self.dsn,
            min_size=self.min_size,
            max_size=self.max_size,
            command_timeout=60,
            # Optimize for many small queries
            max_cached_statement_lifetime=300,
            max_cacheable_statement_size=1024 * 15,
        )
        logger.info("database_pool.connected")

    async def close(self):
        """Close all connections"""
        if self._pool:
            logger.info("database_pool.closing")
            await self._pool.close()
            logger.info("database_pool.closed")

    def acquire(self):
        """Acquire a connection from the pool"""
        if not self._pool:
            raise RuntimeError("Database pool not initialized. Call connect() first.")
        return self._pool.acquire()

    async def execute(self, query: str, *args):
        """Execute a query"""
        async with self.acquire() as conn:
            return await conn.execute(query, *args)

    async def fetch(self, query: str, *args):
        """Fetch multiple rows"""
        async with self.acquire() as conn:
            return await conn.fetch(query, *args)

    async def fetchrow(self, query: str, *args):
        """Fetch a single row"""
        async with self.acquire() as conn:
            return await conn.fetchrow(query, *args)

    async def fetchval(self, query: str, *args):
        """Fetch a single value"""
        async with self.acquire() as conn:
            return await conn.fetchval(query, *args)
