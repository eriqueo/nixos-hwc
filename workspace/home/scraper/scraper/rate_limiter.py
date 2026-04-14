"""Adaptive rate limiting for scraping."""

from dataclasses import dataclass, field
from time import sleep, time

from .logging_config import get_logger


@dataclass
class RateLimitConfig:
    """Configuration for rate limiting."""

    min_delay: float = 2.0  # Minimum seconds between requests
    max_delay: float = 60.0  # Maximum backoff delay
    requests_per_minute: int = 20
    backoff_multiplier: float = 1.5


@dataclass
class AdaptiveRateLimiter:
    """
    Rate limiter with exponential backoff.

    Tracks request timing and adjusts delays based on success/failure.
    """

    config: RateLimitConfig = field(default_factory=RateLimitConfig)
    request_times: list[float] = field(default_factory=list)
    current_delay: float = field(init=False)
    consecutive_errors: int = field(default=0)

    def __post_init__(self) -> None:
        self.current_delay = self.config.min_delay

    def wait(self) -> None:
        """Wait appropriate time before next request."""
        logger = get_logger()
        now = time()

        # Remove timestamps older than 1 minute
        cutoff = now - 60
        self.request_times = [t for t in self.request_times if t > cutoff]

        # Check rate limit
        if len(self.request_times) >= self.config.requests_per_minute:
            sleep_time = 60 - (now - self.request_times[0])
            if sleep_time > 0:
                logger.info(f"Rate limit reached, waiting {sleep_time:.1f}s")
                sleep(sleep_time)

        # Apply current delay (may be increased due to errors)
        logger.debug(f"Waiting {self.current_delay:.1f}s before next request")
        sleep(self.current_delay)

        self.request_times.append(time())

    def record_success(self) -> None:
        """Reset delay after successful request."""
        self.consecutive_errors = 0
        self.current_delay = max(
            self.config.min_delay,
            self.current_delay / self.config.backoff_multiplier,
        )

    def record_error(self) -> None:
        """Increase delay after error."""
        logger = get_logger()
        self.consecutive_errors += 1
        self.current_delay = min(
            self.config.max_delay,
            self.current_delay * self.config.backoff_multiplier,
        )
        logger.warning(
            f"Error #{self.consecutive_errors}, "
            f"increasing delay to {self.current_delay:.1f}s"
        )
