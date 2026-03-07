"""Data models for the scraper."""

from __future__ import annotations

import hashlib
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


class Comment(BaseModel):
    """A comment on a post."""

    author: str
    text: str

    @field_validator("text")
    @classmethod
    def text_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Comment text cannot be empty")
        return v.strip()

    @field_validator("author")
    @classmethod
    def author_not_empty(cls, v: str) -> str:
        return v.strip() if v else "Unknown"


class Post(BaseModel):
    """A scraped post with metadata."""

    source: str = Field(description="Name of the site/platform")
    group: str = Field(description="Group/subreddit/page name")
    author: str = Field(default="Unknown")
    date: str = Field(default="")
    text: str = Field(min_length=1)
    reactions: str = Field(default="")
    comments: list[Comment] = Field(default_factory=list)
    url: str = Field(default="")
    scraped_at: datetime = Field(default_factory=datetime.now)

    @property
    def comments_count(self) -> int:
        return len(self.comments)

    @property
    def content_hash(self) -> str:
        """Generate hash for deduplication."""
        content = f"{self.author}::{self.text}"
        return hashlib.sha256(content.encode()).hexdigest()[:16]

    @field_validator("author")
    @classmethod
    def clean_author(cls, v: str) -> str:
        return v.strip() if v else "Unknown"

    @field_validator("text")
    @classmethod
    def clean_text(cls, v: str) -> str:
        return v.strip()


class ScraperDefinition(BaseModel):
    """Selector configuration for extracting a field."""

    selector: str = Field(min_length=1)
    type: Literal["text", "href"] = "text"


class SiteScraperConfig(BaseModel):
    """Per-site scraper configuration overrides."""

    scroll_delay: float | None = None
    timeout: int | None = None
    rate_limit_rpm: int = Field(default=20, ge=1, le=60)
    max_scrolls: int | None = None


class SiteConfig(BaseModel):
    """Configuration for a single site."""

    name: str
    url_pattern: str
    login_required: bool = False
    post_container_selector: str = Field(min_length=1)
    scrapers: dict[str, ScraperDefinition | str] = Field(default_factory=dict)
    # Attribute-based extraction (e.g., Reddit's shreddit-post)
    attribute_map: dict[str, str] = Field(default_factory=dict)
    scraper_config: SiteScraperConfig = Field(default_factory=SiteScraperConfig)
    user_agent: str | None = None

    @field_validator("scrapers", mode="before")
    @classmethod
    def normalize_scrapers(cls, v: dict) -> dict:
        """Handle both simple string selectors and full ScraperDefinition."""
        normalized = {}
        for key, value in v.items():
            if isinstance(value, str):
                # Simple string selector - treat as text type
                normalized[key] = {"selector": value, "type": "text"}
            elif isinstance(value, dict):
                normalized[key] = value
            else:
                normalized[key] = value
        return normalized


class GlobalConfig(BaseModel):
    """Global scraper settings."""

    default_scrolls: int = Field(default=10, ge=1, le=100)
    default_scroll_delay: float = Field(default=3.0, ge=0.5, le=30.0)
    default_timeout: int = Field(default=15000, ge=5000, le=60000)
    headless: bool = False
    user_agent: str | None = None
    viewport_width: int = Field(default=1920, ge=800)
    viewport_height: int = Field(default=1080, ge=600)


class SitesConfig(BaseModel):
    """Root configuration containing all sites."""

    sites: list[SiteConfig]
    global_config: GlobalConfig = Field(default_factory=GlobalConfig)
