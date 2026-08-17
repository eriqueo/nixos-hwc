# fb-group-scraper

Headless Facebook group scraper built on Playwright. Intercepts FB's internal GraphQL API responses during scroll — no DOM parsing, no fragile selectors for post content. Emits posts and comments as **JSON** on stdout (or to `-o <path>`); persistence is the caller's job.

## Setup

```bash
npm install
npx playwright install chromium
```

Or build the image — `Containerfile` is `FROM mcr.microsoft.com/playwright:v1.59.1-noble`,
`npm ci --omit=dev`, entrypoint `node index.mjs`, with `/data` as a volume for the
browser profile.

## Auth

First run requires a one-time interactive login, which saves a **persistent browser
profile** (not a cookie jar):

```bash
node index.mjs --login --headed
```

This opens a browser. Log in to Facebook manually; the profile is written to
`./data/browser-profile` (override with `--profile`) and `--login` then exits.
Subsequent runs reuse the profile headlessly via `launchPersistentContext`.

If the session expires, re-run the login step.

## Usage

```bash
# Scrape 50 posts (default) — JSON to stdout
node index.mjs https://facebook.com/groups/jobtread

# Short form — just the group slug
node index.mjs jobtread -n 100

# Include full comment threads
node index.mjs jobtread -n 50 -d comments

# Write to a file instead of stdout
node index.mjs jobtread -n 50 -d comments -o /tmp/export.json

# Quiet mode (cron-friendly — errors only on stderr)
node index.mjs jobtread -n 100 -q

# Pipe straight into a consumer
node index.mjs jobtread -n 25 | fb-merge /dev/stdin
```

### Options

Mirrors `usage()` in `index.mjs`.

| Flag | Description | Default |
|------|-------------|---------|
| `-n, --posts` | Posts to collect | 50 |
| `-d, --depth` | `posts` or `comments` | posts |
| `-o, --output` | Write JSON to file | stdout |
| `--profile` | Browser profile directory | `./data/browser-profile` |
| `--headed` | Show the browser window | off |
| `--login` | Interactive login — saves profile then exits | — |
| `-q, --quiet` | Suppress progress output (stderr) | off |
| `-h, --help` | Usage | — |

## Cron

```cron
# Every 6 hours, scrape the latest 50 posts
0 */6 * * * cd /path/to/fb-group-scraper && node index.mjs jobtread -n 50 -q >> /var/log/fb-scraper.log 2>&1
```

Each run emits a fresh JSON document. Idempotence is a property of the **consumer**:
post IDs are deterministic (see below), so a merge step can upsert on `post_id` rather
than duplicate. `fb-monitor-bak/merge.py` + `schema.sql` are the reference consumer.

## How It Works

1. Launches Chromium via `launchPersistentContext` against the saved browser profile
2. Navigates to the group feed
3. Hooks `page.on('response')` to intercept FB's GraphQL API calls — same data the Tampermonkey script captures, but via Playwright's network layer instead of fetch/XHR hooks
4. Routes responses by `fb_api_req_friendly_name` — only parses `GroupsCometFeed` for posts, `CometSinglePostDialogContentQuery` for full comments, `CommentsListPaginationQuery` for paginated replies
5. Scrolls with human-like cadence (random distance + delay) to trigger feed loading
6. Optionally navigates to each post URL to expand comments — scrolls the comment section, then multi-pass clicks "N Replies" / "View more replies" buttons to capture nested reply threads
7. Serializes the collected posts + comments as JSON to stdout, or to `--output`

### Post IDs

Posts are identified by FB's canonical post ID extracted from the URL (`/posts/1286089016487814` → `1286089016487814`). Posts without a URL-based ID are skipped — this matches the Tampermonkey script's behavior and ensures stable, deterministic keys. For a consumer that upserts on `post_id`, this means:

- Repeat runs don't create duplicate rows
- Updated engagement numbers (reactions, comment counts) overwrite stale values
- Comments from later runs attach to the original post record

## Consumer schema

The scraper itself owns no database. The shape below is the reference consumer's —
see `../fb-monitor-bak/schema.sql`.

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
- **NixOS:** the only runtime dependency is `playwright` (pinned 1.59.1, matching the
  Containerfile base image) — there is no native module to compile. The `shell.nix`
  that used to live here for that purpose was deleted on 2026-05-21.

## Structure

```
├── index.mjs           CLI, browser lifecycle, scroll loop, comment expansion, JSON output
├── parse.mjs           FB GraphQL response parsers (ported from API Monitor)
├── Containerfile       playwright:v1.59.1-noble base; /data volume for the profile
├── package.json        v2.0.0 — sole dependency: playwright 1.59.1
├── package-lock.json
└── data/               (gitignored, created at runtime)
    └── browser-profile   ← created on --login
```

## Changelog

- 2026-08-17: Law 12 catch-up. The README still documented a SQLite-persisting tool —
  a `store.mjs` module that has never existed in this directory's history, `--db` and
  `--session` flags, and a `better-sqlite3` native-build note. The actual v2.0.0
  `index.mjs` emits JSON to stdout or `-o`, authenticates via a persistent browser
  profile (`--profile`, default `./data/browser-profile`), and lists `playwright` as
  its only dependency. Rewrote Setup/Auth/Usage/Options/Structure against the source
  and reframed the schema section as the consumer's (`../fb-monitor-bak/schema.sql`).
- 2026-05-21: `5da97868` — deleted `shell.nix` (-11), the Playwright-on-NixOS dev shell
  added ten days earlier in `8b1715d8`.
- 2026-05-15: `80d78d4a` — `package-lock.json` touched in passing by the HWC lead-scoring
  change (new prompt + classifier); no scraper behaviour change.
- 2026-05-11: `14bb2b86` — switched to `launchPersistentContext` with a `--profile` flag
  (+33/-53), replacing the saved-cookie session model. `96bcad2c` pinned playwright to
  1.59.1 in both `package.json` and the `Containerfile` so image and lockfile agree.
  `be21c3c0`, `a215218e`, `c000f1b2`, `c03a3c62` iterated on login detection in the same
  window — settling on the `c_user` cookie rather than DOM state, and polling so a
  passkey redirect does not abort the login.
