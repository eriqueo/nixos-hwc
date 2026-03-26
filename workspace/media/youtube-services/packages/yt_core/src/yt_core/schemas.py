"""Shared Pydantic models for YouTube services"""

from datetime import datetime
from typing import Optional, List
from enum import Enum
from pydantic import BaseModel, Field
from uuid import UUID


class JobStatus(str, Enum):
    """Canonical job status values"""
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class EntityType(str, Enum):
    """YouTube entity types"""
    VIDEO = "video"
    PLAYLIST = "playlist"
    CHANNEL = "channel"


class JobBase(BaseModel):
    """
    Canonical job table shape (shared contract).

    Services extend this with service-specific fields but MUST include:
    - Lease fields: locked_at, locked_by, lease_expires_at
    - Retry logic: attempts, next_run_at
    - Quota tracking: quota_units_used
    """
    id: UUID
    status: JobStatus
    entity_type: EntityType
    entity_id: str
    requested_at: datetime
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None

    # Lease management (crash recovery)
    locked_at: Optional[datetime] = None
    locked_by: Optional[str] = None  # Worker ID or hostname
    lease_expires_at: Optional[datetime] = None

    # Retry logic
    attempts: int = 0
    max_attempts: int = 3
    next_run_at: Optional[datetime] = None

    # Quota tracking (YouTube Data API)
    quota_units_used: int = 0

    # Error tracking
    error_message: Optional[str] = None
    last_error: Optional[str] = None


class VideoMetadata(BaseModel):
    """Shared video metadata (deduplicated across services)"""
    video_id: str
    title: Optional[str] = None
    channel_id: Optional[str] = None
    channel_name: Optional[str] = None
    duration_seconds: Optional[int] = None
    published_at: Optional[datetime] = None
    last_fetched_at: datetime = Field(default_factory=datetime.now)


class TranscriptJob(JobBase):
    """Transcript extraction job (extends canonical shape)"""
    output_format: str = "markdown"
    language_preference: List[str] = ["en", "en-US", "en-GB"]
    output_location: Optional[str] = None
    total_videos: int = 0
    successful_videos: int = 0
    failed_videos: int = 0


class DownloadJob(JobBase):
    """Video download job (extends canonical shape)"""
    output_directory: str
    container_policy: str = "webm"
    embed_metadata: bool = True
    embed_cover_art: bool = True
    remove_after_download: bool = False
    total_videos: int = 0
    successful_downloads: int = 0
    failed_downloads: int = 0
    total_bytes_downloaded: int = 0


class QuotaUsage(BaseModel):
    """Daily YouTube API quota tracking"""
    date: str  # YYYY-MM-DD
    quota_units_used: int = 0
    quota_limit: int = 10000

    def can_consume(self, units: int) -> bool:
        """Check if quota allows consuming N units"""
        return (self.quota_units_used + units) <= self.quota_limit

    def consume(self, units: int) -> None:
        """Consume N quota units (raises if exceeds limit)"""
        if not self.can_consume(units):
            raise RuntimeError(
                f"YouTube quota exceeded: {self.quota_units_used + units}/{self.quota_limit}"
            )
        self.quota_units_used += units
