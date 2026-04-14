'''
Configurable, Multi-Platform Social Media Scraper Engine

This script uses Playwright to scrape posts and comments from various social media sites
based on a `sites.json` configuration file. It handles login, scrolling, data extraction,
and saves the output to a standardized CSV format.

Author: Manus AI
Version: 1.0

Usage:
  - For login (one-time setup per site):
    python scraper.py --url "https://www.facebook.com" --login

  - To run a scrape:
    python scraper.py --url "https://www.facebook.com/groups/your_group_id"

  - For more options:
    python scraper.py --help
'''

import json
import argparse
import time
import pandas as pd
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError
from pathlib import Path

# --- Configuration ---
CONFIG_FILE = "sites.json"
DEFAULT_SCROLLS = 10
SCROLL_DELAY = 3  # seconds
TIMEOUT = 15000  # milliseconds


def load_config():
    """Loads the sites.json configuration file."""
    if not Path(CONFIG_FILE).exists():
        print(f"Error: Configuration file '{CONFIG_FILE}' not found.")
        print("Please create it next to the scraper.py script.")
        exit(1)
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)


def get_site_config(url, config):
    """Determines which site configuration to use based on the URL."""
    for site in config["sites"]:
        if site["url_pattern"] in url:
            print(f"Found matching configuration: '{site['name']}'")
            return site
    return None


def extract_data(page, site_config):
    """Extracts data from the page based on the site's selectors."""
    posts_data = []
    post_elements = page.query_selector_all(site_config["post_container_selector"])
    print(f"Found {len(post_elements)} post containers on the page.")

    for post_el in post_elements:
        post = {"Source": site_config["name"], "Group": page.title()}
        scrapers = site_config["scrapers"]

        # Scrape main post content
        for key, scraper_config in scrapers.items():
            if "comment_" in key or "_container_" in key: continue
            try:
                element = post_el.query_selector(scraper_config["selector"])
                if element:
                    if scraper_config.get("type") == "text":
                        post[key.capitalize()] = element.inner_text().strip()
                    elif scraper_config.get("type") == "href":
                        post[key.capitalize()] = element.get_attribute('href')
            except Exception as e:
                # print(f"  - Could not find {key}: {e}")
                post[key.capitalize()] = ""

        # Scrape comments
        comments = []
        if "comments_container_selector" in scrapers:
            comment_elements = post_el.query_selector_all(scrapers["comments_container_selector"])
            for comment_el in comment_elements:
                comment = {}
                try:
                    author_el = comment_el.query_selector(scrapers["comment_author"]["selector"])
                    text_el = comment_el.query_selector(scrapers["comment_text"]["selector"])
                    if author_el and text_el:
                        comment["author"] = author_el.inner_text().strip()
                        comment["text"] = text_el.inner_text().strip()
                        comments.append(comment)
                except Exception:
                    continue # Skip malformed comment
        
        post["Comments"] = json.dumps(comments)
        post["Comments Count"] = len(comments)

        # Add to list if post has some text content
        if post.get("Text"):
            posts_data.append(post)
            
    return posts_data


def main():
    parser = argparse.ArgumentParser(description="Configurable Social Media Scraper")
    parser.add_argument("--url", required=True, help="The URL of the page to scrape.")
    parser.add_argument("--login", action="store_true", help="Perform a manual login to save the auth state.")
    parser.add_argument("--scrolls", type=int, default=DEFAULT_SCROLLS, help="Number of times to scroll down the page.")
    parser.add_argument("--output", help="Name of the output CSV file.")
    args = parser.parse_args()

    config = load_config()
    site_config = get_site_config(args.url, config)

    if not site_config:
        print(f"Error: No configuration found for URL: {args.url}")
        return

    auth_file = Path(f"{site_config['name'].lower().replace(' ', '_')}_auth.json")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False) # Headless=False is important for login
        context_args = {"storage_state": auth_file} if auth_file.exists() and not args.login else {}
        context = browser.new_context(**context_args)
        page = context.new_page()
        page.set_default_timeout(TIMEOUT)

        print(f"Navigating to: {args.url}")
        try:
            page.goto(args.url, wait_until="domcontentloaded")
        except PlaywrightTimeoutError:
            print("Timeout navigating to page. It might be slow to load. Continuing...")

        if args.login:
            print("--- MANUAL LOGIN REQUIRED ---")
            print(f"Please log in to {site_config['name']} in the browser window.")
            print("Once you are fully logged in, close this script with Ctrl+C.")
            print("Your session will be saved for future runs.")
            try:
                # Wait indefinitely for the user to do their thing
                page.wait_for_timeout(3600 * 1000) 
            except KeyboardInterrupt:
                print("\nLogin process interrupted by user. Saving authentication state...")
                context.storage_state(path=auth_file)
                print(f"Authentication state saved to {auth_file}")
            browser.close()
            return

        # --- Main Scraping Logic ---
        print("Starting scrape...")
        all_posts = []
        processed_post_texts = set()

        for i in range(args.scrolls):
            print(f"\n--- Scroll {i + 1}/{args.scrolls} ---")
            current_posts = extract_data(page, site_config)
            new_posts_found = 0
            for post in current_posts:
                # Simple deduplication based on post text
                post_key = post.get("Text", "")[:200]
                if post_key and post_key not in processed_post_texts:
                    all_posts.append(post)
                    processed_post_texts.add(post_key)
                    new_posts_found += 1
            
            print(f"Found {new_posts_found} new posts this scroll. Total unique posts: {len(all_posts)}")

            # Scroll down
            page.mouse.wheel(0, 15000)
            print(f"Waiting {SCROLL_DELAY} seconds for content to load...")
            time.sleep(SCROLL_DELAY)

        print("\nScraping complete.")
        browser.close()

        # --- Save to CSV ---
        if not all_posts:
            print("No data was scraped. Exiting.")
            return

        df = pd.DataFrame(all_posts)
        # Reorder columns for clarity
        cols = ['Source', 'Group', 'Author', 'Date', 'Text', 'Reactions', 'Comments Count', 'Comments']
        df = df.reindex(columns=[c for c in cols if c in df.columns] + [c for c in df.columns if c not in cols])

        output_filename = args.output or f"{site_config['name'].lower().replace(' ', '_')}_data.csv"
        df.to_csv(output_filename, index=False)
        print(f"Successfully saved {len(df)} posts to {output_filename}")


if __name__ == "__main__":
    main()
