"""
Logged-in X capture through a real browser.

X only lists a post's replies to a logged-in client, and its API rejects
requests without the x-client-transaction-id that X's own obfuscated script
signs. So this drives headless Chromium with a saved X login (imported
cookies), opens the post, scrolls, and reads X's own TweetDetail responses.
The only module that touches Playwright; xpost.Conversation parses what it
collects. Same technique as Lead Scout's Facebook scraper.

Retention of the profile directory: REPLACEABLE — a lost profile is rebuilt
by importing the cookies again (POST /x/session).
"""

import asyncio
import json
import logging
import os
import random
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from transcript import TranscriptError
import xpost

logger = logging.getLogger("transcripts")

PROFILE_DIR = Path(os.getenv("X_PROFILE_DIR", "/var/lib/hwc/transcripts/x-profile"))
STATUS_FILE = "hwc-x-session.json"   # derived from the last import/capture; never holds cookie values

CAPTURE_BUDGET_SECONDS = 150
FIRST_RESPONSE_SECONDS = 20
# Scrolls with no new posts before trying "show more" or accepting X's end
# signal. While X has not ended the timeline, wait up to STALE_SCROLLS_PENDING:
# measured 2026-10-12, X sends a page every 3-7 s and one scroll takes 1-1.7 s,
# so 4 scrolls stopped a live capture at 60 of ~400 replies.
STALE_SCROLLS = 4
STALE_SCROLLS_PENDING = 12
MAX_SHOW_MORE_CLICKS = 5
SCROLL_PIXELS = 3000

# Pages X sends a logged-out, expired or locked session to.
_LOGIN_URL = re.compile(r"x\.com/(i/flow/login|login|account/access|i/flow/consent)", re.IGNORECASE)
# Buttons that reveal hidden replies; matched on their visible text.
_SHOW_MORE = re.compile(r"^(Show more replies|Show additional replies|Show probable spam|Show replies)",
                        re.IGNORECASE)

# One browser at a time: the profile directory cannot be opened twice.
_lock = asyncio.Lock()


# ---------------------------------------------------------------------------
# Capture loop (browser-independent; tested against a fake page)
# ---------------------------------------------------------------------------
@dataclass
class Capture:
    conversation: xpost.Conversation
    reached_end: bool      # X had no further page
    hit_limit: bool
    hit_budget: bool


class PagePort:
    """What the capture loop needs from a page. PlaywrightPage implements it."""
    async def open(self, url: str) -> None: ...
    def url(self) -> str: ...
    async def scroll(self) -> None: ...
    async def click_show_more(self) -> bool: ...
    async def settle(self) -> None: ...


def _target_count(conv: xpost.Conversation, focal_id: str, mode: str) -> int:
    if mode == "replies":
        return len(xpost.direct_replies(conv, focal_id))
    return len(conv.posts)


async def drive(page: PagePort, conv: xpost.Conversation, seen: Callable[[], int],
                rate_limited: Callable[[], bool], focal_id: str, mode: str, limit: int,
                on_stage=lambda stage: None, budget: float = CAPTURE_BUDGET_SECONDS,
                clock=time.monotonic) -> Capture:
    """Open the post and scroll until the limit, the end of the conversation,
    the time budget, or a login wall. `seen()` counts TweetDetail responses
    parsed so far (the browser adapter feeds `conv` as they arrive)."""
    deadline = clock() + budget
    on_stage("opening post")
    await page.open(xpost.post_url(focal_id))

    waited = 0.0
    while seen() == 0:
        if _LOGIN_URL.search(page.url()):
            raise TranscriptError("login_required", "X sent the browser to a login page")
        if rate_limited():
            raise TranscriptError("rate_limited", "X answered 429 to TweetDetail")
        if waited >= FIRST_RESPONSE_SECONDS:
            # Logged out, X renders 3 replies into the page and calls no API.
            raise TranscriptError("login_required", "no logged-in conversation data arrived")
        await page.settle()
        waited += 1

    stale = clicks = 0
    last = -1
    while True:
        count = _target_count(conv, focal_id, mode)
        on_stage(f"scrolling ({count} {'replies' if mode == 'replies' else 'posts'})")
        if mode == "replies" and count >= limit:
            return Capture(conv, False, True, False)
        if len(conv.posts) >= xpost.REPLY_LIMIT_MAX * 2:
            return Capture(conv, False, True, False)
        if clock() >= deadline:
            return Capture(conv, False, False, True)
        if rate_limited():
            raise TranscriptError("rate_limited", "X answered 429 to TweetDetail")
        if _LOGIN_URL.search(page.url()):
            raise TranscriptError("login_required", "X sent the browser to a login page")
        if len(conv.posts) == last:
            stale += 1
        else:
            stale, last = 0, len(conv.posts)
        if stale >= STALE_SCROLLS:
            if clicks < MAX_SHOW_MORE_CLICKS and await page.click_show_more():
                clicks += 1
                stale = 0
            elif conv.ended:
                return Capture(conv, True, False, False)
            elif stale >= STALE_SCROLLS_PENDING:
                return Capture(conv, False, False, False)
        await page.scroll()
        await page.settle()


# ---------------------------------------------------------------------------
# Playwright adapter
# ---------------------------------------------------------------------------
class PlaywrightPage(PagePort):
    def __init__(self, page):
        self._page = page

    async def open(self, url: str) -> None:
        await self._page.goto(url, wait_until="domcontentloaded", timeout=30_000)

    def url(self) -> str:
        return self._page.url

    async def scroll(self) -> None:
        await self._page.mouse.wheel(0, SCROLL_PIXELS)

    async def click_show_more(self) -> bool:
        button = self._page.get_by_role("button", name=_SHOW_MORE).first
        try:
            if await button.count() and await button.is_visible():
                await button.click(timeout=5_000)
                return True
        except Exception as e:  # a re-rendered button is not a failure
            logger.info(f"X show-more click skipped: {type(e).__name__}")
        return False

    async def settle(self) -> None:
        await self._page.wait_for_timeout(1000 + random.randint(0, 700))


async def _launch(pw):
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    ctx = await pw.chromium.launch_persistent_context(
        str(PROFILE_DIR), channel="chromium", headless=True,
        args=["--no-sandbox", "--disable-blink-features=AutomationControlled"],
        viewport={"width": 1280, "height": 1600}, locale="en-US")
    page = ctx.pages[0] if ctx.pages else await ctx.new_page()
    # Headless Chromium names itself "HeadlessChrome"; x.com answers that with
    # 403. Present the same browser's normal identity instead.
    ua = (await page.evaluate("navigator.userAgent")).replace("HeadlessChrome", "Chrome")
    cdp = await ctx.new_cdp_session(page)
    await cdp.send("Network.setUserAgentOverride", {"userAgent": ua})
    await page.route(re.compile(r"\.(png|jpe?g|gif|webp|mp4|m3u8|woff2?)(\?|$)"),
                     lambda route: route.abort())
    return ctx, page


def _write_status(**fields) -> None:
    path = PROFILE_DIR / STATUS_FILE
    status = session_status() | fields
    path.write_text(json.dumps(status))


def session_status() -> dict:
    try:
        return json.loads((PROFILE_DIR / STATUS_FILE).read_text())
    except (OSError, ValueError):
        return {"linked": False}


async def capture(focal_id: str, mode: str, limit: int, on_stage=lambda stage: None) -> Capture:
    from playwright.async_api import async_playwright

    if not session_status().get("linked"):
        raise TranscriptError("login_required", "no X login imported yet")
    async with _lock, async_playwright() as pw:
        ctx, page = await _launch(pw)
        conv = xpost.Conversation()
        state = {"seen": 0, "429": False}
        pending: set[asyncio.Task] = set()

        async def read(response) -> None:
            if "/TweetDetail" not in response.url:
                return
            if response.status == 429:
                state["429"] = True
            elif response.ok:
                try:
                    conv.add(await response.json())
                    state["seen"] += 1
                except Exception as e:
                    logger.info(f"X TweetDetail unreadable: {type(e).__name__}")

        def on_response(response) -> None:
            task = asyncio.ensure_future(read(response))
            pending.add(task)
            task.add_done_callback(pending.discard)

        page.on("response", on_response)
        try:
            result = await drive(PlaywrightPage(page), conv, lambda: state["seen"],
                                 lambda: state["429"], focal_id, mode, limit, on_stage)
            if pending:
                await asyncio.wait(pending, timeout=5)
            return result
        except TranscriptError as e:
            if e.reason == "login_required":
                _write_status(linked=False)
            raise
        finally:
            await ctx.close()


# ---------------------------------------------------------------------------
# Session import
# ---------------------------------------------------------------------------
_X_DOMAIN = re.compile(r"^\.?(x|twitter)\.com$")


def parse_cookies(text: str) -> list[dict]:
    """Netscape cookies.txt or a JSON cookie export -> Playwright cookies.
    Rejects anything outside x.com/twitter.com and requires the login pair."""
    text = text.strip()
    cookies = []
    if text.startswith("["):
        for c in json.loads(text):
            cookies.append({"name": c["name"], "value": c["value"], "domain": c["domain"],
                            "path": c.get("path", "/"), "secure": bool(c.get("secure", True)),
                            "httpOnly": bool(c.get("httpOnly", False)),
                            "expires": float(c.get("expirationDate") or c.get("expires") or -1)})
    else:
        for line in text.splitlines():
            http_only = line.startswith("#HttpOnly_")
            if http_only:
                line = line.removeprefix("#HttpOnly_")
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 7:
                raise ValueError("Not a cookies.txt file (expected 7 tab-separated fields per line).")
            domain, _, path, secure, expires, name, value = parts
            cookies.append({"name": name, "value": value, "domain": domain, "path": path,
                            "secure": secure.upper() == "TRUE", "httpOnly": http_only,
                            "expires": float(expires) if expires not in ("", "0") else -1})
    foreign = sorted({c["domain"] for c in cookies if not _X_DOMAIN.match(c["domain"])})
    if foreign:
        raise ValueError(f"Only x.com cookies are accepted; found {', '.join(foreign)}.")
    names = {c["name"] for c in cookies}
    if not {"auth_token", "ct0"} <= names:
        raise ValueError("The export has no X login (auth_token and ct0 are missing). "
                         "Export while logged in to x.com.")
    for c in cookies:
        c["domain"] = ".x.com"
        c["sameSite"] = "Lax"
    return cookies


async def import_session(text: str) -> dict:
    """Replace the profile's X login with the given cookies and prove it by
    loading x.com/home. On failure the previous cookies are restored."""
    from playwright.async_api import async_playwright

    cookies = parse_cookies(text)
    async with _lock, async_playwright() as pw:
        ctx, page = await _launch(pw)
        snapshot = await ctx.cookies()
        try:
            await ctx.clear_cookies()
            await ctx.add_cookies(cookies)
            await page.goto("https://x.com/home", wait_until="domcontentloaded", timeout=30_000)
            link = page.locator('a[data-testid="AppTabBar_Profile_Link"]')
            try:
                await link.wait_for(timeout=20_000)
            except Exception:
                raise ValueError("X did not accept this login (no account page loaded). "
                                 "Export the cookies again while logged in.")
            if _LOGIN_URL.search(page.url):
                raise ValueError("X sent the browser to a login page; the cookies are expired.")
            handle = ((await link.get_attribute("href")) or "").strip("/")
        except BaseException:
            await ctx.clear_cookies()
            if snapshot:
                await ctx.add_cookies(snapshot)
            await ctx.close()
            raise
        await ctx.close()
    status = {"linked": True, "handle": handle, "imported_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    _write_status(**status)
    return status
