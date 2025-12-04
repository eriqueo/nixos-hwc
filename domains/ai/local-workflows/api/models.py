"""
Pydantic models for Local Workflows API
"""
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from enum import Enum


class WorkflowStatus(str, Enum):
    """Workflow execution status"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class ChatRequest(BaseModel):
    """Request for chat endpoint"""
    message: str = Field(..., description="User message")
    context: Optional[str] = Field(None, description="Optional context (file content, logs, etc.)")
    model: str = Field("qwen2.5-coder:3b", description="Model to use")
    system_prompt: Optional[str] = Field(None, description="Optional system prompt override")
    stream: bool = Field(True, description="Stream response via SSE")


class ChatResponse(BaseModel):
    """Response from chat endpoint"""
    response: str = Field(..., description="Model response")
    model: str = Field(..., description="Model used")
    tokens: Optional[int] = Field(None, description="Token count")


class CleanupRequest(BaseModel):
    """Request for cleanup workflow"""
    directory: str = Field(..., description="Directory to clean up")
    dry_run: bool = Field(True, description="If true, only analyze without moving files")


class CleanupAction(BaseModel):
    """Single cleanup action"""
    file: str
    action: str  # "move", "rename", "skip"
    destination: Optional[str]
    reason: str


class CleanupResponse(BaseModel):
    """Response from cleanup workflow"""
    directory: str
    files_analyzed: int
    actions: List[CleanupAction]
    dry_run: bool


class JournalRequest(BaseModel):
    """Request for journal generation"""
    sources: List[str] = Field(
        default=["systemd-journal", "container-logs"],
        description="Sources to include in journal"
    )
    time_range: str = Field("24h", description="Time range (e.g., '24h', '7d')")
    include_metrics: bool = Field(True, description="Include system metrics")


class JournalResponse(BaseModel):
    """Response from journal generation"""
    content: str = Field(..., description="Generated journal entry (markdown)")
    output_path: Optional[str] = Field(None, description="Path where journal was saved")
    timestamp: str = Field(..., description="Journal timestamp")


class AutodocRequest(BaseModel):
    """Request for autodoc generation"""
    file_path: str = Field(..., description="File to document")
    style: str = Field("technical", description="Documentation style (technical|user-friendly)")
    include_examples: bool = Field(True, description="Include usage examples")


class AutodocResponse(BaseModel):
    """Response from autodoc generation"""
    documentation: str = Field(..., description="Generated documentation (markdown)")
    file_path: str = Field(..., description="Source file path")
    sections: List[str] = Field(..., description="Documentation sections generated")


class WorkflowInfo(BaseModel):
    """Information about a workflow"""
    name: str
    enabled: bool
    last_run: Optional[str]
    next_run: Optional[str]
    runs_count: int
    status: WorkflowStatus
    last_error: Optional[str]


class ModelInfo(BaseModel):
    """Information about an available model"""
    name: str
    status: str  # "available", "loading", "unavailable"
    size: Optional[str]


class StatusResponse(BaseModel):
    """Overall status response"""
    version: str = "1.0.0"
    workflows: Dict[str, WorkflowInfo]
    models: Dict[str, ModelInfo]
    api_uptime: str
    requests_processed: int
