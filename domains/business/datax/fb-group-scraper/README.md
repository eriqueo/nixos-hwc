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
fb-group-scraper/
├── index.mjs          CLI, browser lifecycle, scroll loop, comment expansion
├── parse.mjs          FB GraphQL response parsers (ported from API Monitor)
├── Containerfile      Playwright image (pinned to the package.json version)
├── package.json
├── package-lock.json
├── README.md
└── data/              ← created at runtime
    ├── posts.db           on first run
    └── browser-profile/   on --login
```

## Changelog

- 2026-10-05: Added `## Changelog` for Charter Law 12 and corrected `## Structure`
  (no `store.mjs` — persistence lives in `index.mjs`; `Containerfile` and
  `package-lock.json` were missing; `data/` now holds `browser-profile/`, not
  `session.json`). The code changes it had fallen behind, newest first:
  - `5da97868` (2026-05-21) removed the laptop-only `shell.nix` added in `8b1715d8`
    and repointed by `c1723479`.
  - `80d78d4a` (2026-05-21) bumped only `package-lock.json` here; the HWC lead-scoring
    prompt and classifier it carries live in `fb-classifier/`.
  - `b6f1fc59`, `5cf2ab77`, `2d15e31f`, `aa12b637` (2026-05-18/19) reworked `index.mjs`
    under the "jobber mcp" commits (+120/−17 in `aa12b637` alone).
  - `14bb2b86` (2026-05-14) switched to `chromium.launchPersistentContext` with a
    `--profile` directory, replacing the saved `session.json` state file.
  - `c03a3c62`, `c000f1b2`, `a215218e`, `be21c3c0` (2026-05-13/14) made `--login`
    self-detecting: it polls for the `c_user` cookie instead of waiting on DOM state
    or an Enter press, so passkey redirects survive. The **Auth** section above still
    describes the older press-Enter/`session.json` flow.
  - `96bcad2c` (2026-05-13) pinned Playwright 1.59.1 in both `package.json` and the
    `Containerfile` so the image and the dependency match.
