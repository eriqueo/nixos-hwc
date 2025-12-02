"""Pydantic schemas for Labor model validation."""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, ConfigDict


class LaborCategoryBase(BaseModel):
    """Base labor category schema."""

    code: str = Field(..., max_length=50, description="Unique labor code")
    name: str = Field(..., max_length=200, description="Labor category name")
    description: Optional[str] = Field(None, description="Detailed description")
    trade: str = Field(..., max_length=100, description="Trade type")
    skill_level: Optional[str] = Field(None, max_length=50, description="Skill level")
    hourly_rate: float = Field(..., gt=0, description="Base hourly rate")
    burden_rate: float = Field(0.25, ge=0, le=2, description="Burden rate for benefits, taxes")
    overtime_multiplier: float = Field(1.5, gt=1, description="Overtime rate multiplier")
    active: bool = True
    notes: Optional[str] = None


class LaborCategoryCreate(LaborCategoryBase):
    """Schema for creating a labor category."""

    pass


class LaborCategoryUpdate(BaseModel):
    """Schema for updating a labor category."""

    name: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    trade: Optional[str] = Field(None, max_length=100)
    skill_level: Optional[str] = Field(None, max_length=50)
    hourly_rate: Optional[float] = Field(None, gt=0)
    burden_rate: Optional[float] = Field(None, ge=0, le=2)
    overtime_multiplier: Optional[float] = Field(None, gt=1)
    active: Optional[bool] = None
    notes: Optional[str] = None


class LaborCategory(LaborCategoryBase):
    """Schema for labor category response."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    effective_date: datetime
    created_at: datetime
    updated_at: datetime
    total_hourly_cost: float
