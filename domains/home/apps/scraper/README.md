# Home Apps — Scraper

## Purpose
Social media scraper and comment analysis tools using Playwright for browser automation.

## Boundaries
- Manages: Scraper CLI wrappers, Playwright browser setup
- Does NOT manage: Scraper source code (lives in `workspace/home/scraper/`)

## Structure
```
scraper/
├── index.nix    # Wrapper scripts + Playwright setup
└── README.md    # This file
```

### Workspace Source (`workspace/home/scraper/`)
- `scraper.py` — Main social media scraper
- `scrape_comments.py` — Comment analysis pass
- `sites.json` — Site configuration

## CLI Tools
- `scraper` — Run the social media scraper
- `scrape-comments` — Run comment analysis

## Changelog
- 2026-07-11: `nixosPath` standalone fallback derives from `config.home.homeDirectory` instead of a `/home/eric` literal (Law 3, value unchanged).
- 2026-03-26: Workspace source moved from workspace/hwc/social_media_scraper/ to workspace/home/scraper/ (domain alignment)
