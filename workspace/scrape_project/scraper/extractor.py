"""Data extraction from pages using Playwright."""

from collections import Counter
from dataclasses import dataclass, field

from playwright.sync_api import Page, ElementHandle

from .exceptions import ExtractionError
from .logging_config import get_logger
from .models import Comment, Post, SiteConfig, ScraperDefinition


@dataclass
class ExtractionMetrics:
    """Track extraction success/failure rates."""

    successes: Counter = field(default_factory=Counter)
    failures: Counter = field(default_factory=Counter)

    def record_success(self, field_name: str) -> None:
        self.successes[field_name] += 1

    def record_failure(self, field_name: str, reason: str) -> None:
        self.failures[f"{field_name}_{reason}"] += 1

    def summary(self) -> dict:
        """Get summary of extraction metrics."""
        total_success = sum(self.successes.values())
        total_failure = sum(self.failures.values())
        total = total_success + total_failure
        return {
            "total_extractions": total,
            "success_rate": total_success / total if total > 0 else 0,
            "successes": dict(self.successes),
            "failures": dict(self.failures),
        }


def extract_field(
    element: ElementHandle,
    field_name: str,
    scraper_config: ScraperDefinition | dict,
    metrics: ExtractionMetrics,
) -> str:
    """
    Extract a single field from an element.

    Args:
        element: Playwright element handle
        field_name: Name of field being extracted
        scraper_config: Selector and type configuration
        metrics: Metrics tracker

    Returns:
        Extracted text or empty string
    """
    logger = get_logger()

    # Handle both ScraperDefinition and dict
    if isinstance(scraper_config, dict):
        selector = scraper_config.get("selector", "")
        field_type = scraper_config.get("type", "text")
    else:
        selector = scraper_config.selector
        field_type = scraper_config.type

    try:
        target = element.query_selector(selector)
        if not target:
            metrics.record_failure(field_name, "not_found")
            return ""

        if field_type == "text":
            value = target.inner_text().strip()
        elif field_type == "href":
            value = target.get_attribute("href") or ""
        else:
            logger.warning(f"Unknown scraper type: {field_type}")
            value = ""

        if value:
            metrics.record_success(field_name)
        else:
            metrics.record_failure(field_name, "empty")

        return value

    except Exception as e:
        logger.debug(f"Failed to extract {field_name}: {e}")
        metrics.record_failure(field_name, "error")
        return ""


def extract_comments(
    post_element: ElementHandle,
    site_config: SiteConfig,
    metrics: ExtractionMetrics,
) -> list[Comment]:
    """
    Extract comments from a post element.

    Args:
        post_element: Post element containing comments
        site_config: Site configuration with comment selectors
        metrics: Metrics tracker

    Returns:
        List of extracted comments
    """
    logger = get_logger()
    comments = []
    scrapers = site_config.scrapers

    # Check for comments container selector
    container_key = "comments_container_selector"
    if container_key not in scrapers:
        return comments

    container_selector = scrapers[container_key]
    if isinstance(container_selector, dict):
        container_selector = container_selector.get("selector", "")
    elif hasattr(container_selector, "selector"):
        container_selector = container_selector.selector

    if not container_selector:
        return comments

    try:
        comment_elements = post_element.query_selector_all(container_selector)

        for comment_el in comment_elements:
            try:
                # Get author
                author_config = scrapers.get("comment_author", {})
                if isinstance(author_config, dict):
                    author_selector = author_config.get("selector", "")
                else:
                    author_selector = author_config.selector if hasattr(author_config, "selector") else ""

                # Get text
                text_config = scrapers.get("comment_text", {})
                if isinstance(text_config, dict):
                    text_selector = text_config.get("selector", "")
                else:
                    text_selector = text_config.selector if hasattr(text_config, "selector") else ""

                author_el = comment_el.query_selector(author_selector) if author_selector else None
                text_el = comment_el.query_selector(text_selector) if text_selector else None

                if author_el and text_el:
                    author = author_el.inner_text().strip()
                    text = text_el.inner_text().strip()
                    if text:
                        comments.append(Comment(author=author, text=text))
                        metrics.record_success("comment")

            except Exception as e:
                logger.debug(f"Failed to extract comment: {e}")
                metrics.record_failure("comment", "error")
                continue

    except Exception as e:
        logger.debug(f"Failed to find comments container: {e}")

    return comments


def extract_post(
    post_element: ElementHandle,
    site_config: SiteConfig,
    page_title: str,
    metrics: ExtractionMetrics,
) -> Post | None:
    """
    Extract a single post from its element.

    Args:
        post_element: Post container element
        site_config: Site configuration
        page_title: Page title for group name
        metrics: Metrics tracker

    Returns:
        Extracted Post or None if invalid
    """
    logger = get_logger()
    scrapers = site_config.scrapers

    # Extract main fields
    data = {
        "source": site_config.name,
        "group": page_title,
    }

    for key, scraper_config in scrapers.items():
        # Skip comment-related keys
        if "comment" in key.lower() or "container" in key.lower():
            continue

        value = extract_field(post_element, key, scraper_config, metrics)
        # Map to Post field names (capitalize first letter)
        field_name = key.lower()
        data[field_name] = value

    # Extract comments
    comments = extract_comments(post_element, site_config, metrics)
    data["comments"] = comments

    # Validate - must have text
    if not data.get("text"):
        metrics.record_failure("post", "no_text")
        return None

    try:
        post = Post(**data)
        metrics.record_success("post")
        return post
    except Exception as e:
        logger.debug(f"Failed to create Post model: {e}")
        metrics.record_failure("post", "validation_error")
        return None


def extract_all_posts(
    page: Page,
    site_config: SiteConfig,
    metrics: ExtractionMetrics | None = None,
) -> list[Post]:
    """
    Extract all posts from a page.

    Args:
        page: Playwright page instance
        site_config: Site configuration
        metrics: Optional metrics tracker

    Returns:
        List of extracted posts
    """
    logger = get_logger()

    if metrics is None:
        metrics = ExtractionMetrics()

    posts = []
    page_title = page.title()

    try:
        post_elements = page.query_selector_all(site_config.post_container_selector)
        logger.debug(f"Found {len(post_elements)} post containers")

        for post_el in post_elements:
            post = extract_post(post_el, site_config, page_title, metrics)
            if post:
                posts.append(post)

    except Exception as e:
        logger.error(f"Failed to extract posts: {e}")
        raise ExtractionError(f"Post extraction failed: {e}") from e

    logger.info(f"Extracted {len(posts)} valid posts from {len(post_elements)} containers")
    return posts
