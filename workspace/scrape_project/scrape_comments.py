#!/usr/bin/env python3
"""
Reddit Comment Scraper - Pass 2

Takes post IDs or a JSONL file from pass 1 and scrapes all comments.
Designed to work with n8n pipeline for market research.

Usage:
  # From post IDs directly
  scrape_comments --ids t3_abc123 t3_def456 --output comments.jsonl

  # From JSONL file (uses post_id field)
  scrape_comments --input filtered_posts.jsonl --output comments.jsonl

  # From stdin (pipe from n8n or jq)
  cat post_ids.txt | scrape_comments --output comments.jsonl
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError
from pydantic import BaseModel, Field

from scraper.logging_config import setup_logging, get_logger
from scraper.rate_limiter import AdaptiveRateLimiter, RateLimitConfig


class CommentData(BaseModel):
    """A scraped comment with metadata."""

    post_id: str
    post_title: str = ""
    post_url: str = ""
    comment_id: str = ""
    author: str = "Unknown"
    text: str
    score: str = ""
    depth: int = 0  # 0 = top-level, 1+ = reply depth
    parent_id: str = ""
    scraped_at: datetime = Field(default_factory=datetime.now)


USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"


def extract_comments_from_page(page, post_id: str, post_url: str) -> list[CommentData]:
    """Extract all comments from a Reddit post page."""
    logger = get_logger()
    comments = []

    # Get post title
    post_title = ""
    title_el = page.query_selector('shreddit-post')
    if title_el:
        post_title = title_el.get_attribute('post-title') or ""

    # Find all comment elements
    # Reddit uses shreddit-comment for comments
    comment_elements = page.query_selector_all('shreddit-comment')
    logger.debug(f"Found {len(comment_elements)} comment elements")

    for el in comment_elements:
        try:
            # Extract from attributes
            author = el.get_attribute('author') or "Unknown"
            comment_id = el.get_attribute('thingid') or el.get_attribute('id') or ""
            score = el.get_attribute('score') or ""
            depth = int(el.get_attribute('depth') or 0)
            parent_id = el.get_attribute('parentid') or ""

            # Get comment text from nested element
            text_el = el.query_selector('div[slot="comment"] p, div[id$="-post-rtjson-content"]')
            text = text_el.inner_text().strip() if text_el else ""

            if not text:
                # Try alternative selector
                text_el = el.query_selector('div.md')
                text = text_el.inner_text().strip() if text_el else ""

            if text:
                comments.append(CommentData(
                    post_id=post_id,
                    post_title=post_title,
                    post_url=post_url,
                    comment_id=comment_id,
                    author=author,
                    text=text,
                    score=score,
                    depth=depth,
                    parent_id=parent_id,
                ))
        except Exception as e:
            logger.debug(f"Failed to extract comment: {e}")
            continue

    return comments


def scrape_post_comments(
    context,
    post_id: str,
    subreddit: str = "",
    limiter: AdaptiveRateLimiter | None = None,
) -> list[CommentData]:
    """Scrape comments from a single post."""
    logger = get_logger()

    # Build URL
    # post_id format: t3_abc123 -> abc123
    clean_id = post_id.replace("t3_", "")
    if subreddit:
        url = f"https://www.reddit.com/r/{subreddit}/comments/{clean_id}/"
    else:
        # Use Reddit's shortlink
        url = f"https://www.reddit.com/comments/{clean_id}/"

    logger.info(f"Scraping comments from: {url}")

    if limiter:
        limiter.wait()

    page = context.new_page()
    page.set_default_timeout(30000)

    try:
        page.goto(url, wait_until="networkidle")
        page.wait_for_timeout(2000)  # Let comments load

        # Scroll to load more comments
        for _ in range(3):
            page.mouse.wheel(0, 3000)
            page.wait_for_timeout(1000)

        comments = extract_comments_from_page(page, post_id, url)

        if limiter:
            limiter.record_success()

        logger.info(f"Extracted {len(comments)} comments from {post_id}")
        return comments

    except PlaywrightTimeoutError:
        logger.warning(f"Timeout scraping {post_id}")
        if limiter:
            limiter.record_error()
        return []
    except Exception as e:
        logger.error(f"Error scraping {post_id}: {e}")
        if limiter:
            limiter.record_error()
        return []
    finally:
        page.close()


def load_post_ids(args) -> list[dict]:
    """Load post IDs from various sources."""
    posts = []

    # From --ids argument
    if args.ids:
        for pid in args.ids:
            posts.append({"post_id": pid, "subreddit": args.subreddit or ""})

    # From --input JSONL file
    if args.input:
        input_path = Path(args.input)
        if input_path.exists():
            with open(input_path) as f:
                for line in f:
                    if line.strip():
                        data = json.loads(line)
                        post_id = data.get("post_id", "")
                        # Try to extract subreddit from url
                        url = data.get("url", "")
                        subreddit = ""
                        if "/r/" in url:
                            subreddit = url.split("/r/")[1].split("/")[0]
                        if post_id:
                            posts.append({"post_id": post_id, "subreddit": subreddit})

    # From stdin
    if not sys.stdin.isatty() and not args.ids and not args.input:
        for line in sys.stdin:
            line = line.strip()
            if line:
                # Could be just an ID or JSON
                if line.startswith("{"):
                    data = json.loads(line)
                    posts.append({
                        "post_id": data.get("post_id", ""),
                        "subreddit": args.subreddit or ""
                    })
                else:
                    posts.append({"post_id": line, "subreddit": args.subreddit or ""})

    return posts


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reddit Comment Scraper - Pass 2 for market research pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Scrape specific posts
  scrape_comments --ids t3_abc123 t3_def456 -o comments.jsonl

  # From filtered JSONL (output of pass 1)
  scrape_comments --input valuable_posts.jsonl -o comments.jsonl

  # Pipe from jq/n8n
  jq -r '.post_id' posts.jsonl | scrape_comments -o comments.jsonl
        """
    )

    parser.add_argument("--ids", nargs="+", help="Post IDs to scrape (t3_xxx format)")
    parser.add_argument("--input", "-i", help="Input JSONL file with post_id fields")
    parser.add_argument("--output", "-o", required=True, help="Output JSONL file")
    parser.add_argument("--subreddit", "-r", help="Subreddit name (if not in input data)")
    parser.add_argument("--delay", type=float, default=3.0, help="Delay between requests")
    parser.add_argument("--headless", action="store_true", default=True)
    parser.add_argument("--log-level", choices=["DEBUG", "INFO", "WARNING", "ERROR"], default="INFO")

    args = parser.parse_args()

    setup_logging(level=args.log_level)
    logger = get_logger()

    # Load post IDs
    posts = load_post_ids(args)
    if not posts:
        logger.error("No post IDs provided. Use --ids, --input, or pipe to stdin.")
        return 1

    logger.info(f"Scraping comments from {len(posts)} posts")

    # Set up rate limiter
    limiter = AdaptiveRateLimiter(RateLimitConfig(
        min_delay=args.delay,
        requests_per_minute=15,  # Conservative for comment pages
    ))

    # Open output file
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    total_comments = 0

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=args.headless)
        context = browser.new_context(user_agent=USER_AGENT)

        with open(output_path, "w") as out_file:
            for i, post in enumerate(posts):
                post_id = post["post_id"]
                subreddit = post.get("subreddit", "")

                logger.info(f"[{i+1}/{len(posts)}] Processing {post_id}")

                comments = scrape_post_comments(context, post_id, subreddit, limiter)

                for comment in comments:
                    out_file.write(comment.model_dump_json() + "\n")
                    total_comments += 1

                out_file.flush()

        browser.close()

    logger.info(f"Done! Scraped {total_comments} comments from {len(posts)} posts")
    logger.info(f"Output: {output_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
