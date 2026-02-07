"""Pydantic request/response models"""

from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
from uuid import UUID


class JobCreateRequest(BaseModel):
    """Request to create a new transcript extraction job"""

    entity_type: str = Field(..., pattern="^(video|playlist|channel)$")
    entity_id: str = Field(..., min_length=1)
    output_format: str = Field(default="markdown", pattern="^(markdown|jsonl)$")
    language_preference: Optional[List[str]] = Field(default=None)
    idempotency_key: Optional[str] = None


class JobResponse(BaseModel):
    """Job status response"""

    id: UUID
    entity_type: str
    entity_id: str
    status: str
    requested_at: datetime
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    output_format: str
    language_preference: Optional[List[str]] = None
    total_videos: int
    successful_videos: int
    failed_videos: int
    output_location: Optional[str] = None
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
    worker_status: Optional[dict] = None
