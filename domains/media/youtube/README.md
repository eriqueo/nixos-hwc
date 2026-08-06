# domains/server/native/youtube/

## Purpose

YouTube content acquisition APIs for transcript extraction and video downloads. Provides REST APIs with background workers for async job processing, PostgreSQL integration for deduplication, and rate limiting.

## Boundaries

- **Manages**: YouTube transcript extraction (legacy API, new job-based API), video downloads via yt-dlp, output format configuration, rate limiting, API key management
- **Does NOT manage**: PostgreSQL database (-> `domains/server/databases`), monitoring metrics (-> `domains/server/native/monitoring`), reverse proxy routes (-> `domains/server/routes.nix`)

## Structure

```
domains/media/youtube/
├── README.md           # This file
├── index.nix           # Domain aggregator
├── options.nix         # hwc.media.youtube.* options
└── parts/
    ├── legacy-api.nix  # Original transcript API (FastAPI, direct output)
    ├── transcripts/
    │   └── default.nix # Job-based transcript API with worker
    └── yt-videos-api/
        └── default.nix # Video download API with atomic finalization
```

### Workspace Support (`workspace/media/youtube-services/`)

```
workspace/media/youtube-services/
├── packages/
│   ├── yt_core/             # Shared library (SQLAlchemy, Pydantic models)
│   ├── yt_transcripts_api/  # Transcript extraction API + worker
│   └── yt_videos_api/       # Video download API + worker
├── transcript-formatter/    # Obsidian transcript formatter (Ollama/Qwen)
├── DEPLOYMENT.md
└── pyproject.toml
```

## Configuration

### Legacy Transcript API

```nix
hwc.server.native.youtube.legacyApi = {
  enable = true;
  port = 5000;  # Default: 5000
  dataDir = "/path/to/transcripts";
};
```

### New Transcripts API (Job-based)

```nix
hwc.server.native.youtube.transcripts = {
  enable = true;
  port = 8100;
  workers = 4;
  outputDirectory = "/mnt/hot/youtube-transcripts";
  defaultOutputFormat = "markdown";  # or "jsonl"
  rateLimit = {
    requestsPerSecond = 10;
    burst = 50;
    quotaLimit = 10000;
  };
};
```

### Videos API

```nix
hwc.server.native.youtube.videos = {
  enable = true;
  port = 8101;
  workers = 2;
  outputDirectory = "/mnt/media/youtube";
  containerPolicy = "webm";  # or "mp4", "mkv"
  qualityPreference = "best";
  embedMetadata = true;
  embedCoverArt = true;
};
```

## Dependencies

- PostgreSQL (`hwc.server.databases.postgresql`) - Required for job-based APIs
- YouTube API key (optional) - Only needed for playlist/channel expansion
- Secrets: `youtube-transcripts-db-url`, `youtube-videos-db-url`, `youtube-api-key` (optional)

## Services

| Service | Port | Description |
|---------|------|-------------|
| `transcript-api` | 5000 | Legacy transcript extraction |
| `transcripts` | 8100 | Job-based transcript extraction |
| `yt-transcripts-worker` | - | Background transcript processor |
| `yt-videos-api` | 8101 | Video download job submission |
| `yt-videos-worker` | - | Background video downloader |

## Changelog
- 2026-08-06: Transcripts UI v4 — multi-box URL input (`+ URL` / remove rows, no more comma/newline paste), playlist URLs expand (`fetch_playlist` via `yt-dlp --flat-playlist`) with each playlist saved to its own titled subfolder, and a save-location picker: new `outputRoots` option is a whitelist of base dirs (default `<media.root>/transcripts` + `media.youtube`) surfaced as a UI dropdown + free-text subfolder. `ReadWritePaths`/tmpfiles now derive from `outputRoots` (was single `outputDirectory`); base is validated against the whitelist and the subfolder is sanitized so no path escapes its root. `fetch_transcript` retries once on the intermittent datacenter-IP rate-limit. New `/config` endpoint feeds the dropdown; `/transcript` (n8n) unchanged.
- 2026-08-06: Renamed the transcript service `yt-transcripts-api` → `transcripts` everywhere — systemd unit (`transcripts.service`), StateDirectory (`hwc/transcripts`), parts folder (`parts/transcripts/`), and the Caddy vhost (now `transcripts.hwc.iheartwoodcraft.com`). Old empty StateDirectory `hwc/yt-transcripts-api` orphaned. Loopback :8100 unchanged, so n8n callers unaffected.
- 2026-07-11: `transcripts.outputDirectory` default is now `${config.hwc.paths.media.root}/transcripts` — the dead `/mnt/media` fallback removed (media.root is non-null on every server-role host that imports this domain). Law 3 migration, value unchanged.

- 2026-03-26: Workspace source moved from workspace/youtube-services/ to workspace/media/youtube-services/ (domain alignment); all nix refs updated
- 2026-03-04: Namespace migration hwc.server.native.youtube.* → hwc.media.youtube.*
- 2026-02-27: Initial domain creation with legacy API, transcripts API, and videos API
