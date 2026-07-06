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
├── index.mjs    CLI, browser lifecycle, scroll loop, comment expansion
├── parse.mjs    FB GraphQL response parsers (ported from API Monitor)
├── store.mjs    SQLite persistence layer
├── classify.py  HWC residential-remodel lead classifier
├── shell.nix    Playwright/Chromium dev shell for NixOS laptop
├── data/
│   ├── posts.db         ← created on first run
│   └── browser-profile/ ← persistent Chromium profile (created on login)
└── package.json
```

## Changelog

- 2026-07-06: Login-detection & session hardening arc — switched to Playwright
  `launchPersistentContext` with a `--profile` flag (replacing the JSON
  `--session`/`session.json` model), detect login via the `c_user` cookie
  rather than fragile DOM checks, plus a run of login-detection fixes. Added
  `shell.nix` (Playwright/Chromium dev shell for the NixOS laptop) and
  repurposed the classifier for **HWC lead scoring**: `classify.py` now emits the
  residential-remodel schema (hot_lead/warm_lead/monitor/competitor with
  project_signal, service_match, urgency, contractor_request, budget_signal,
  sentiment), and a `fbClassifier.promptFile` Nix option (Nix-store-safe path)
  drives `PROMPT_FILE` — the HWC Bozeman prompt itself stays local-only, not
  tracked in git. Playwright pinned to 1.59.1.
