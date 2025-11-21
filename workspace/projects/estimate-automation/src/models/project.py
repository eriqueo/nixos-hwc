"""Project and line item models for storing estimates."""

from sqlalchemy import Column, String, Float, Integer, ForeignKey, Text, JSON, Enum as SQLEnum
from sqlalchemy.orm import relationship
import enum

from src.config.database import Base
from .base import BaseModel


class ProjectStatus(enum.Enum):
    """Project status enum."""

    DRAFT = "draft"
    SENT = "sent"
    APPROVED = "approved"
    REJECTED = "rejected"
    COMPLETED = "completed"


class Project(Base, BaseModel):
    """Project/estimate."""

    __tablename__ = "projects"

    # Identification
    project_number = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(200), nullable=False)

    # Client information
    client_name = Column(String(200), nullable=False)
    client_email = Column(String(200), nullable=True)
    client_phone = Column(String(50), nullable=True)
    client_address = Column(Text, nullable=True)

    # Project details
    job_type = Column(String(100), nullable=False, index=True)
    description = Column(Text, nullable=True)

    # Job parameters stored as JSON (dimensions, counts, options, etc.)
    parameters = Column(JSON, nullable=True)

    # Financial summary
    subtotal_materials = Column(Float, default=0.0)
    subtotal_labor = Column(Float, default=0.0)
    subtotal = Column(Float, default=0.0)
    material_markup_percent = Column(Float, default=0.0)
    labor_markup_percent = Column(Float, default=0.0)
    overhead_percent = Column(Float, default=0.0)
    profit_percent = Column(Float, default=0.0)
    tax_amount = Column(Float, default=0.0)
    total_price = Column(Float, default=0.0)

    # Status
    status = Column(SQLEnum(ProjectStatus), default=ProjectStatus.DRAFT, nullable=False)
    notes = Column(Text, nullable=True)

    # Relationships
    line_items = relationship("ProjectLineItem", back_populates="project", cascade="all, delete-orphan")


class ItemType(enum.Enum):
    """Line item type enum."""

    MATERIAL = "material"
    LABOR = "labor"
    ASSEMBLY = "assembly"
    MISC = "misc"
    SUBTOTAL = "subtotal"
    MARKUP = "markup"
    TAX = "tax"


class ProjectLineItem(Base, BaseModel):
    """Individual line item in a project estimate."""

    __tablename__ = "project_line_items"

    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False, index=True)
    line_number = Column(Integer, nullable=False)

    # Item details
    item_type = Column(SQLEnum(ItemType), nullable=False)
    code = Column(String(50), nullable=True)
    description = Column(String(500), nullable=False)

    # Quantity and pricing
    quantity = Column(Float, default=1.0)
    unit = Column(String(50), nullable=True)
    unit_cost = Column(Float, default=0.0)
    total_cost = Column(Float, default=0.0)

    # Categorization
    category = Column(String(100), nullable=True)
    subcategory = Column(String(100), nullable=True)

    # Optional reference to source material/labor/assembly
    material_id = Column(Integer, ForeignKey("materials.id"), nullable=True)
    labor_category_id = Column(Integer, ForeignKey("labor_categories.id"), nullable=True)
    assembly_id = Column(Integer, ForeignKey("assemblies.id"), nullable=True)

    notes = Column(Text, nullable=True)

    # Relationships
    project = relationship("Project", back_populates="line_items")
