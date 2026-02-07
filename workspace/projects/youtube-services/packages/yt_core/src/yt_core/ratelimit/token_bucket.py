"""Token bucket rate limiter"""

import asyncio
import time
from dataclasses import dataclass
import structlog

logger = structlog.get_logger()


@dataclass
class TokenBucket:
    """
    Token bucket rate limiter with async support.

    Allows burst traffic up to capacity, then enforces
    steady rate of refill_rate tokens per second.
    """

    capacity: int
    refill_rate: float  # tokens per second

    def __post_init__(self):
        self.tokens = float(self.capacity)
        self.last_refill = time.monotonic()
        self._lock = asyncio.Lock()

    async def acquire(self, tokens: int = 1) -> None:
        """
        Acquire tokens, waiting if necessary.

        Blocks until sufficient tokens are available.
        """
        async with self._lock:
            while self.tokens < tokens:
                # Calculate wait time
                deficit = tokens - self.tokens
                wait_time = deficit / self.refill_rate

                logger.debug(
                    "token_bucket.waiting",
                    tokens_needed=tokens,
                    tokens_available=self.tokens,
                    wait_seconds=wait_time,
                )

                await asyncio.sleep(wait_time)
                self._refill()

            self.tokens -= tokens
            logger.debug(
                "token_bucket.acquired",
                tokens_acquired=tokens,
                tokens_remaining=self.tokens,
            )

    def _refill(self):
        """Refill tokens based on elapsed time"""
        now = time.monotonic()
        elapsed = now - self.last_refill

        new_tokens = elapsed * self.refill_rate
        self.tokens = min(self.capacity, self.tokens + new_tokens)
        self.last_refill = now
