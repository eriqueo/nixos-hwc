"""FastAPI dependency injection"""

from fastapi import Request
from yt_core.database import DatabasePool
from ..config import Config


async def get_db_pool(request: Request) -> DatabasePool:
    """Get database pool from app state"""
    return request.app.state.db_pool


async def get_config(request: Request) -> Config:
    """Get config from app state"""
    return request.app.state.config
