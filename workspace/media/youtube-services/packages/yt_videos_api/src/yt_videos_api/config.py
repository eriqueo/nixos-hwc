"""Service configuration"""

from pydantic_settings import BaseSettings
from typing import Optional


class Config(BaseSettings):
    """Configuration for yt-videos-api"""

    # Database
    database_url: str

    # YouTube API (optional, only for playlist expansion)
    youtube_api_key: Optional[str] = None

    # Server
    host: str = "127.0.0.1"
    port: int = 8101

    # Worker
    workers: int = 4

    # Output
    output_directory: str = "/mnt/media/youtube"
    staging_directory: str = "/var/lib/hwc/yt-videos-api/staging"

    # Download settings
    container_policy: str = "webm"  # webm, mp4, mkv
    quality_preference: str = "best"
    embed_metadata: bool = True
    embed_cover_art: bool = True

    # Rate limiting
    rate_limit_rps: int = 10  # HTTP requests per second
    rate_limit_burst: int = 50
    quota_limit: int = 10000  # YouTube Data API daily quota

    # Logging
    log_level: str = "INFO"

    class Config:
        env_prefix = "YT_VIDEOS_"
        case_sensitive = False


# Global config instance
config = Config()
