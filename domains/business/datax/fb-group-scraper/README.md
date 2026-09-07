# fb-group-scraper

Headless Facebook group scraper built on Playwright. Intercepts FB's internal GraphQL API responses during scroll — no DOM parsing, no fragile selectors for post content. Stores posts and comments in SQLite with deterministic IDs for dedup across runs.

## Setup

```bash
npm install
npx playwright install chromium
```

## Auth

First run requires a one-time interactive login to capture session cookies:

```bash
node index.mjs --login --headed
```

This opens a browser. Log in to Facebook manually, press Enter in the terminal, and the session is saved to `./data/session.json`. Subsequent runs reuse this session headlessly.

If the session expires (you'll see "Session expired"), re-run the login step.

## Usage

```bash
# Scrape 50 posts (default)
node index.mjs https://facebook.com/groups/jobtread

# Short form — just the group slug
node index.mjs jobtread -n 100

# Include full comment threads
node index.mjs jobtread -n 50 -d comments

# Quiet mode (cron-friendly — errors and summary only)
node index.mjs jobtread -n 100 -q

# Custom paths
node index.mjs jobtread --db ./mydata/jt.db --session ./mydata/session.json
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-n, --posts` | Number of posts to collect | 50 |
| `-d, --depth` | `posts` or `comments` | posts |
| `--db` | SQLite database path | `./data/posts.db` |
| `--session` | Session state file | `./data/session.json` |
| `--headed` | Show the browser window | off |
| `--login` | Interactive login mode | — |
| `-q, --quiet` | Minimal output | off |

## Cron

```cron
# Every 6 hours, scrape the latest 50 posts
0 */6 * * * cd /path/to/fb-group-scraper && node index.mjs jobtread -n 50 -q >> /var/log/fb-scraper.log 2>&1
```

Each run is idempotent — posts with the same ID are updated (engagement numbers), not duplicated. New comments attach to existing posts.

## How It Works

1. Launches Chromium with saved session cookies
2. Navigates to the group feed
3. Hooks `page.on('response')` to intercept FB's GraphQL API calls — same data the Tampermonkey script captures, but via Playwright's network layer instead of fetch/XHR hooks
4. Routes responses by `fb_api_req_friendly_name` — only parses `GroupsCometFeed` for posts, `CometSinglePostDialogContentQuery` for full comments, `CommentsListPaginationQuery` for paginated replies
5. Scrolls with human-like cadence (random distance + delay) to trigger feed loading
6. Optionally navigates to each post URL to expand comments — scrolls the comment section, then multi-pass clicks "N Replies" / "View more replies" buttons to capture nested reply threads
7. Persists to SQLite with `INSERT ... ON CONFLICT UPDATE` for clean dedup

### Post IDs

Posts are identified by FB's canonical post ID extracted from the URL (`/posts/1286089016487814` → `1286089016487814`). Posts without a URL-based ID are skipped — this matches the Tampermonkey script's behavior and ensures stable, deterministic keys. This means:

- Repeat runs don't create duplicate rows
- Updated engagement numbers (reactions, comment counts) overwrite stale values
- Comments from later runs attach to the original post record

## Schema

**posts** — `post_id, group_url, author, body, source, url, timestamp, reactions, comment_count, first_seen, last_seen`

**comments** — `id, post_id, author, body, depth, timestamp, first_seen`

`depth` tracks comment nesting: 0 = top-level, 1 = reply, 2 = reply-to-reply, etc.

Query examples:

```sql
-- Posts from the last week
SELECT author, substr(body, 1, 80), datetime(timestamp, 'unixepoch') FROM posts
WHERE timestamp > unixepoch('now', '-7 days') ORDER BY timestamp DESC;

-- Top posts by engagement
SELECT author, reactions, comment_count, substr(body, 1, 80) FROM posts
ORDER BY coalesce(reactions, 0) + coalesce(comment_count, 0) DESC LIMIT 20;

-- All comments on a specific post (threaded)
SELECT c.depth, c.author, c.body FROM comments c
WHERE c.post_id = '1286089016487814' ORDER BY c.timestamp;

-- Reply depth distribution
SELECT depth, COUNT(*) FROM comments GROUP BY depth;
```

## Notes

- **Anti-detection:** The script uses a standard Chromium instance with `AutomationControlled` disabled and human-like scroll pacing. For heavier use, consider adding [playwright-extra](https://github.com/nickreese/playwright-extra) with the stealth plugin.
- **Rate limiting:** The scroll loop pauses longer after consecutive empty scrolls. The comment expansion pass waits between navigations. Adjust `SCROLL` constants in `index.mjs` if needed.
- **Session expiry:** FB sessions typically last weeks but can expire sooner. The script detects this and exits with a clear message.
- **Comment depth:** The `comments` mode scrolls each post's comment section, then runs up to 5 passes clicking "N Replies" / "View more replies" buttons to capture nested threads. Captures depth-0 (top-level), depth-1 (replies), and depth-2+ (reply chains). FB's reply button selectors change occasionally — if expansion stops working, the script still captures preview comments from the feed response and any top-level comments that loaded.
- **NixOS:** `better-sqlite3` requires native compilation. On NixOS, you may need `nix-shell -p python3 gcc gnumake` or add the appropriate build inputs.

## Structure

```
├── index.mjs          CLI, browser lifecycle, scroll loop, comment expansion,
│                        SQLite persistence
├── parse.mjs          FB GraphQL response parsers (ported from API Monitor)
├── Containerfile      mcr.microsoft.com/playwright:v1.59.1-noble
├── package.json       playwright pinned to 1.59.1 (must match the image)
├── package-lock.json
└── data/              ← untracked, created at runtime
    ├── posts.db         ← created on first run
    └── session.json     ← created on login
```

> **Status:** these sources are 2026-05 leftovers and are not referenced by any
> module — `hwc.business.datax` was deleted on 2026-08-26. See
> `domains/business/README.md`.

## Changelog

- 2026-05-21: Deleted `shell.nix` (5da97868). The NixOS-laptop Playwright shell
  it provided (added 8b1715d8, pointed at the system chromium in c1723479) is
  gone; use `nix-shell -p` directly.
- 2026-05-21: Login handling reworked across four passes — wait for the
  logged-in UI rather than "password form gone" (c000f1b2), poll for login
  state so passkey redirects survive (a215218e), detect login via the `c_user`
  cookie instead of the DOM (be21c3c0), and drop the manual Enter press
  (c03a3c62). Browser launch switched to `launchPersistentContext` with a
  `--profile` flag (14bb2b86).
- 2026-05-21: Pinned playwright to exactly `1.59.1` in `package.json` and moved
  the Containerfile base image from `v1.49.0-noble` to `v1.59.1-noble` so the
  library and the browser bundle match (96bcad2c).
- 2026-05-11: README last refreshed before this batch.
