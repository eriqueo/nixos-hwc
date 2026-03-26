"""Base model with common fields for all models."""

from datetime import datetime
from sqlalchemy import Column, Integer, DateTime
from sqlalchemy.ext.declarative import declared_attr


class TimestampMixin:
    """Mixin to add created_at and updated_at timestamps."""

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class BaseModel(TimestampMixin):
    """Base model with id and timestamps."""

    @declared_attr
    def __tablename__(cls) -> str:  # type: ignore
        """Auto-generate table name from class name."""
        return cls.__name__.lower() + "s"

    id = Column(Integer, primary_key=True, index=True)
