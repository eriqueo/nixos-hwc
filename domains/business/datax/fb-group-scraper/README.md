# fb-group-scraper

Headless Facebook group scraper built on Playwright. Intercepts FB's internal GraphQL API responses during scroll — no DOM parsing, no fragile selectors for post content. Emits one JSON document of posts (and optionally comment threads) to stdout or a file; persistence is the caller's job.

## Setup

```bash
npm install            # playwright 1.59.1, pinned to match the container image
npx playwright install chromium
```

The tracked `Containerfile` builds on `mcr.microsoft.com/playwright:v1.59.1-noble`
and uses Playwright's bundled Chromium (`PLAYWRIGHT_BROWSERS_PATH=/ms-playwright`).

## Auth

First run requires a one-time interactive login, which saves a **persistent browser
profile** (not a cookie jar):

```bash
node index.mjs --login --headed
```

This opens a browser. Log in to Facebook manually — the script polls for the
`c_user` cookie and exits on its own once login completes, so there is no Enter
press and passkey redirects don't break it. The profile is written to
`./data/browser-profile` (override with `--profile`) and reused headlessly
afterwards via `chromium.launchPersistentContext`.

If the profile goes stale, the next run dies with `Not logged in. Run with --login
--headed first.` — re-run the login step.

## Usage

```bash
# Scrape 50 posts (default), JSON to stdout
node index.mjs https://facebook.com/groups/jobtread

# Short form — just the group slug
node index.mjs jobtread -n 100

# Include full comment threads
node index.mjs jobtread -n 50 -d comments

# Quiet mode (cron-friendly — errors and summary only)
node index.mjs jobtread -n 100 -q

# Write to a file, or pipe onward
node index.mjs jobtread -n 50 -d comments -o /tmp/export.json
node index.mjs jobtread -n 25 | fb-merge /dev/stdin

# Custom profile directory
node index.mjs jobtread --profile ./mydata/browser-profile
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-n, --posts` | Number of posts to collect | 50 |
| `-d, --depth` | `posts` or `comments` | posts |
| `-o, --output` | Write JSON to this path | stdout |
| `--profile` | Browser profile directory | `./data/browser-profile` |
| `--headed` | Show the browser window | off |
| `--login` | Interactive login — saves the profile, then exits | — |
| `-q, --quiet` | Suppress progress output (stderr) | off |

## Cron

```cron
# Every 6 hours, scrape the latest 50 posts into a dated export
0 */6 * * * cd /path/to/fb-group-scraper && node index.mjs jobtread -n 50 -q -o /var/lib/fb-scraper/$(date +\%s).json >> /var/log/fb-scraper.log 2>&1
```

Each run is a fresh export keyed on FB's canonical post IDs, so a downstream
consumer can dedup/merge deterministically across runs — the scraper itself keeps
no state beyond the browser profile.

## How It Works

1. Launches Chromium with saved session cookies
2. Navigates to the group feed
3. Hooks `page.on('response')` to intercept FB's GraphQL API calls — same data the Tampermonkey script captures, but via Playwright's network layer instead of fetch/XHR hooks
4. Routes responses by `fb_api_req_friendly_name` — only parses `GroupsCometFeed` for posts, `CometSinglePostDialogContentQuery` for full comments, `CommentsListPaginationQuery` for paginated replies
5. Scrolls with human-like cadence (random distance + delay) to trigger feed loading
6. Optionally navigates to each post URL to expand comments — waits for the
   `CometSinglePostDialogContentQuery` handler signal (headless FB never adds
   `role="dialog"`), scrolls the comment section when the overlay is actually
   present, then multi-pass clicks "N Replies" / "View more replies" buttons to
   capture nested reply threads
7. Serializes everything to JSON (stdout or `--output`)

### Post IDs

Posts are identified by FB's canonical post ID extracted from the URL (`/posts/1286089016487814` → `1286089016487814`). Posts without a URL-based ID are skipped — this matches the Tampermonkey script's behavior and ensures stable, deterministic keys. This means:

- Repeat runs don't create duplicate rows
- Updated engagement numbers (reactions, comment counts) overwrite stale values
- Comments from later runs attach to the original post record

## Output shape

```json
{
  "_meta": {
    "tool": "fb-group-scraper",
    "version": "2.0.0",
    "capturedAt": "2026-05-21T18:00:00.000Z",
    "source": "https://facebook.com/groups/jobtread",
    "postCount": 50,
    "totalComments": 412,
    "expandedPosts": 50
  },
  "posts": [
    {
      "postId": "1286089016487814",
      "body": "…",
      "author": "…",
      "source": "…",
      "url": "https://facebook.com/groups/jobtread/posts/1286089016487814",
      "timestamp": "2026-05-20T14:22:00.000Z",
      "commentCount": 17,
      "commentsExpanded": true,
      "comments": [
        { "author": "…", "body": "…", "depth": 0, "timestamp": "…" }
      ]
    }
  ]
}
```

`depth` tracks comment nesting: 0 = top-level, 1 = reply, 2 = reply-to-reply, etc.
Timestamps are ISO-8601 (FB's epoch seconds converted at export).

## Notes

- **Anti-detection:** The script uses a standard Chromium instance with `AutomationControlled` disabled and human-like scroll pacing. For heavier use, consider adding [playwright-extra](https://github.com/nickreese/playwright-extra) with the stealth plugin.
- **Rate limiting:** The scroll loop pauses longer after consecutive empty scrolls. The comment expansion pass waits between navigations. Adjust `SCROLL` constants in `index.mjs` if needed.
- **Session expiry:** FB sessions typically last weeks but can expire sooner. The script detects this (no `c_user` cookie in the persistent profile) and exits with a clear message.
- **Comment depth:** The `comments` mode scrolls each post's comment section, then runs up to 5 passes clicking "N Replies" / "View more replies" buttons to capture nested threads. Captures depth-0 (top-level), depth-1 (replies), and depth-2+ (reply chains). FB's reply button selectors change occasionally — if expansion stops working, the script still captures preview comments from the feed response and any top-level comments that loaded.
- **NixOS:** `playwright` is the only dependency and needs no native compilation. For
  the interactive login on a NixOS host, run it in the container (`Containerfile`) or
  point Playwright at a system Chromium — the `shell.nix` that used to live here was
  deleted 2026-05-21.

## Structure

```
domains/business/datax/fb-group-scraper/
├── index.mjs           CLI, browser lifecycle, scroll loop, comment expansion, JSON export
├── parse.mjs           FB GraphQL response parsers (ported from API Monitor)
├── package.json        playwright 1.59.1 (pinned to the image), npm scripts
├── package-lock.json
├── Containerfile       mcr.microsoft.com/playwright:v1.59.1-noble, entrypoint index.mjs
├── README.md
└── data/               (runtime, untracked)
    └── browser-profile/    ← created on --login
```

## Changelog

- 2026-05-21: Deleted `shell.nix` (the Playwright-on-NixOS dev shell). The NixOS
  note above no longer points at it (`5da97868`).
- 2026-05-13: Comment expansion scoped to the `role=dialog` element, and the dialog
  readiness check moved onto the `CometSinglePostDialogContentQuery` handler signal
  because headless FB never adds `role="dialog"` (`b6f1fc59`, `5cf2ab77`, `2d15e31f`,
  `aa12b637` — the last three committed as "jobber mcp", which does not describe them).
- 2026-05-11: Login reworked and this README fell behind it. `index.mjs` switched to
  `chromium.launchPersistentContext` with a `--profile` flag, replacing the
  `./data/session.json` cookie jar; login is detected by polling for the `c_user`
  cookie rather than the DOM, which survives passkey redirects and needs no Enter
  press. Playwright pinned to 1.59.1 to match the container image (`14bb2b86`,
  `be21c3c0`, `a215218e`, `c000f1b2`, `c03a3c62`, `96bcad2c`).
- 2026-05-11: Structure/Usage/Schema corrected on 2026-10-19 — this README had still
  documented a `store.mjs` SQLite persistence layer with `--db`/`--session` flags and
  a `posts`/`comments` table schema. No such file or flags exist in `index.mjs` (v2.0.0
  writes one JSON document to stdout or `--output`); when the SQLite layer was dropped
  is not recoverable from this directory's history, so that removal is recorded here
  as **unverified** rather than dated.
