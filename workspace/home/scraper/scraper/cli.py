"""Command-line interface for the scraper."""

import argparse
from pathlib import Path

from .config import get_env_config
from .storage import STORAGE_BACKENDS


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        description="Configurable Social Media Scraper",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Login to Facebook (one-time setup)
  scraper --url "https://www.facebook.com" --login

  # Scrape a Facebook group
  scraper --url "https://www.facebook.com/groups/your_group_id"

  # Scrape with custom settings
  scraper --url "https://reddit.com/r/python" --scrolls 20 --format jsonl

  # Run headless with JSON output
  scraper --url "..." --headless --format json --output data.json

Environment Variables:
  SCRAPER_LOG_LEVEL     Log level (DEBUG, INFO, WARNING, ERROR)
  SCRAPER_HEADLESS      Run browser headless (true/false)
  SCRAPER_SCROLL_DELAY  Delay between scrolls in seconds
  SCRAPER_TIMEOUT       Page timeout in milliseconds
  SCRAPER_CONFIG_FILE   Path to sites.json configuration
        """,
    )

    # Required arguments
    parser.add_argument(
        "--url",
        required=True,
        help="URL of the page to scrape",
    )

    # Mode arguments
    parser.add_argument(
        "--login",
        action="store_true",
        help="Perform manual login to save auth state",
    )

    # Scraping options
    parser.add_argument(
        "--scrolls",
        type=int,
        default=None,
        help="Number of times to scroll (default: 10)",
    )
    parser.add_argument(
        "--scroll-delay",
        type=float,
        default=None,
        help="Seconds to wait between scrolls (default: 3.0)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=None,
        help="Page timeout in milliseconds (default: 15000)",
    )

    # Output options
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Output file path",
    )
    parser.add_argument(
        "--format", "-f",
        choices=list(STORAGE_BACKENDS.keys()),
        default="csv",
        help="Output format (default: csv)",
    )

    # Browser options
    parser.add_argument(
        "--headless",
        action="store_true",
        default=None,
        help="Run browser in headless mode",
    )

    # Logging options
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default=None,
        help="Log level (default: INFO)",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        default=None,
        help="Path to log file",
    )
    parser.add_argument(
        "--json-logs",
        action="store_true",
        help="Use JSON format for logs",
    )

    # Config options
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help="Path to sites.json configuration",
    )

    return parser


def merge_config(args: argparse.Namespace) -> argparse.Namespace:
    """
    Merge CLI args with environment variables.

    Priority: CLI args > Environment > Defaults
    """
    env_config = get_env_config()

    # Apply env defaults where CLI not specified
    if args.log_level is None:
        args.log_level = env_config.get("log_level", "INFO")

    if args.headless is None:
        args.headless = env_config.get("headless", False)

    if args.scroll_delay is None:
        args.scroll_delay = env_config.get("scroll_delay", 3.0)

    if args.timeout is None:
        args.timeout = env_config.get("timeout", 15000)

    if args.config is None:
        args.config = env_config.get("config_file")

    if args.scrolls is None:
        args.scrolls = 10

    return args


def parse_args() -> argparse.Namespace:
    """Parse and validate command-line arguments."""
    parser = create_parser()
    args = parser.parse_args()
    return merge_config(args)
