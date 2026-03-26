"""Custom exceptions for the scraper."""


class ScraperError(Exception):
    """Base exception for all scraper errors."""

    pass


class ConfigurationError(ScraperError):
    """Raised when configuration is invalid or missing."""

    pass


class ExtractionError(ScraperError):
    """Raised when data extraction fails."""

    pass


class RateLimitError(ScraperError):
    """Raised when rate limit is exceeded."""

    pass


class AuthenticationError(ScraperError):
    """Raised when authentication fails or is required."""

    pass


class NavigationError(ScraperError):
    """Raised when page navigation fails."""

    pass
