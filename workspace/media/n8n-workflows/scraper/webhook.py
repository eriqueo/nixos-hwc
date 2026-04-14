#!/usr/bin/env python3
"""
Webhook service for triggering the scraper via Slack or HTTP.

Run with: uvicorn webhook:app --host 0.0.0.0 --port 8765

Slack usage:
  POST /slack with Slack slash command payload
  Example command: /scrape https://facebook.com/groups/XYZ 15

HTTP usage:
  POST /scrape {"url": "https://...", "scrolls": 10}
"""

import asyncio
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request, BackgroundTasks, HTTPException
from pydantic import BaseModel
import httpx

app = FastAPI(title="HWC Scraper Webhook")

SCRIPT_DIR = Path(__file__).parent
SCRAPER_PATH = SCRIPT_DIR / "scraper.py"
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")


class ScrapeRequest(BaseModel):
    url: str
    scrolls: int = 10
    trigger_n8n: bool = True


async def notify_slack(message: str):
    """Send notification to Slack."""
    if not SLACK_WEBHOOK_URL:
        return
    try:
        async with httpx.AsyncClient() as client:
            await client.post(SLACK_WEBHOOK_URL, json={"text": message}, timeout=10)
    except Exception as e:
        print(f"Slack notification failed: {e}")


def run_scraper(url: str, scrolls: int, trigger_n8n: bool):
    """Run the scraper in a subprocess."""
    cmd = [
        sys.executable, str(SCRAPER_PATH),
        "--url", url,
        "--scrolls", str(scrolls)
    ]
    if trigger_n8n:
        cmd.append("--trigger-webhook")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5 minute timeout
            cwd=str(SCRIPT_DIR)
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Scraper timed out after 5 minutes"
    except Exception as e:
        return False, "", str(e)


async def run_scraper_async(url: str, scrolls: int, trigger_n8n: bool):
    """Run scraper in background and notify Slack."""
    await notify_slack(f":mag: Starting scrape: `{url}` ({scrolls} scrolls)")

    # Run in thread pool to not block
    loop = asyncio.get_event_loop()
    success, stdout, stderr = await loop.run_in_executor(
        None, run_scraper, url, scrolls, trigger_n8n
    )

    if success:
        # Extract post count from output
        lines = stdout.split("\n")
        post_line = [l for l in lines if "Saved" in l]
        count_msg = post_line[0] if post_line else "Scrape complete"
        await notify_slack(f":white_check_mark: {count_msg}")
    else:
        await notify_slack(f":x: Scrape failed: {stderr[:200]}")


@app.post("/scrape")
async def scrape_endpoint(req: ScrapeRequest, background_tasks: BackgroundTasks):
    """Direct HTTP endpoint to trigger scraper."""
    background_tasks.add_task(run_scraper_async, req.url, req.scrolls, req.trigger_n8n)
    return {"status": "started", "url": req.url, "scrolls": req.scrolls}


@app.post("/slack")
async def slack_command(request: Request, background_tasks: BackgroundTasks):
    """
    Slack slash command endpoint.

    Configure in Slack:
      Command: /scrape
      Request URL: https://your-server:8765/slack

    Usage: /scrape https://facebook.com/groups/XYZ 15
    """
    form = await request.form()

    # Parse Slack command text
    text = form.get("text", "").strip()
    parts = text.split()

    if not parts:
        return {"response_type": "ephemeral", "text": "Usage: /scrape <url> [scrolls]"}

    url = parts[0]
    scrolls = int(parts[1]) if len(parts) > 1 else 10

    # Validate URL
    if not url.startswith("http"):
        return {"response_type": "ephemeral", "text": f"Invalid URL: {url}"}

    # Start scraper in background
    background_tasks.add_task(run_scraper_async, url, scrolls, True)

    return {
        "response_type": "in_channel",
        "text": f":mag: Starting scrape: `{url}` ({scrolls} scrolls)\nI'll notify you when it's done."
    }


@app.post("/tampermonkey")
async def tampermonkey_upload(request: Request, background_tasks: BackgroundTasks):
    """
    Endpoint for Tampermonkey script to upload scraped data.

    Expects JSON: {
        "source": "Facebook",
        "group": "Bozeman Home Improvement",
        "posts": [{"author": "...", "text": "...", ...}]
    }
    """
    import pandas as pd

    data = await request.json()
    source = data.get("source", "Unknown")
    group = data.get("group", "Unknown")
    posts = data.get("posts", [])

    if not posts:
        raise HTTPException(status_code=400, detail="No posts provided")

    # Convert to DataFrame
    df = pd.DataFrame(posts)

    # Ensure standard columns
    df.insert(0, "Source", source)
    df.insert(1, "Group", group)

    for col in ["Author", "Date", "Text", "Reactions", "Comments Count", "Comments"]:
        if col not in df.columns:
            df[col] = ""

    df = df[["Source", "Group", "Author", "Date", "Text", "Reactions", "Comments Count", "Comments"]]

    # Save to output directory
    output_dir = Path(os.environ.get("SCRAPER_OUTPUT_DIR", "/data/scraper-output"))
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_group = "".join(c for c in group if c.isalnum() or c in "._- ")[:30]
    output_path = output_dir / f"tampermonkey_{safe_group}_{timestamp}.csv"

    df.to_csv(output_path, index=False)

    # Notify
    await notify_slack(f":monkey: Tampermonkey upload: {len(posts)} posts from {source}/{group}")

    # Trigger n8n webhook
    n8n_webhook = os.environ.get("N8N_SCRAPER_WEBHOOK", "http://localhost:5678/webhook/scraper-complete")
    try:
        async with httpx.AsyncClient() as client:
            await client.post(n8n_webhook, json={"filepath": str(output_path)}, timeout=10)
    except Exception as e:
        print(f"n8n webhook failed: {e}")

    return {"status": "saved", "path": str(output_path), "count": len(posts)}


@app.get("/health")
async def health():
    return {"status": "ok", "scraper_exists": SCRAPER_PATH.exists()}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8765)
