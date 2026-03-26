"""YouTube-specific rate limiters"""

import time
from typing import Optional
import structlog
from .token_bucket import TokenBucket

logger = structlog.get_logger()


class YouTubeRateLimiter:
    """
    Rate limiter for HTTP scraping (non-API).

    Conservative limits:
    - 10 requests/second
    - Burst of 50 for handling spikes
    """

    def __init__(self, requests_per_second: int = 10, burst: int = 50):
        self.bucket = TokenBucket(capacity=burst, refill_rate=requests_per_second)

    async def __aenter__(self):
        await self.bucket.acquire(1)
        return self

    async def __aexit__(self, *args):
        pass


class YouTubeQuotaTracker:
    """
    Quota tracker for YouTube Data API.

    YouTube quota: 10,000 units/day
    - videos.list: 1 unit
    - playlistItems.list: 1 unit
    - search: 100 units

    Tracks usage and prevents quota exhaustion.
    """

    DAILY_QUOTA = 10000
    QUOTA_WINDOW = 24 * 60 * 60  # 24 hours in seconds

    def __init__(self, quota_limit: Optional[int] = None):
        self.quota_limit = quota_limit or self.DAILY_QUOTA
        self.quota_used = 0
        self.window_start = time.time()

    def _check_window_reset(self):
        """Reset quota if window has elapsed"""
        now = time.time()
        if now - self.window_start >= self.QUOTA_WINDOW:
            logger.info(
                "youtube_quota.reset",
                quota_used=self.quota_used,
                quota_limit=self.quota_limit,
            )
            self.quota_used = 0
            self.window_start = now

    async def consume(self, units: int):
        """
        Consume quota units.

        Args:
            units: Number of quota units to consume

        Raises:
            RuntimeError: If quota would be exceeded
        """
        self._check_window_reset()

        if self.quota_used + units > self.quota_limit:
            time_until_reset = self.QUOTA_WINDOW - (time.time() - self.window_start)
            logger.error(
                "youtube_quota.exceeded",
                quota_used=self.quota_used,
                quota_limit=self.quota_limit,
                units_requested=units,
                reset_in_seconds=time_until_reset,
            )
            raise RuntimeError(
                f"YouTube quota exceeded: {self.quota_used}/{self.quota_limit} "
                f"(reset in {time_until_reset:.0f}s)"
            )

        self.quota_used += units
        logger.debug(
            "youtube_quota.consumed",
            units=units,
            quota_used=self.quota_used,
            quota_limit=self.quota_limit,
        )

    async def __aenter__(self):
        # Default to 1 unit (e.g., videos.list, playlistItems.list)
        await self.consume(1)
        return self

    async def __aexit__(self, *args):
        pass
