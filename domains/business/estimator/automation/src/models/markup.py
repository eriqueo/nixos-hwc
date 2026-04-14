"""Markup rules model for pricing calculations."""

from sqlalchemy import Column, String, Float, Boolean, Text

from src.config.database import Base
from .base import BaseModel


class MarkupRule(Base, BaseModel):
    """Markup rules for pricing calculations."""

    __tablename__ = "markup_rules"

    # Identification
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)

    # Job type (null = applies to all job types)
    job_type = Column(String(100), nullable=True, index=True)

    # Markup percentages
    material_markup_percent = Column(Float, default=25.0)
    labor_markup_percent = Column(Float, default=15.0)
    overhead_percent = Column(Float, default=10.0)
    profit_percent = Column(Float, default=15.0)

    # Minimum margins
    min_margin_dollars = Column(Float, default=0.0)
    min_job_total = Column(Float, default=0.0)

    # Priority (higher = applied first, allows for overrides)
    priority = Column(Integer, default=0)

    # Status
    active = Column(Boolean, default=True, index=True)
    is_default = Column(Boolean, default=False)

    notes = Column(Text, nullable=True)
