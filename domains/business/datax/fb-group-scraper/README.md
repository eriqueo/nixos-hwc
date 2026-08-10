# fb-group-scraper

Headless Facebook group scraper built on Playwright. Intercepts FB's internal GraphQL API responses during scroll — no DOM parsing, no fragile selectors for post content. Emits a JSON document of posts and comments (stdout, or `-o <path>`) with deterministic post IDs so downstream ingestion can dedup across runs.

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

This opens a browser. Log in to Facebook manually; login completion is auto-detected via the `c_user` cookie (no Enter press) and the browser profile is saved to `./data/browser-profile`. Subsequent runs reuse that persistent profile headlessly.

If the profile stops authenticating (`Not logged in. Run with --login --headed first.`), re-run the login step.

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

# Write JSON to a file instead of stdout, custom profile dir
node index.mjs jobtread -o /tmp/export.json --profile ./mydata/browser-profile
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-n, --posts` | Number of posts to collect | 50 |
| `-d, --depth` | `posts` or `comments` | posts |
| `-o, --output` | Write JSON to file | stdout |
| `--profile` | Browser profile directory | `./data/browser-profile` |
| `--headed` | Show the browser window | off |
| `--login` | Interactive login mode | — |
| `-q, --quiet` | Minimal output | off |

## Cron

```cron
# Every 6 hours, scrape the latest 50 posts
0 */6 * * * cd /path/to/fb-group-scraper && node index.mjs jobtread -n 50 -q >> /var/log/fb-scraper.log 2>&1
```

Each run is a fresh capture keyed by stable post IDs, so a downstream upsert (same ID → update engagement numbers, attach new comments) is idempotent across runs.

## How It Works

1. Launches Chromium with saved session cookies
2. Navigates to the group feed
3. Hooks `page.on('response')` to intercept FB's GraphQL API calls — same data the Tampermonkey script captures, but via Playwright's network layer instead of fetch/XHR hooks
4. Routes responses by `fb_api_req_friendly_name` — only parses `GroupsCometFeed` for posts, `CometSinglePostDialogContentQuery` for full comments, `CommentsListPaginationQuery` for paginated replies
5. Scrolls with human-like cadence (random distance + delay) to trigger feed loading
6. Optionally navigates to each post URL to expand comments — scrolls the comment section, then multi-pass clicks "N Replies" / "View more replies" buttons to capture nested reply threads
7. Serializes everything to one JSON document (`_meta` + `posts[]`) on stdout or `-o <path>`

### Post IDs

Posts are identified by FB's canonical post ID extracted from the URL (`/posts/1286089016487814` → `1286089016487814`). Posts without a URL-based ID are skipped — this matches the Tampermonkey script's behavior and ensures stable, deterministic keys. This means:

- Repeat runs don't create duplicate rows
- Updated engagement numbers (reactions, comment counts) overwrite stale values
- Comments from later runs attach to the original post record

## Output shape

```json
{
  "_meta": {
    "tool": "fb-group-scraper", "version": "2.0.0",
    "capturedAt": "…", "source": "…",
    "postCount": 50, "totalComments": 412, "expandedPosts": 50
  },
  "posts": [
    {
      "postId": "1286089016487814",
      "body": "…", "author": "…", "source": "…", "url": "…",
      "timestamp": "…ISO8601…",
      "commentCount": 12, "commentsExpanded": true,
      "comments": [ { "author": "…", "body": "…", "depth": 0, "timestamp": "…" } ]
    }
  ]
}
```

`depth` tracks comment nesting: 0 = top-level, 1 = reply, 2 = reply-to-reply, etc.

## Notes

- **Anti-detection:** The script uses a standard Chromium instance with `AutomationControlled` disabled and human-like scroll pacing. For heavier use, consider adding [playwright-extra](https://github.com/nickreese/playwright-extra) with the stealth plugin.
- **Rate limiting:** The scroll loop pauses longer after consecutive empty scrolls. The comment expansion pass waits between navigations. Adjust `SCROLL` constants in `index.mjs` if needed.
- **Session expiry:** FB sessions typically last weeks but can expire sooner. The auth check reads the `c_user` cookie (not the DOM) and exits with a clear message.
- **Comment depth:** The `comments` mode scrolls each post's comment section, then runs up to 5 passes clicking "N Replies" / "View more replies" buttons to capture nested threads. Captures depth-0 (top-level), depth-1 (replies), and depth-2+ (reply chains). FB's reply button selectors change occasionally — if expansion stops working, the script still captures preview comments from the feed response and any top-level comments that loaded.
- **Container:** `Containerfile` builds on `mcr.microsoft.com/playwright:v1.59.1-noble` — the image tag and the `playwright` dependency are pinned to the same version on purpose; bump them together.

## Structure

```
├── index.mjs           CLI, browser lifecycle, scroll loop, comment expansion, JSON export
├── parse.mjs           FB GraphQL response parsers (ported from API Monitor)
├── Containerfile       Podman image (playwright v1.59.1-noble base, VOLUME /data)
├── package.json        pinned playwright 1.59.1
├── package-lock.json
└── data/
    └── browser-profile/  ← created on --login (untracked)
```

## Changelog

- 2026-08-10: Doc-only correction. This file described a SQLite/`store.mjs`
  persistence layer, `--db`/`--session` flags and a `posts`/`comments` table
  schema — none of which exist in the tracked source; the tool writes one JSON
  document. Usage, Structure and the schema section now match `index.mjs`.
- 2026-05-21: Dropped the laptop-only `shell.nix` (5da97868).
- 2026-05-11: v2 auth rework — `launchPersistentContext` + `--profile` replace
  `storageState` + `--session` (14bb2b86); login completion auto-detected via the
  `c_user` cookie instead of DOM probing, surviving passkey redirects (c03a3c62,
  c000f1b2, a215218e, be21c3c0); playwright pinned to 1.59.1 to match the
  container image tag (96bcad2c).
- 2026-05-11: Initial import — Podman + Postgres + systemd timer (499286ec).
