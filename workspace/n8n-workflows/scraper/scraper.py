#!/usr/bin/env python3
"""
Multi-platform social media scraper for HWC Intelligence Pipeline.

Scrapes Facebook groups, Reddit, and Nextdoor using Playwright.
Outputs standardized CSVs that feed into the n8n Intelligence Pipeline.

Usage:
    python scraper.py --url "https://facebook.com/groups/XYZ"
    python scraper.py --url "https://reddit.com/r/Bozeman" --scrolls 20
    python scraper.py --url "https://nextdoor.com/" --login
    python scraper.py --url "..." --output my_data.csv
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import pandas as pd
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError

# Configuration
SCRIPT_DIR = Path(__file__).parent
SITES_CONFIG = SCRIPT_DIR / "sites.json"
AUTH_DIR = SCRIPT_DIR / "auth"
OUTPUT_DIR = Path(os.environ.get("SCRAPER_OUTPUT_DIR", "/data/scraper-output"))
DEFAULT_SCROLLS = 10
SCROLL_DELAY = 3  # Seconds between scrolls (increase if getting blocked)
PAGE_LOAD_TIMEOUT = 30000  # ms


def load_sites_config():
    """Load site configurations from sites.json."""
    with open(SITES_CONFIG) as f:
        return json.load(f)


def match_site(url: str, sites: dict) -> tuple[str, dict] | None:
    """Match URL to a site configuration."""
    for site_name, config in sites.items():
        if re.search(config["url_pattern"], url):
            return site_name, config
    return None


def load_auth(site_name: str) -> dict | None:
    """Load saved authentication state for a site."""
    auth_file = AUTH_DIR / f"{site_name}_auth.json"
    if auth_file.exists():
        with open(auth_file) as f:
            return json.load(f)
    return None


def save_auth(site_name: str, storage_state: dict):
    """Save authentication state for a site."""
    AUTH_DIR.mkdir(exist_ok=True)
    auth_file = AUTH_DIR / f"{site_name}_auth.json"
    with open(auth_file, "w") as f:
        json.dump(storage_state, f)
    print(f"Session saved to {auth_file}")


def extract_posts(page, selectors: dict) -> list[dict]:
    """Extract posts from the current page using configured selectors."""
    posts = []

    try:
        post_elements = page.query_selector_all(selectors["post_container"])
    except Exception as e:
        print(f"Error finding posts: {e}")
        return posts

    for post_el in post_elements:
        try:
            post = {
                "author": "",
                "date": "",
                "text": "",
                "reactions": "",
                "comments_count": "",
                "comments": ""
            }

            # Extract each field using selectors
            for field, selector in selectors.get("fields", {}).items():
                try:
                    el = post_el.query_selector(selector)
                    if el:
                        post[field] = el.inner_text().strip()
                except Exception:
                    pass

            # Only add if we got meaningful content
            if post.get("text") or post.get("author"):
                posts.append(post)

        except Exception as e:
            print(f"Error extracting post: {e}")
            continue

    return posts


def deduplicate_posts(posts: list[dict]) -> list[dict]:
    """Remove duplicate posts based on text content."""
    seen = set()
    unique = []
    for post in posts:
        # Create a fingerprint from text (first 100 chars) and author
        fingerprint = f"{post.get('author', '')[:30]}|{post.get('text', '')[:100]}"
        if fingerprint not in seen:
            seen.add(fingerprint)
            unique.append(post)
    return unique


def scrape(url: str, site_name: str, config: dict, num_scrolls: int, login_mode: bool = False) -> list[dict]:
    """Main scraping function."""
    all_posts = []

    with sync_playwright() as p:
        # Launch browser
        browser = p.chromium.launch(
            headless=not login_mode,  # Show browser for login
            args=["--disable-blink-features=AutomationControlled"]
        )

        # Load saved auth if available
        auth_state = load_auth(site_name)
        context_args = {"storage_state": auth_state} if auth_state else {}

        context = browser.new_context(
            viewport={"width": 1280, "height": 900},
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            **context_args
        )

        page = context.new_page()

        try:
            print(f"Loading {url}...")
            page.goto(url, timeout=PAGE_LOAD_TIMEOUT, wait_until="domcontentloaded")

            # Wait for content to load
            time.sleep(3)

            if login_mode:
                print("\n=== LOGIN MODE ===")
                print("Log in manually in the browser window.")
                print("Once you can see the feed, press Ctrl+C to save session.\n")
                try:
                    while True:
                        time.sleep(1)
                except KeyboardInterrupt:
                    # Save the session
                    storage_state = context.storage_state()
                    save_auth(site_name, storage_state)
                    browser.close()
                    return []

            # Scroll and collect posts
            selectors = config.get("selectors", {})

            for i in range(num_scrolls):
                print(f"Scroll {i + 1}/{num_scrolls}...")

                # Extract posts from current view
                new_posts = extract_posts(page, selectors)
                all_posts.extend(new_posts)

                # Deduplicate after each scroll
                all_posts = deduplicate_posts(all_posts)
                print(f"  Found {len(all_posts)} unique posts so far")

                # Scroll down
                page.evaluate("window.scrollBy(0, window.innerHeight * 2)")
                time.sleep(SCROLL_DELAY)

        except PlaywrightTimeoutError:
            print(f"Timeout loading {url}")
        except Exception as e:
            print(f"Error during scrape: {e}")
        finally:
            browser.close()

    return all_posts


def save_csv(posts: list[dict], source: str, group_name: str, output_path: Path):
    """Save posts to standardized CSV format."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    df = pd.DataFrame(posts)

    # Standardize column names
    column_map = {
        "author": "Author",
        "date": "Date",
        "text": "Text",
        "reactions": "Reactions",
        "comments_count": "Comments Count",
        "comments": "Comments"
    }

    df = df.rename(columns=column_map)

    # Add source columns
    df.insert(0, "Source", source)
    df.insert(1, "Group", group_name)

    # Ensure all standard columns exist
    for col in ["Source", "Group", "Author", "Date", "Text", "Reactions", "Comments Count", "Comments"]:
        if col not in df.columns:
            df[col] = ""

    # Reorder columns
    df = df[["Source", "Group", "Author", "Date", "Text", "Reactions", "Comments Count", "Comments"]]

    df.to_csv(output_path, index=False)
    print(f"\nSaved {len(df)} posts to {output_path}")

    return output_path


def extract_group_name(url: str, site_name: str) -> str:
    """Extract group/subreddit name from URL."""
    if site_name == "facebook_group":
        match = re.search(r"/groups/([^/?]+)", url)
        return match.group(1) if match else "unknown_group"
    elif site_name == "reddit":
        match = re.search(r"/r/([^/?]+)", url)
        return match.group(1) if match else "unknown_subreddit"
    elif site_name == "nextdoor":
        return "nextdoor_feed"
    return "unknown"


def main():
    parser = argparse.ArgumentParser(description="Multi-platform social media scraper")
    parser.add_argument("--url", required=True, help="URL to scrape")
    parser.add_argument("--scrolls", type=int, default=DEFAULT_SCROLLS, help="Number of scrolls")
    parser.add_argument("--output", help="Output CSV filename (default: auto-generated)")
    parser.add_argument("--login", action="store_true", help="Login mode - save session")
    parser.add_argument("--trigger-webhook", action="store_true", help="Trigger n8n webhook after scrape")
    args = parser.parse_args()

    # Load site configs
    sites = load_sites_config()

    # Match URL to site
    match = match_site(args.url, sites)
    if not match:
        print(f"Error: No configuration found for URL: {args.url}")
        print(f"Supported sites: {', '.join(sites.keys())}")
        sys.exit(1)

    site_name, config = match
    print(f"Detected site: {config['name']}")

    # Run scraper
    posts = scrape(args.url, site_name, config, args.scrolls, args.login)

    if args.login:
        print("Login session saved. Run again without --login to scrape.")
        return

    if not posts:
        print("No posts found.")
        return

    # Generate output filename
    group_name = extract_group_name(args.url, site_name)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    if args.output:
        output_path = OUTPUT_DIR / args.output
    else:
        output_path = OUTPUT_DIR / f"{site_name}_{group_name}_{timestamp}.csv"

    # Save CSV
    csv_path = save_csv(posts, config["name"], group_name, output_path)

    # Optionally trigger n8n webhook
    if args.trigger_webhook:
        webhook_url = os.environ.get("N8N_SCRAPER_WEBHOOK", "http://localhost:5678/webhook/scraper-complete")
        try:
            import requests
            requests.post(webhook_url, json={"filepath": str(csv_path)}, timeout=10)
            print(f"Triggered n8n webhook: {webhook_url}")
        except Exception as e:
            print(f"Failed to trigger webhook: {e}")


if __name__ == "__main__":
    main()
