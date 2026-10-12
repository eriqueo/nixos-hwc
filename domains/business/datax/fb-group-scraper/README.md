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
├── index.mjs       CLI, browser lifecycle, login, scroll loop, comment expansion,
│                   SQLite persistence
├── parse.mjs       FB GraphQL response parsers (ported from API Monitor)
├── Containerfile   mcr.microsoft.com/playwright:v1.59.1-noble base image
├── package.json    pins playwright to exactly 1.59.1 (must match the image)
├── package-lock.json
└── README.md
```

`data/posts.db` and the browser profile directory (`data/browser-profile` by default)
are created at runtime and are not tracked.

## Changelog

- 2026-05-21: `shell.nix` removed (`5da97868`) — the NixOS Playwright dev shell that
  pointed at the system chromium (`c1723479`, added `8b1715d8`).
- 2026-05-21: Login flow reworked across `index.mjs`: the browser now starts via
  `launchPersistentContext` with a `--profile` flag (`14bb2b86`); login completion is
  detected from the `c_user` cookie rather than the DOM (`be21c3c0`) after earlier
  passes polled for logged-in UI and tried to survive passkey redirects
  (`a215218e`, `c000f1b2`, `c03a3c62`) — no Enter press is needed. The **Auth**,
  **Usage** and **Options** sections above still describe the retired
  `--session ./data/session.json` state file and the manual Enter step; the CLI now
  takes `--profile <dir>` and persists the whole browser profile.
- 2026-05-21: Playwright pinned to exactly `1.59.1` in `package.json` and the
  Containerfile base image moved `v1.49.0-noble` → `v1.59.1-noble` (`96bcad2c`),
  so the client library and the browser build in the image match.
- 2026-05-21: Structure block corrected — `store.mjs` and `data/` were never tracked
  files here; persistence lives in `index.mjs`.
- 2026-05-21: `index.mjs` project path updated to `300_tech/320_projects` (`b6f1fc59`),
  plus three `jobber mcp` commits (`5cf2ab77`, `2d15e31f`, `aa12b637`) whose messages
  record no detail beyond that.
