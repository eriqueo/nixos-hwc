"""Pydantic schemas for Material model validation."""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, ConfigDict


class MaterialBase(BaseModel):
    """Base material schema."""

    code: str = Field(..., max_length=50, description="Unique material code")
    name: str = Field(..., max_length=200, description="Material name")
    description: Optional[str] = Field(None, description="Detailed description")
    category: str = Field(..., max_length=100, description="Material category")
    subcategory: Optional[str] = Field(None, max_length=100)
    unit: str = Field(..., max_length=50, description="Unit of measure")
    base_cost: float = Field(..., gt=0, description="Base cost per unit")
    current_price: float = Field(..., gt=0, description="Current price per unit")
    supplier_id: Optional[int] = None
    waste_factor: float = Field(0.10, ge=0, le=1, description="Waste factor (0-1)")
    taxable: bool = True
    active: bool = True
    notes: Optional[str] = None


class MaterialCreate(MaterialBase):
    """Schema for creating a material."""

    pass


class MaterialUpdate(BaseModel):
    """Schema for updating a material."""

    name: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    subcategory: Optional[str] = Field(None, max_length=100)
    unit: Optional[str] = Field(None, max_length=50)
    base_cost: Optional[float] = Field(None, gt=0)
    current_price: Optional[float] = Field(None, gt=0)
    supplier_id: Optional[int] = None
    waste_factor: Optional[float] = Field(None, ge=0, le=1)
    taxable: Optional[bool] = None
    active: Optional[bool] = None
    notes: Optional[str] = None


class Material(MaterialBase):
    """Schema for material response."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    last_price_update: datetime
    created_at: datetime
    updated_at: datetime


class SupplierBase(BaseModel):
    """Base supplier schema."""

    name: str = Field(..., max_length=200)
    contact_name: Optional[str] = Field(None, max_length=200)
    email: Optional[str] = Field(None, max_length=200)
    phone: Optional[str] = Field(None, max_length=50)
    address: Optional[str] = None
    payment_terms: Optional[str] = Field(None, max_length=100)
    discount_percent: float = Field(0.0, ge=0, le=100)
    active: bool = True
    notes: Optional[str] = None


class SupplierCreate(SupplierBase):
    """Schema for creating a supplier."""

    pass


class Supplier(SupplierBase):
    """Schema for supplier response."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime
