"""Service configuration"""

from pydantic_settings import BaseSettings
from typing import Optional


class Config(BaseSettings):
    """Configuration for yt-transcripts-api"""

    # Database
    database_url: str

    # YouTube API
    youtube_api_key: Optional[str] = None

    # Server
    host: str = "127.0.0.1"
    port: int = 8100

    # Worker
    workers: int = 4

    # Output
    output_directory: str = "/mnt/hot/youtube-transcripts"

    # Rate limiting
    rate_limit_rps: int = 10  # HTTP requests per second
    rate_limit_burst: int = 50
    quota_limit: int = 10000  # YouTube Data API daily quota

    # Caching
    cache_expiry_seconds: int = 3600  # Playlist cache

    # Logging
    log_level: str = "INFO"

    class Config:
        env_prefix = "YT_TRANSCRIPTS_"
        case_sensitive = False


# Global config instance
config = Config()
