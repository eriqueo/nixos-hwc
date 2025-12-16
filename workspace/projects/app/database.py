"""
Database connection and utilities
"""
import os
import asyncio
import logging
from typing import AsyncGenerator
import asyncpg
from asyncpg.pool import Pool

logger = logging.getLogger(__name__)

# Database configuration from environment
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://remodel:remodel@localhost:5432/remodel"
)

# Global connection pool
_pool: Pool | None = None


async def get_db_pool(max_retries: int = 5, retry_delay: float = 2.0) -> Pool:
    """
    Get or create the database connection pool with retry logic.

    Args:
        max_retries: Maximum number of connection attempts
        retry_delay: Seconds to wait between retries

    Returns:
        asyncpg.Pool: The database connection pool

    Raises:
        Exception: If connection fails after all retries
    """
    global _pool

    if _pool is not None:
        return _pool

    # Validate DATABASE_URL is set
    if not DATABASE_URL or DATABASE_URL == "postgresql://remodel:remodel@localhost:5432/remodel":
        logger.warning("⚠️  Using default DATABASE_URL - this may not work in production!")

    logger.info(f"Connecting to database: {DATABASE_URL.split('@')[-1]}")  # Don't log password

    last_error = None
    for attempt in range(1, max_retries + 1):
        try:
            logger.info(f"Database connection attempt {attempt}/{max_retries}")

            _pool = await asyncpg.create_pool(
                DATABASE_URL,
                min_size=2,
                max_size=10,
                command_timeout=60,
                timeout=10  # Connection timeout
            )

            # Test the connection
            async with _pool.acquire() as conn:
                await conn.fetchval("SELECT 1")

            logger.info("✓ Database connection pool created successfully")
            return _pool

        except asyncpg.InvalidPasswordError as e:
            logger.error(f"❌ Invalid database password: {e}")
            raise  # Don't retry on auth errors

        except asyncpg.InvalidCatalogNameError as e:
            logger.error(f"❌ Database does not exist: {e}")
            raise  # Don't retry if DB doesn't exist

        except Exception as e:
            last_error = e
            logger.warning(
                f"Database connection attempt {attempt}/{max_retries} failed: {e}"
            )

            if attempt < max_retries:
                wait_time = retry_delay * attempt  # Exponential backoff
                logger.info(f"Retrying in {wait_time:.1f} seconds...")
                await asyncio.sleep(wait_time)
            else:
                logger.error(f"❌ Failed to connect to database after {max_retries} attempts")
                raise Exception(f"Database connection failed: {last_error}") from last_error

    raise Exception("Database connection failed - this should not be reached")


async def close_db_pool():
    """Close the database connection pool"""
    global _pool

    if _pool is not None:
        await _pool.close()
        _pool = None


async def get_db_connection() -> AsyncGenerator[asyncpg.Connection, None]:
    """
    Dependency for FastAPI routes to get a database connection.

    Usage:
        @app.get("/endpoint")
        async def endpoint(conn = Depends(get_db_connection)):
            result = await conn.fetch("SELECT ...")

    Yields:
        asyncpg.Connection: A database connection from the pool
    """
    pool = await get_db_pool()

    async with pool.acquire() as connection:
        yield connection


async def execute_query(query: str, *args, fetch: str = "all"):
    """
    Execute a query and return results.

    Args:
        query: SQL query string
        *args: Query parameters
        fetch: "all", "one", or "val" for fetchall/fetchone/fetchval

    Returns:
        Query results based on fetch type
    """
    pool = await get_db_pool()

    async with pool.acquire() as conn:
        if fetch == "all":
            return await conn.fetch(query, *args)
        elif fetch == "one":
            return await conn.fetchrow(query, *args)
        elif fetch == "val":
            return await conn.fetchval(query, *args)
        else:
            raise ValueError(f"Invalid fetch type: {fetch}")


async def execute_many(query: str, args_list: list):
    """
    Execute a query multiple times with different parameters.

    Args:
        query: SQL query string
        args_list: List of parameter tuples
    """
    pool = await get_db_pool()

    async with pool.acquire() as conn:
        await conn.executemany(query, args_list)
