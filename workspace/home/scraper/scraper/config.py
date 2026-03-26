"""Configuration loading and validation."""

import json
import os
import stat
from pathlib import Path

from pydantic import ValidationError

from .exceptions import ConfigurationError
from .logging_config import get_logger
from .models import SiteConfig, SitesConfig


def load_config(config_path: Path) -> SitesConfig:
    """
    Load and validate sites.json configuration.

    Args:
        config_path: Path to configuration file

    Returns:
        Validated SitesConfig

    Raises:
        ConfigurationError: If config is missing or invalid
    """
    logger = get_logger()

    if not config_path.exists():
        raise ConfigurationError(
            f"Configuration file not found: {config_path}\n"
            f"Please create sites.json in the script directory."
        )

    try:
        data = json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise ConfigurationError(f"Invalid JSON in {config_path}: {e}") from e

    try:
        config = SitesConfig(**data)
        logger.debug(f"Loaded config with {len(config.sites)} sites")
        return config
    except ValidationError as e:
        raise ConfigurationError(f"Configuration validation failed:\n{e}") from e


def get_site_config(url: str, config: SitesConfig) -> SiteConfig | None:
    """
    Find matching site configuration for a URL.

    Args:
        url: URL to match
        config: Sites configuration

    Returns:
        Matching SiteConfig or None
    """
    logger = get_logger()

    for site in config.sites:
        if site.url_pattern in url:
            logger.info(f"Matched site configuration: {site.name}")
            return site

    logger.warning(f"No configuration found for URL: {url}")
    return None


def get_auth_file_path(site_name: str) -> Path:
    """
    Get secure path for authentication storage.

    Uses XDG_DATA_HOME on Unix, AppData on Windows.

    Args:
        site_name: Name of the site

    Returns:
        Path to auth file
    """
    if os.name == "nt":  # Windows
        data_dir = Path(os.getenv("APPDATA", Path.home() / "AppData/Roaming"))
    else:  # Unix-like
        data_dir = Path(os.getenv("XDG_DATA_HOME", Path.home() / ".local/share"))

    auth_dir = data_dir / "scraper" / "auth"
    auth_dir.mkdir(parents=True, exist_ok=True)

    # Set restrictive permissions (Unix only)
    if os.name != "nt":
        try:
            auth_dir.chmod(stat.S_IRWXU)  # 0700 - owner only
        except OSError:
            pass  # May fail on some filesystems

    safe_name = site_name.lower().replace(" ", "_")
    auth_file = auth_dir / f"{safe_name}.json"

    # Set file permissions if it exists
    if auth_file.exists() and os.name != "nt":
        try:
            auth_file.chmod(stat.S_IRUSR | stat.S_IWUSR)  # 0600
        except OSError:
            pass

    return auth_file


def get_env_config() -> dict:
    """
    Get configuration from environment variables.

    Supports:
        SCRAPER_LOG_LEVEL: DEBUG, INFO, WARNING, ERROR
        SCRAPER_HEADLESS: true/false
        SCRAPER_SCROLL_DELAY: float seconds
        SCRAPER_TIMEOUT: int milliseconds
        SCRAPER_CONFIG_FILE: path to sites.json

    Returns:
        Dict of environment-based config overrides
    """
    config = {}

    if level := os.getenv("SCRAPER_LOG_LEVEL"):
        config["log_level"] = level.upper()

    if headless := os.getenv("SCRAPER_HEADLESS"):
        config["headless"] = headless.lower() in ("true", "1", "yes")

    if delay := os.getenv("SCRAPER_SCROLL_DELAY"):
        try:
            config["scroll_delay"] = float(delay)
        except ValueError:
            pass

    if timeout := os.getenv("SCRAPER_TIMEOUT"):
        try:
            config["timeout"] = int(timeout)
        except ValueError:
            pass

    if config_file := os.getenv("SCRAPER_CONFIG_FILE"):
        config["config_file"] = Path(config_file)

    return config
