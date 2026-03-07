#!/usr/bin/env python3
"""
Configurable Multi-Platform Social Media Scraper

A Playwright-based scraper with support for multiple sites,
rate limiting, deduplication, and multiple output formats.

Usage:
  # Login (one-time setup per site):
  scraper --url "https://www.facebook.com" --login

  # Scrape a page:
  scraper --url "https://www.facebook.com/groups/your_group_id"

  # With options:
  scraper --url "..." --scrolls 20 --format jsonl --output data.jsonl

For more options: scraper --help
"""

from pathlib import Path
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError

from scraper import (
    setup_logging,
    get_logger,
    load_config,
    get_site_config,
    get_auth_file_path,
    extract_all_posts,
    ExtractionMetrics,
    PostDeduplicator,
    get_storage_backend,
    AdaptiveRateLimiter,
    RateLimitConfig,
    ConfigurationError,
)
from scraper.cli import parse_args


# Default config file location (next to this script)
SCRIPT_DIR = Path(__file__).parent.resolve()
DEFAULT_CONFIG = SCRIPT_DIR / "sites.json"


def run_login_flow(page, site_name: str, auth_file: Path) -> None:
    """
    Handle manual login flow.

    Opens browser for user to login manually, then saves auth state.
    """
    logger = get_logger()

    logger.info("=" * 50)
    logger.info("MANUAL LOGIN REQUIRED")
    logger.info("=" * 50)
    logger.info(f"Please log in to {site_name} in the browser window.")
    logger.info("Once logged in, press Ctrl+C to save your session.")
    logger.info("=" * 50)

    try:
        # Wait up to 1 hour for user to login
        page.wait_for_timeout(3600 * 1000)
    except KeyboardInterrupt:
        logger.info("\nSaving authentication state...")
        page.context.storage_state(path=str(auth_file))
        logger.info(f"Auth saved to: {auth_file}")


def run_scrape(
    page,
    site_config,
    scrolls: int,
    scroll_delay: float,
    output_path: Path,
    output_format: str,
) -> None:
    """
    Run the main scraping loop.

    Args:
        page: Playwright page instance
        site_config: Site configuration
        scrolls: Number of scroll iterations
        scroll_delay: Delay between scrolls
        output_path: Output file path
        output_format: Output format (csv, json, jsonl)
    """
    logger = get_logger()
    metrics = ExtractionMetrics()
    deduplicator = PostDeduplicator()

    # Set up rate limiter
    rate_limit_rpm = site_config.scraper_config.rate_limit_rpm
    limiter = AdaptiveRateLimiter(
        RateLimitConfig(
            min_delay=scroll_delay,
            requests_per_minute=rate_limit_rpm,
        )
    )

    logger.info(f"Starting scrape: {scrolls} scrolls, {scroll_delay}s delay")

    # Open storage for streaming writes
    storage = get_storage_backend(output_format, output_path)

    with storage:
        for i in range(scrolls):
            logger.info(f"Scroll {i + 1}/{scrolls}")

            # Wait according to rate limiter
            if i > 0:  # Don't wait before first extraction
                limiter.wait()

            try:
                # Extract posts from current page state
                posts = extract_all_posts(page, site_config, metrics)
                limiter.record_success()

                # Deduplicate and write new posts
                new_count = 0
                for post in posts:
                    if deduplicator.add_or_update(post):
                        storage.append(post)
                        new_count += 1

                logger.info(
                    f"Found {new_count} new posts "
                    f"(total unique: {len(deduplicator)})"
                )

                # Scroll down for more content
                page.mouse.wheel(0, 15000)

            except PlaywrightTimeoutError:
                logger.warning("Timeout during extraction, continuing...")
                limiter.record_error()
            except Exception as e:
                logger.error(f"Extraction error: {e}")
                limiter.record_error()

    # Log final metrics
    total_posts = len(deduplicator)
    if total_posts > 0:
        logger.info(f"Scrape complete: {total_posts} posts saved to {output_path}")
        logger.debug(f"Extraction metrics: {metrics.summary()}")
    else:
        logger.warning("No posts were scraped.")


def main() -> int:
    """Main entry point."""
    args = parse_args()

    # Set up logging
    setup_logging(
        level=args.log_level,
        log_file=args.log_file,
        json_format=args.json_logs,
    )
    logger = get_logger()

    # Load configuration
    config_path = args.config or DEFAULT_CONFIG
    try:
        config = load_config(config_path)
    except ConfigurationError as e:
        logger.error(str(e))
        return 1

    # Find site config for URL
    site_config = get_site_config(args.url, config)
    if not site_config:
        logger.error(f"No configuration found for URL: {args.url}")
        logger.error(f"Configured sites: {[s.name for s in config.sites]}")
        return 1

    # Determine auth file location
    auth_file = get_auth_file_path(site_config.name)

    # Merge config values (CLI > site config > global config)
    scroll_delay = (
        args.scroll_delay
        or site_config.scraper_config.scroll_delay
        or config.global_config.default_scroll_delay
    )
    timeout = (
        args.timeout
        or site_config.scraper_config.timeout
        or config.global_config.default_timeout
    )
    headless = args.headless if args.headless is not None else config.global_config.headless

    # Determine output path
    if args.output:
        output_path = args.output
    else:
        safe_name = site_config.name.lower().replace(" ", "_")
        output_path = Path(f"{safe_name}_data.{args.format}")

    logger.info(f"Scraping: {args.url}")
    logger.info(f"Site: {site_config.name}")
    logger.debug(f"Auth file: {auth_file}")
    logger.debug(f"Headless: {headless}, Timeout: {timeout}ms")

    # Launch browser
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=headless)

            # Set up context with auth and user agent
            context_args = {}
            if auth_file.exists() and not args.login:
                logger.info("Using saved authentication")
                context_args["storage_state"] = str(auth_file)
            elif site_config.login_required and not args.login:
                logger.warning(
                    f"Site requires login but no auth found. "
                    f"Run with --login first."
                )

            # Set user agent (required for sites like Reddit)
            user_agent = (
                site_config.user_agent
                or config.global_config.user_agent
                or "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            )
            context_args["user_agent"] = user_agent

            context = browser.new_context(**context_args)
            page = context.new_page()
            page.set_default_timeout(timeout)

            # Navigate to URL
            logger.info(f"Navigating to: {args.url}")
            try:
                page.goto(args.url, wait_until="domcontentloaded")
            except PlaywrightTimeoutError:
                logger.warning("Page load timeout, attempting to continue...")

            # Run appropriate flow
            if args.login:
                run_login_flow(page, site_config.name, auth_file)
            else:
                run_scrape(
                    page=page,
                    site_config=site_config,
                    scrolls=args.scrolls,
                    scroll_delay=scroll_delay,
                    output_path=output_path,
                    output_format=args.format,
                )

            browser.close()

    except KeyboardInterrupt:
        logger.info("\nScrape interrupted by user")
        return 130
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
