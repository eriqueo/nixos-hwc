"""Application settings and configuration."""

from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Database
    database_url: str = "sqlite:///./estimate_automation.db"

    # Application
    app_name: str = "Estimate Automation"
    debug: bool = False
    log_level: str = "INFO"

    # Business defaults
    default_material_markup: float = 25.0
    default_labor_markup: float = 15.0
    default_overhead_percent: float = 10.0
    default_profit_percent: float = 15.0

    # Export settings
    export_dir: str = "./exports"
    jobtread_date_format: str = "%m/%d/%Y"

    # Regional
    tax_rate: float = 0.0
    currency_symbol: str = "$"


# Global settings instance
settings = Settings()
