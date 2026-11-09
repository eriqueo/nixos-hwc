# fb-group-scraper

Headless Facebook group scraper built on Playwright. Intercepts FB's internal GraphQL API responses during scroll — no DOM parsing, no fragile selectors for post content. Stores posts and comments in SQLite with deterministic IDs for dedup across runs.

## Setup

```bash
npm install
npx playwright install chromium
```

## Auth

First run requires a one-time interactive login into a persistent browser profile:

```bash
node index.mjs --login --headed
```

This opens Chromium with `launchPersistentContext` on `./data/browser-profile`. Log in to Facebook (passkeys work). The script polls every 2 seconds for the `c_user` cookie and saves the profile when it appears; no Enter press is needed. Subsequent runs reuse the profile headlessly.

A scrape checks for the `c_user` cookie first. Without it the script exits with "Not logged in. Run with --login --headed first."; re-run the login step.

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
node index.mjs jobtread -o ./mydata/jt.json --profile ./mydata/browser-profile
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

Each run is idempotent — posts with the same ID are updated (engagement numbers), not duplicated. New comments attach to existing posts.

## How It Works

1. Launches Chromium on the persistent browser profile
2. Navigates to the group feed
3. Hooks `page.on('response')` to intercept FB's GraphQL API calls — same data the Tampermonkey script captures, but via Playwright's network layer instead of fetch/XHR hooks
4. Routes responses by `fb_api_req_friendly_name` — only parses `GroupsCometFeed` for posts, `CometSinglePostDialogContentQuery` for full comments, `CommentsListPaginationQuery` for paginated replies
5. Scrolls with human-like cadence (random distance + delay) to trigger feed loading
6. With `-d comments`, clicks each post's link in the feed to open its dialog and waits for `CometSinglePostDialogContentQuery` to fire (headless FB renders no `role="dialog"`). Dialog scrolling and multi-pass "N Replies" / "View more replies" clicks run only when a dialog overlay is present (headed mode). Posts not found in the DOM are skipped
7. Writes the collected posts as JSON to stdout or `-o <path>`

### Post IDs

Posts are identified by FB's canonical post ID extracted from the URL (`/posts/1286089016487814` → `1286089016487814`). Posts without a URL-based ID are skipped — this matches the Tampermonkey script's behavior and ensures stable, deterministic keys. This means:

- Repeat runs don't create duplicate rows
- Updated engagement numbers (reactions, comment counts) overwrite stale values
- Comments from later runs attach to the original post record

## Schema

> Unverified: this section and "Cron" describe a SQLite store (`store.mjs`,
> `--db`). No `store.mjs` exists in this directory, and the current `index.mjs`
> only writes JSON.

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
├── Containerfile      Playwright v1.59.1-noble image; ENTRYPOINT node index.mjs
├── index.mjs          CLI, browser lifecycle, scroll loop, comment expansion, JSON export
├── parse.mjs          FB GraphQL response parsers (ported from API Monitor)
├── package.json       playwright pinned to 1.59.1
├── package-lock.json
├── README.md
└── data/
    └── browser-profile/   ← created on login (not tracked)
```

## Changelog

- 2026-11-04: `index.mjs` and `parse.mjs` hoist fixed regexes to module scope
  (68ff8eda). No behavior change intended.
- 2026-05-21: Removed `shell.nix` (5da97868).
- 2026-05-15: `package-lock.json` updated (80d78d4a).
- 2026-05-13: Comment mode opens each post by clicking its feed link and waits
  for the dialog query signal; scroll/reply expansion runs only when a dialog
  overlay exists (5cf2ab77, 2d15e31f, aa12b637, b6f1fc59 — commit titles say
  "jobber mcp"; behavior is taken from the diff).
- 2026-05-11: Login moved from `storageState` (`--session`, Enter prompt) to a
  persistent profile (`--profile`, `launchPersistentContext`) with `c_user`
  cookie polling. Playwright pinned to 1.59.1 in `package.json` and the
  Containerfile image. `shell.nix` added for laptop login (later removed).
