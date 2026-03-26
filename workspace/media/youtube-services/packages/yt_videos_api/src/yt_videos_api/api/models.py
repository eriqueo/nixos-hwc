"""Pydantic request/response models"""

from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
from uuid import UUID


class JobCreateRequest(BaseModel):
    """Request to create a new video download job"""

    entity_type: str = Field(..., pattern="^(video|playlist|channel)$")
    entity_id: str = Field(..., min_length=1)
    output_directory: Optional[str] = None
    container_policy: str = Field(default="webm", pattern="^(webm|mp4|mkv)$")
    embed_metadata: bool = True
    embed_cover_art: bool = True
    remove_after_download: bool = False
    idempotency_key: Optional[str] = None


class DownloadInfo(BaseModel):
    """Information about a single download"""

    video_id: str
    title: Optional[str] = None
    status: str
    file_path: Optional[str] = None
    file_size_bytes: Optional[int] = None
    extractor_used: Optional[str] = None


class JobResponse(BaseModel):
    """Job status response"""

    id: UUID
    entity_type: str
    entity_id: str
    status: str
    requested_at: datetime
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    output_directory: str
    container_policy: str
    total_videos: int
    successful_downloads: int
    failed_downloads: int
    total_bytes_downloaded: int
    error_message: Optional[str] = None

    class Config:
        from_attributes = True


class JobListResponse(BaseModel):
    """Paginated job list response"""

    jobs: List[JobResponse]
    total: int
    limit: int
    offset: int


class HealthResponse(BaseModel):
    """Health check response"""

    status: str
    database: str
    yt_dlp_version: str
    worker_status: Optional[dict] = None
    disk_space: Optional[dict] = None
