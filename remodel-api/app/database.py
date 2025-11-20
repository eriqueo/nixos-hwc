"""
Database connection and utilities
"""
import os
from typing import AsyncGenerator
import asyncpg
from asyncpg.pool import Pool

# Database configuration from environment
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://remodel:remodel@localhost:5432/remodel"
)

# Global connection pool
_pool: Pool | None = None


async def get_db_pool() -> Pool:
    """
    Get or create the database connection pool.

    Returns:
        asyncpg.Pool: The database connection pool
    """
    global _pool

    if _pool is None:
        _pool = await asyncpg.create_pool(
            DATABASE_URL,
            min_size=2,
            max_size=10,
            command_timeout=60
        )

    return _pool


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
