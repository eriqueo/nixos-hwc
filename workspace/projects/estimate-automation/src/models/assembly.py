"""Assembly models for pre-configured bundles of materials and labor."""

from sqlalchemy import Column, String, Float, Boolean, Integer, ForeignKey, Text
from sqlalchemy.orm import relationship

from src.config.database import Base
from .base import BaseModel


class Assembly(Base, BaseModel):
    """Assembly - a pre-configured bundle of materials and labor."""

    __tablename__ = "assemblies"

    # Identification
    code = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)

    # Categorization
    job_type = Column(String(100), nullable=False, index=True)  # bathroom, deck, siding, etc.
    category = Column(String(100), nullable=True)
    subcategory = Column(String(100), nullable=True)

    # Unit of measure for the assembly
    unit = Column(String(50), nullable=False)  # each, sq_ft, linear_ft, etc.

    # Status
    active = Column(Boolean, default=True, index=True)
    notes = Column(Text, nullable=True)

    # Relationships
    materials = relationship("AssemblyMaterial", back_populates="assembly", cascade="all, delete-orphan")
    labor = relationship("AssemblyLabor", back_populates="assembly", cascade="all, delete-orphan")


class AssemblyMaterial(Base, BaseModel):
    """Material component of an assembly."""

    __tablename__ = "assembly_materials"

    assembly_id = Column(Integer, ForeignKey("assemblies.id"), nullable=False, index=True)
    material_id = Column(Integer, ForeignKey("materials.id"), nullable=False, index=True)

    # Quantity per unit of assembly
    quantity_per_unit = Column(Float, nullable=False)

    # Optional formula for dynamic calculation (stored as string, evaluated at runtime)
    quantity_formula = Column(String(500), nullable=True)

    notes = Column(Text, nullable=True)

    # Relationships
    assembly = relationship("Assembly", back_populates="materials")
    material = relationship("Material", back_populates="assembly_materials")


class AssemblyLabor(Base, BaseModel):
    """Labor component of an assembly."""

    __tablename__ = "assembly_labor"

    assembly_id = Column(Integer, ForeignKey("assemblies.id"), nullable=False, index=True)
    labor_category_id = Column(Integer, ForeignKey("labor_categories.id"), nullable=False, index=True)

    # Hours per unit of assembly
    hours_per_unit = Column(Float, nullable=False)

    # Optional formula for dynamic calculation
    hours_formula = Column(String(500), nullable=True)

    notes = Column(Text, nullable=True)

    # Relationships
    assembly = relationship("Assembly", back_populates="labor")
    labor_category = relationship("LaborCategory", back_populates="assembly_labor")
