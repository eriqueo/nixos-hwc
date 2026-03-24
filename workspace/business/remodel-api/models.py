"""
Pydantic models for API request/response validation
"""
from typing import Optional, List, Dict, Any
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field


# ============================================================================
# REQUEST MODELS
# ============================================================================

class ClientCreate(BaseModel):
    """Client information for project creation"""
    name: str = Field(..., min_length=1, max_length=255)
    email: Optional[EmailStr] = None
    phone: Optional[str] = Field(None, max_length=20)


class ProjectCreate(BaseModel):
    """Create a new project"""
    client: ClientCreate
    project_type: str = "bathroom"


class BathroomAnswers(BaseModel):
    """
    Complete set of answers from the bathroom wizard.
    Matches the question tree config keys.
    """
    # Step 1: Space Overview
    bathroom_type: str

    # Step 2: Vision
    preferred_styles: Optional[List[str]] = []
    ambience: Optional[str] = None

    # Step 3: Scope Goals
    goals: List[str]

    # Step 4: Space & Layout
    size_sqft_band: str
    layout_change_level: str
    plumbing_changes: str
    ceiling_height_band: Optional[str] = "standard"

    # Step 5: Systems & Upgrades
    electrical_scope: str
    ventilation_scope: str
    extras: Optional[List[str]] = []

    # Step 6: Finishes
    shower_type: Optional[str] = None
    tile_level: Optional[str] = None
    flooring_type: Optional[str] = None
    vanity_type: str
    countertop_type: str

    # Step 7: Budget & Timing
    budget_band: str
    timeline_readiness: str

    # Step 8: Optional Details
    free_text_notes: Optional[str] = None


class EstimateRequest(BaseModel):
    """Request body for /estimate endpoint"""
    answers: BathroomAnswers


# ============================================================================
# RESPONSE MODELS
# ============================================================================

class ProjectResponse(BaseModel):
    """Response after creating a project"""
    project_id: UUID
    client_id: UUID


class CostModule(BaseModel):
    """A single cost module (e.g., tub_to_shower)"""
    module_key: str
    label: str
    total_min: float
    total_max: float
    labor_min: Optional[float] = None
    labor_max: Optional[float] = None
    materials_min: Optional[float] = None
    materials_max: Optional[float] = None


class CostSummary(BaseModel):
    """Overall cost summary"""
    total_min: float
    total_max: float
    labor_min: float
    labor_max: float
    materials_min: float
    materials_max: float


class ProjectSummary(BaseModel):
    """Human-readable project summary"""
    scope_text: str
    complexity_band: str  # low, medium, high
    complexity_score: int


class EducationalContent(BaseModel):
    """Educational information for the client"""
    cost_drivers: List[str]
    questions_for_contractors: Optional[List[str]] = []


class AnalysisContent(BaseModel):
    """LLM-generated analysis (future)"""
    builder: Optional[str] = None
    designer: Optional[str] = None


class EstimateResult(BaseModel):
    """Complete estimate response"""
    project_id: UUID
    summary: ProjectSummary
    cost: CostSummary
    modules: List[CostModule]
    education: EducationalContent
    analysis: AnalysisContent


# ============================================================================
# INTERNAL DATA MODELS (Database rows)
# ============================================================================

class CostRule(BaseModel):
    """A cost rule from the database"""
    id: UUID
    engine: str
    module_key: str
    rule_key: str
    applies_when: Dict[str, Any]
    base_cost_min: float
    base_cost_max: float
    cost_per_sqft_min: float
    cost_per_sqft_max: float
    labor_fraction: float
    complexity_points: int
    notes: Optional[str]
    active: bool

    class Config:
        from_attributes = True


class RuleMatchResult(BaseModel):
    """Result of matching a single rule against answers"""
    rule: CostRule
    matched: bool
    labor_min: float
    labor_max: float
    materials_min: float
    materials_max: float
    total_min: float
    total_max: float


class ModuleResult(BaseModel):
    """Aggregated result for a module"""
    module_key: str
    label: str
    rules_matched: List[RuleMatchResult]
    total_min: float
    total_max: float
    labor_min: float
    labor_max: float
    materials_min: float
    materials_max: float
    complexity_points: int
