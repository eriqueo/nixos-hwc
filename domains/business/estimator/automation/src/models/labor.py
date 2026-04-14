"""Labor category model for storing labor rates."""

from datetime import datetime
from sqlalchemy import Column, String, Float, Boolean, DateTime, Text
from sqlalchemy.orm import relationship

from src.config.database import Base
from .base import BaseModel


class LaborCategory(Base, BaseModel):
    """Labor category with rates and specifications."""

    __tablename__ = "labor_categories"

    # Identification
    code = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)

    # Categorization
    trade = Column(String(100), nullable=False, index=True)  # carpentry, plumbing, electrical, etc.
    skill_level = Column(String(50), nullable=True)  # apprentice, journeyman, master

    # Pricing
    hourly_rate = Column(Float, nullable=False)
    burden_rate = Column(Float, default=0.25)  # 25% for taxes, insurance, benefits
    overtime_multiplier = Column(Float, default=1.5)

    # Effective date for rate changes
    effective_date = Column(DateTime, default=datetime.utcnow)

    # Status
    active = Column(Boolean, default=True, index=True)
    notes = Column(Text, nullable=True)

    # Relationships
    assembly_labor = relationship("AssemblyLabor", back_populates="labor_category")

    @property
    def total_hourly_cost(self) -> float:
        """Calculate total hourly cost including burden."""
        return self.hourly_rate * (1 + self.burden_rate)
