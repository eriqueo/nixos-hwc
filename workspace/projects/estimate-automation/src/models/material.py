"""Material model for storing material pricing and details."""

from datetime import datetime
from sqlalchemy import Column, String, Float, Boolean, Integer, ForeignKey, DateTime, Text
from sqlalchemy.orm import relationship

from src.config.database import Base
from .base import BaseModel


class Material(Base, BaseModel):
    """Material with pricing and specifications."""

    __tablename__ = "materials"

    # Identification
    code = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)

    # Categorization
    category = Column(String(100), nullable=False, index=True)
    subcategory = Column(String(100), nullable=True)

    # Pricing
    unit = Column(String(50), nullable=False)  # each, sq_ft, linear_ft, lb, gallon, etc.
    base_cost = Column(Float, nullable=False)
    current_price = Column(Float, nullable=False)
    last_price_update = Column(DateTime, default=datetime.utcnow)

    # Supplier
    supplier_id = Column(Integer, ForeignKey("suppliers.id"), nullable=True)
    supplier = relationship("Supplier", back_populates="materials")

    # Specifications
    waste_factor = Column(Float, default=0.10)  # 10% waste by default
    taxable = Column(Boolean, default=True)
    active = Column(Boolean, default=True, index=True)
    notes = Column(Text, nullable=True)

    # Relationships
    assembly_materials = relationship("AssemblyMaterial", back_populates="material")


class Supplier(Base, BaseModel):
    """Supplier/vendor information."""

    __tablename__ = "suppliers"

    name = Column(String(200), nullable=False)
    contact_name = Column(String(200), nullable=True)
    email = Column(String(200), nullable=True)
    phone = Column(String(50), nullable=True)
    address = Column(Text, nullable=True)
    payment_terms = Column(String(100), nullable=True)
    discount_percent = Column(Float, default=0.0)
    active = Column(Boolean, default=True)
    notes = Column(Text, nullable=True)

    # Relationships
    materials = relationship("Material", back_populates="supplier")
