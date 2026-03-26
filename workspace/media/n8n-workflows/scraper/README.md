# HWC Social Media Scraper

Multi-platform scraper that feeds the n8n Intelligence Pipeline.

## Components

- `scraper.py` - Playwright-based scraper for Facebook, Reddit, Nextdoor
- `sites.json` - CSS selectors configuration for each platform
- `webhook.py` - FastAPI service for Slack/HTTP/Tampermonkey triggers

## Quick Start

```bash
# Install dependencies
pip install playwright pandas fastapi uvicorn httpx

# Install browser
playwright install chromium

# First-time login (Facebook/Nextdoor require this)
python scraper.py --url "https://facebook.com/groups/XYZ" --login

# Scrape
python scraper.py --url "https://facebook.com/groups/XYZ" --scrolls 15
```

## Trigger Methods

### 1. Manual CLI
```bash
python scraper.py --url "https://facebook.com/groups/123" --scrolls 10
```

### 2. Slack Command
Configure `/scrape` slash command pointing to webhook:
```
/scrape https://facebook.com/groups/XYZ 15
```

### 3. Tampermonkey Upload
POST scraped data from browser extension:
```javascript
fetch('http://your-server:8765/tampermonkey', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
        source: 'Facebook',
        group: 'Bozeman Home Improvement',
        posts: [{author: '...', text: '...', ...}]
    })
});
```

### 4. Folder Watch (n8n)
Drop any CSV into `/data/scraper-output/` and the n8n Intelligence Pipeline auto-triggers.

## Output Format

All outputs are standardized CSVs:

| Column | Description |
|--------|-------------|
| Source | Platform name (Facebook, Reddit, Nextdoor) |
| Group | Group/subreddit name |
| Author | Post author |
| Date | Post date |
| Text | Post content |
| Reactions | Reaction count |
| Comments Count | Number of comments |
| Comments | Comment text |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCRAPER_OUTPUT_DIR` | `/data/scraper-output` | Where CSVs are saved |
| `N8N_SCRAPER_WEBHOOK` | `http://localhost:5678/webhook/scraper-complete` | n8n webhook URL |
| `SLACK_WEBHOOK_URL` | (none) | Slack incoming webhook for notifications |

## Running the Webhook Service

```bash
# Development
uvicorn webhook:app --host 0.0.0.0 --port 8765

# With environment
```

## Troubleshooting

**Getting blocked by Facebook/Nextdoor:**
- Increase `SCROLL_DELAY` in scraper.py from 3 to 5-6 seconds
- Use fewer scrolls per session (10-15 max)
- Wait between scraping sessions

**Session expired:**
- Re-run with `--login` flag to save new session
