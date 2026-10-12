# domains/media/youtube/

## Purpose

YouTube transcript extraction for the media library: one FastAPI service
(`transcripts`) with a web UI at `transcripts.hwc.iheartwoodcraft.com`.
Captions come from youtube-transcript-api, then yt-dlp subtitles; when neither
works (no captions, or YouTube blocking this server's IP) a job falls back to
transcribing the audio with the local whisper-server.

The same service saves X (Twitter) posts. Paste a post URL and choose an
**X capture** mode (`x_mode` on `POST /job` and `POST /xpost`):

| Mode | Saves | Login |
|------|-------|-------|
| `post` | the post and the author's thread above it | no |
| `thread` | the author's thread above and below the post | yes |
| `replies` | the post and its direct replies, X's ranking, top `limit` (default 200, max 1000) | yes |
| `author_replies` | the post and every other post by its author in the conversation | yes |

Each mode is its own file (key `x:<id>` for `post`, `x:<id>:<mode>`
otherwise), so a post and its replies dedup separately. A replies file states
its coverage, e.g. `Replies (200 of 1,146; limit reached)`. `POST /xpost`
returns the same data as JSON and writes nothing.

Every mode except `post` needs an X login: logged out, X
shows only 3 replies and no next page. The "X login" card imports a spare
account's x.com cookies (cookies.txt or JSON export) into a headless Chromium
profile (`xbrowser.py`), which opens the post, scrolls, and reads X's own
`TweetDetail` responses. Direct API calls are not used: X signs them with an
`x-client-transaction-id` its client generates. `GET /x/session` and
`/health` report the login; captures fail as `login_required` when it lapses.

Non-English posts are saved in English only. X's own `lang` tag picks them
(including quoted posts); DX2 translates them in batches, 4 requests at a
time, before the file is written, so titles and filenames are English too. The
header says what happened, e.g. `**Translated:** to English from zh by DX2
(5 texts)`. A failed request keeps its posts in the original language and the
header counts them. `translate.enable` (default: on wherever
`hwc.server.ai.dx2` is imported) controls it; `POST /xpost` is not translated.

## Boundaries

- **Manages**: the `transcripts` systemd unit, its save-location whitelist (`outputRoots`), the `n8n-transcript-extract` helper, the Whisper-fallback wiring, the DX2 translation wiring
- **Does NOT manage**: whisper-server itself (-> `domains/server/native/ai/whisper`), media library directories other than `outputDirectory` (-> `domains/media/directories.nix`), the Caddy vhost (-> `domains/networking/routes.nix`)

## Structure

```
domains/media/youtube/
├── README.md                 # This file
├── index.nix                 # hwc.media.youtube.transcripts.* options
└── parts/transcripts/
    └── default.nix           # systemd unit, wrapper env, n8n helper, assertions

workspace/media/youtube-services/   # runtime source, read from the checkout (paths.nixos)
├── api.py                    # FastAPI: /job, /job/{id}, /job/{id}/retry, /transcript, /xpost, /x/session, /config, /health, UI; saved-file scan
├── transcript.py             # caption sources, Whisper fallback, failure reasons, cleaning, markdown
├── xpost.py                  # X posts: syndication + guest GraphQL fetch, thread walk, TweetDetail parser, modes, DX2 translation, markdown
├── xbrowser.py               # logged-in X capture: Playwright profile, scroll loop, cookie import
├── fixtures/                 # trimmed real TweetDetail response for parser tests
├── test_transcript.py        # unittest: reasons, Whisper decision, dedup, retry, library contract, X posts, capture loop
└── pyproject.toml
```

## Configuration

```nix
hwc.media.youtube.transcripts = {
  enable = true;
  port = 8100;
  outputDirectory = "/mnt/media/transcripts";
  whisper.enable = true;        # default: follows hwc.server.ai.whisper.enable
  whisper.maxDuration = 10800;  # seconds; longer videos fail as too_long
};
```

Each failed video reports one reason: `rate_limited`, `no_captions`,
`unavailable`, `invalid_url`, `whisper_failed`, `too_long`, `timeout`, `error`.
Whisper output carries `**Source:** Whisper ...` in the file and a Whisper
badge in the UI. `POST /transcript` is synchronous and never uses Whisper.

Idempotent by video ID: before fetching, a job scans every save location's
`.md` headers (`saved_video_id`, the inverse of `format_markdown`) and returns
an already-saved video as `status: "exists"` instead of fetching it again; the
"Re-extract" checkbox (`force`) overrides. `POST /job/{id}/retry` re-runs a
finished job's failed items into their original folders.

Tests (run on hwc-home with the service interpreter):
`PYTHONPATH=<wrapper PYTHONPATH>:. python3 -m unittest -v test_transcript`

## Services

| Service | Port | Description |
|---------|------|-------------|
| `transcripts` | 8100 | Transcript API + web UI |

## Changelog
- 2026-10-12: English translation of X posts. Posts carry X's `lang` tag; `xpost.translate_posts` sends every non-English text (and quoted text) to DX2 through `xpost.dx2_translator` (OpenAI-compatible, thinking off, key read per request from `hwc.server.ai.dx2.apiKeyFile`) and replaces it with English before the file is written. Fail-open per request; the new `**Translated:**` header line records languages, count and failures. New option `translate.enable`, asserted to need the dx2 module. The translator lives in `xpost.py`, not a new file: it acts only on the X post shape, and `transcript.py` is the YouTube side.
- 2026-10-12: X capture stop rule. A capture ends only on X's bottom `TimelineTerminateTimeline` (`Conversation.ended`), not on a page without a Bottom cursor; while X has not ended the timeline it waits up to 12 stale scrolls (was 4). Measured live: X sends a page every 3-7 s, and the old rule saved 60 of ~400 replies as if complete.
- 2026-10-12: X capture modes end to end. `POST /job` and `POST /xpost` take `x_mode` (`post`, `thread`, `replies`, `author_replies`) and `limit`; `api._fetch_x` dispatches `post` to the logged-out walk and the rest to `xbrowser.capture`. Jobs, in-flight checks, dedup and retry key X items by `xpost.x_key(id, mode)`, and retry replays mode and limit. The UI gains an "X capture" select (labels from `xpost.X_MODE_LABELS` via `/config`) and a replies limit. Saved titles name the mode; replies files state coverage. Gate passed before the build: a logged-in `replies` capture of poteto's post under the unit's sandbox returned 204 direct replies.
- 2026-10-11: X login and capture groundwork. New `xbrowser.py` drives headless Chromium (`playwright`, browsers from `playwright-driver.browsers`) with a profile at `/var/lib/hwc/transcripts/x-profile`; `GET/POST /x/session` and a UI card import a spare account's cookies and prove them by loading x.com/home. `xpost.py` gains a parser for logged-in `TweetDetail` responses (promoted posts dropped) and the selectors for direct replies, the author's thread below a post, and the author's posts in a conversation; saved X files now carry a `**Mode:**` line (files without one stay `post`). New failure reason `login_required`. The unit sets `HOME` to its state directory (Chromium needs a writable home; `ProtectHome` keeps `/home` read-only) and `StateDirectoryMode = "0700"` because the profile holds a login. Verified: Chromium runs under the unit's sandbox via `systemd-run` with the same properties, and loads x.com with HTTP 200.
- 2026-10-11: X posts. A post URL in the job box (or `POST /transcript`) saves the post as Markdown, with the author's thread above it, long-form text, media links, quoted post and stats. New `xpost.py` ports the fetch engine of github.com/itsbigdill/x-post-to-json: public syndication endpoint, then guest-token GraphQL for full text and metrics (best effort). New `POST /xpost` returns the thread as JSON. The saved-file scan keys X files as `x:<post id>` next to video IDs, so dedup, in-flight checks and retry cover both. Failure texts for `unavailable` and `invalid_url` no longer say "video"/"YouTube"; the reason codes are unchanged.
- 2026-10-06: Whisper segments that continue the previous word (no leading space, e.g. "Cl" + "oning") are joined to it instead of becoming their own segment, which had produced "Cl oning" and "you 're" in output.
- 2026-10-06: Whisper fallback downloads the best audio track (`WHISPER_AUDIO_FORMAT`), not the worst. The 52 kbps track (format 249) produced fluent nonsense on both GPU and CPU; the 125 kbps track of the same minute matched the captions nearly word for word. Every Whisper transcript made before this change is unreliable.
- 2026-10-06: Retry and duplicate check. A finished job with failures shows "Retry failed (N)", which calls the new `POST /job/{id}/retry`; the failed items' folders and playlists are held server-side (newest 200 jobs kept), so a retry never takes a save path from the browser. Jobs and `POST /transcript` now skip videos already saved anywhere under the save locations, keyed on the video ID in each file's header (both the current `**URL:**` and the older `- **URL**:` format); a "Re-extract" checkbox overrides. The same video listed twice in a batch runs once, and a video being extracted by another job is not started again. Fixed a silent overwrite: two different videos with the same title on the same day wrote the same file; the second now gets ` [videoid]` appended. Files are written to a temp name and renamed. Also: yt-dlp's "This video is unavailable" was classified as `error`; it is now `unavailable`.
- 2026-10-06: Transcripts recover from failures instead of hiding them. (1) The youtube-transcript-api 1.2 upgrade had removed `list_transcripts`, so the primary caption source failed on every video and a bare `except` hid it; every success came from the yt-dlp fallback, which YouTube answers with 429 for many videos. Now on the 1.x instance API. (2) Failures carry one reason from a closed vocabulary (`TranscriptError`), shown in the UI and logged per source. (3) A blocked caption request is retried once after 10 s, a 429 starts a process-wide 20 s cooldown, and job videos are paced 2 s apart. (4) New Whisper fallback (`whisper.enable`, `whisper.maxDuration`): yt-dlp audio -> ffmpeg 180 s chunks -> local whisper-server, so the shared server is held per chunk, not per video. Subprocesses are killed on timeout. Rewrote this README's Structure/Configuration/Services, which still described the removed PostgreSQL/worker design, and deleted the obsolete `DEPLOYMENT.md`.
- 2026-09-10: `parts/transcripts/default.nix` no longer creates every `outputRoot`, only its own `outputDirectory` (`/mnt/media/transcripts`). The other root it writes to, `/mnt/media/youtube`, is a shared library directory that pinchflat also uses, and all three modules were declaring it — this one as `eric users`, pinchflat as `1000 100`. The same identity spelled two ways, resolved by whichever tmpfiles rule systemd applied last. It now comes from `domains/media/directories.nix`, which owns media library paths. `ReadWritePaths` still covers every root: writability is this service's concern, existence is the owner's. **Adding a new `outputRoot` now requires adding it to `directories.nix` as well** — it will not be created from here, and the service will fail to write to a path that does not exist.
- 2026-08-06: Transcripts UI v4 — multi-box URL input (`+ URL` / remove rows, no more comma/newline paste), playlist URLs expand (`fetch_playlist` via `yt-dlp --flat-playlist`) with each playlist saved to its own titled subfolder, and a save-location picker: new `outputRoots` option is a whitelist of base dirs (default `<media.root>/transcripts` + `media.youtube`) surfaced as a UI dropdown + free-text subfolder. `ReadWritePaths`/tmpfiles now derive from `outputRoots` (was single `outputDirectory`); base is validated against the whitelist and the subfolder is sanitized so no path escapes its root. `fetch_transcript` retries once on the intermittent datacenter-IP rate-limit. New `/config` endpoint feeds the dropdown; `/transcript` (n8n) unchanged.
- 2026-08-06: Renamed the transcript service `yt-transcripts-api` → `transcripts` everywhere — systemd unit (`transcripts.service`), StateDirectory (`hwc/transcripts`), parts folder (`parts/transcripts/`), and the Caddy vhost (now `transcripts.hwc.iheartwoodcraft.com`). Old empty StateDirectory `hwc/yt-transcripts-api` orphaned. Loopback :8100 unchanged, so n8n callers unaffected.
- 2026-07-11: `transcripts.outputDirectory` default is now `${config.hwc.paths.media.root}/transcripts` — the dead `/mnt/media` fallback removed (media.root is non-null on every server-role host that imports this domain). Law 3 migration, value unchanged.

- 2026-03-26: Workspace source moved from workspace/youtube-services/ to workspace/media/youtube-services/ (domain alignment); all nix refs updated
- 2026-03-04: Namespace migration hwc.server.native.youtube.* → hwc.media.youtube.*
- 2026-02-27: Initial domain creation with legacy API, transcripts API, and videos API
