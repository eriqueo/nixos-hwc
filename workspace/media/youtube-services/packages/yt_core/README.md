# yt_core

Shared core library for YouTube services (yt-transcripts-api and yt-videos-api).

## Features

### Database Connection Pooling
- `DatabasePool`: asyncpg connection pool with prepared statement caching
- Configurable pool size (default: 5-20 connections)
- Automatic connection lifecycle management

### Job Queue System
- `claim_jobs()`: Atomic job claiming using PostgreSQL `FOR UPDATE SKIP LOCKED`
- `update_job_status()`: Update job status and metadata
- Supports multiple worker instances running in parallel

### Rate Limiting
- `TokenBucket`: Generic token bucket rate limiter with async support
- `YouTubeRateLimiter`: HTTP scraping rate limiter (10 req/s, burst 50)
- `YouTubeQuotaTracker`: YouTube Data API quota tracker (10,000 units/day)

### Distributed Locking
- `advisory_lock()`: PostgreSQL advisory locks for distributed coordination
- Transaction-scoped locks that auto-release on commit/rollback

### YouTube Data API Client
- `YouTubeClient`: Wrapper for YouTube Data API v3
- Methods: `get_video_metadata()`, `get_playlist_videos()`, `get_channel_uploads_playlist()`
- Quota-aware operations

### Utilities
- `configure_logging()`: Structured logging with structlog (JSON output)
- `exponential_backoff()`: Retry with exponential backoff and jitter

## Installation

```bash
cd packages/yt_core
pip install -e .
```

## Usage

```python
from yt_core.database import DatabasePool
from yt_core.jobs import claim_jobs, update_job_status
from yt_core.ratelimit import YouTubeQuotaTracker
from yt_core.locking import advisory_lock
from yt_core.utils import configure_logging

# Configure logging
configure_logging("my-service")

# Create database pool
db_pool = DatabasePool("postgresql://user:pass@localhost/db")
await db_pool.connect()

# Claim jobs
async with db_pool.acquire() as conn:
    jobs = await claim_jobs(conn, "yt_transcripts", max_jobs=5)

# Use advisory lock
async with db_pool.acquire() as conn:
    async with conn.transaction():
        async with advisory_lock(conn, f"video:{video_id}"):
            # Exclusively locked work here
            pass

# Track YouTube API quota
quota_tracker = YouTubeQuotaTracker()
await quota_tracker.consume(1)  # videos.list
```

## Dependencies

- sqlalchemy[asyncio]>=2.0
- asyncpg>=0.29
- alembic>=1.13
- pydantic>=2.5
- pydantic-settings>=2.1
- google-api-python-client>=2.100
- httpx>=0.25
- structlog>=24.0
