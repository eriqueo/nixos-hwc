"""
Configurable Multi-Platform Social Media Scraper

A Playwright-based scraper with support for multiple sites,
rate limiting, deduplication, and multiple output formats.
"""

__version__ = "2.0.0"

from .models import Post, Comment, SiteConfig, SitesConfig
from .exceptions import (
    ScraperError,
    ConfigurationError,
    ExtractionError,
    RateLimitError,
    AuthenticationError,
)
from .config import load_config, get_site_config, get_auth_file_path
from .extractor import extract_all_posts, ExtractionMetrics
from .deduplicator import PostDeduplicator
from .storage import get_storage_backend, STORAGE_BACKENDS
from .rate_limiter import AdaptiveRateLimiter, RateLimitConfig
from .logging_config import setup_logging, get_logger
from .auth import perform_auto_login, ensure_authenticated, read_secret

__all__ = [
    # Models
    "Post",
    "Comment",
    "SiteConfig",
    "SitesConfig",
    # Exceptions
    "ScraperError",
    "ConfigurationError",
    "ExtractionError",
    "RateLimitError",
    "AuthenticationError",
    # Config
    "load_config",
    "get_site_config",
    "get_auth_file_path",
    # Extraction
    "extract_all_posts",
    "ExtractionMetrics",
    # Deduplication
    "PostDeduplicator",
    # Storage
    "get_storage_backend",
    "STORAGE_BACKENDS",
    # Rate Limiting
    "AdaptiveRateLimiter",
    "RateLimitConfig",
    # Logging
    "setup_logging",
    "get_logger",
]
