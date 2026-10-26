# fb-group-scraper

Headless Facebook group scraper built on Playwright. Intercepts FB's internal GraphQL API responses during scroll — no DOM parsing, no fragile selectors for post content. Emits one JSON document per run (stdout or `--output`); it does not persist anything itself.

## Setup

```bash
npm install
npx playwright install chromium
```

Playwright is pinned to **1.59.1** to match the `mcr.microsoft.com/playwright:v1.59.1-noble`
base image in `Containerfile`; the container is the supported run environment.

## Auth

The browser runs from a **persistent Chromium profile** (`launchPersistentContext`), so the
login survives between runs. One interactive login is required first:

```bash
node index.mjs --login --headed
```

This opens a browser. Log in to Facebook manually — including a passkey prompt. The script
polls for the `c_user` cookie and saves the profile as soon as that appears; no Enter press,
and no DOM check that a redirect could break. Later runs reuse the profile headlessly.

If the login lapses, the run exits with `Not logged in. Run with --login --headed first.`

## Usage

```bash
# Scrape 50 posts (default) → JSON on stdout
node index.mjs https://facebook.com/groups/jobtread

# Short form — just the group slug
node index.mjs jobtread -n 100

# Include full comment threads, write to a file
node index.mjs jobtread -n 50 -d comments -o /tmp/export.json

# Quiet mode (cron-friendly — errors and summary only)
node index.mjs jobtread -n 100 -q

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
| `--login` | Interactive login mode | — |
| `-q, --quiet` | Suppress progress output (stderr) | off |

## Cron

```cron
# Every 6 hours, scrape the latest 50 posts
0 */6 * * * cd /path/to/fb-group-scraper && node index.mjs jobtread -n 50 -q -o /var/lib/fb-scraper/latest.json 2>> /var/log/fb-scraper.log
```

Each run is self-contained: it emits whatever it saw this run. Dedup and merge across runs is
the consumer's job (`fb-merge` reads the JSON on stdin), keyed on the stable `postId`.

## How It Works

1. Launches Chromium against the persistent profile directory (cookies included)
2. Navigates to the group feed
3. Hooks `page.on('response')` to intercept FB's GraphQL API calls — same data the Tampermonkey script captures, but via Playwright's network layer instead of fetch/XHR hooks
4. Routes responses by `fb_api_req_friendly_name` — only parses `GroupsCometFeed` for posts, `CometSinglePostDialogContentQuery` for full comments, `CommentsListPaginationQuery` for paginated replies
5. Scrolls with human-like cadence (random distance + delay) to trigger feed loading
6. Optionally navigates to each post URL to expand comments — scrolls the comment section, then multi-pass clicks "N Replies" / "View more replies" buttons to capture nested reply threads
7. Serializes everything it collected to one JSON document

### Post IDs

Posts are identified by FB's canonical post ID extracted from the URL (`/posts/1286089016487814` → `1286089016487814`). Posts without a URL-based ID are skipped — this matches the Tampermonkey script's behavior and gives the consumer a stable, deterministic key to merge on across runs.

## Output

One JSON object per run:

```json
{
  "_meta": {
    "tool": "fb-group-scraper",
    "version": "2.0.0",
    "capturedAt": "2026-05-21T12:00:00.000Z",
    "source": "https://www.facebook.com/groups/jobtread",
    "postCount": 50,
    "totalComments": 312,
    "expandedPosts": 50
  },
  "posts": [
    {
      "postId": "1286089016487814",
      "body": "…",
      "author": "…",
      "source": "…",
      "url": "https://www.facebook.com/groups/jobtread/posts/1286089016487814",
      "timestamp": "2026-05-20T18:03:00.000Z",
      "commentCount": 7,
      "commentsExpanded": true,
      "comments": [
        { "author": "…", "body": "…", "depth": 0, "timestamp": "2026-05-20T19:10:00.000Z" }
      ]
    }
  ]
}
```

Timestamps are ISO-8601 (FB's epoch seconds are converted on the way out). `depth` tracks
comment nesting: 0 = top-level, 1 = reply, 2 = reply-to-reply, etc.

## Notes

- **Anti-detection:** The script uses a standard Chromium instance with `AutomationControlled` disabled and human-like scroll pacing. For heavier use, consider adding [playwright-extra](https://github.com/nickreese/playwright-extra) with the stealth plugin.
- **Rate limiting:** The scroll loop pauses longer after consecutive empty scrolls. The comment expansion pass waits between navigations. Adjust `SCROLL` constants in `index.mjs` if needed.
- **Session expiry:** FB logins typically last weeks but can lapse sooner. The script checks for the `c_user` cookie before scraping and exits with a clear message.
- **Comment depth:** The `comments` mode scrolls each post's comment section, then runs up to 5 passes clicking "N Replies" / "View more replies" buttons to capture nested threads. Captures depth-0 (top-level), depth-1 (replies), and depth-2+ (reply chains). FB's reply button selectors change occasionally — if expansion stops working, the script still captures preview comments from the feed response and any top-level comments that loaded.
- **NixOS:** there are no native dependencies left — `playwright` is the only dependency. Run
  it in the `Containerfile` image, or set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to a system
  Chromium (the script honours that variable) instead of Playwright's downloaded browser.

## Structure

```
fb-group-scraper/
├── index.mjs           # CLI, browser lifecycle, scroll loop, comment expansion, JSON emit
├── parse.mjs           # FB GraphQL response parsers (ported from API Monitor)
├── Containerfile       # playwright:v1.59.1-noble image; ENTRYPOINT node index.mjs; VOLUME /data
├── package.json        # v2.0.0; single dependency playwright 1.59.1; login/scrape scripts
├── package-lock.json
├── README.md           # This file
└── data/               # created at runtime
    └── browser-profile/    ← persistent Chromium profile, written by --login
```

## Changelog

- 2026-05-21: Removed `shell.nix`. The dev shell exported
  `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`/`PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS` for a
  laptop Playwright run; the `Containerfile` image is the supported environment and `index.mjs`
  still honours the executable-path variable directly.
- 2026-05-13: `index.mjs` reworked across four commits (`aa12b637`, `2d15e31f`, `5cf2ab77`,
  `b6f1fc59`) — this is the v2.0.0 shape the docs above now describe: **no SQLite layer**. The
  `store.mjs` persistence module, `--db`/`--session` flags and the `posts`/`comments` tables are
  gone; the run emits one JSON document (`_meta` + `posts[]`, ISO-8601 timestamps) to stdout or
  `-o/--output`, and merging across runs belongs to the consumer. Project path references moved
  to `300_tech/320_projects`.
- 2026-05-11: Switched to `launchPersistentContext` with a `--profile` directory instead of a
  saved `session.json` state file, and login completion is detected by polling for the `c_user`
  cookie rather than inspecting the DOM — passkey redirects used to defeat the DOM check.
  Playwright pinned to 1.59.1 in `package.json` and `Containerfile` so the library and the
  image's bundled Chromium match.
