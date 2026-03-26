"""Exponential backoff retry utilities"""

import asyncio
import random
from typing import Optional, Callable, TypeVar
import structlog

logger = structlog.get_logger()

T = TypeVar("T")


async def exponential_backoff(
    func: Callable[[], T],
    max_retries: int = 5,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0,
    jitter: bool = True,
    retry_exceptions: tuple = (Exception,),
) -> T:
    """
    Retry a function with exponential backoff.

    Args:
        func: Async function to retry
        max_retries: Maximum number of retry attempts
        base_delay: Initial delay in seconds
        max_delay: Maximum delay in seconds
        exponential_base: Base for exponential calculation
        jitter: Add random jitter to delay
        retry_exceptions: Tuple of exceptions to retry on

    Returns:
        Result of func()

    Raises:
        Last exception if all retries exhausted
    """
    last_exception: Optional[Exception] = None

    for attempt in range(max_retries + 1):
        try:
            if asyncio.iscoroutinefunction(func):
                return await func()
            else:
                return func()
        except retry_exceptions as e:
            last_exception = e

            if attempt >= max_retries:
                logger.error(
                    "retry.exhausted",
                    func=func.__name__,
                    attempts=attempt + 1,
                    error=str(e),
                )
                raise

            # Calculate delay with exponential backoff
            delay = min(base_delay * (exponential_base**attempt), max_delay)

            # Add jitter (±25%)
            if jitter:
                jitter_amount = delay * 0.25
                delay = delay + random.uniform(-jitter_amount, jitter_amount)

            logger.warning(
                "retry.attempt",
                func=func.__name__,
                attempt=attempt + 1,
                max_retries=max_retries,
                delay_seconds=delay,
                error=str(e),
            )

            await asyncio.sleep(delay)

    # Should never reach here, but satisfy type checker
    if last_exception:
        raise last_exception
    raise RuntimeError("Unexpected retry loop exit")
