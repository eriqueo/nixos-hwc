# domains/media/youtube/

## Purpose

YouTube transcript extraction API (job-based) with a background worker for async
processing, PostgreSQL integration for deduplication, and rate limiting.

## Boundaries

- **Manages**: YouTube transcript extraction (job-based API + worker), output format configuration, rate limiting, API key management
- **Does NOT manage**: PostgreSQL database (-> `domains/server/databases`), monitoring metrics (-> `domains/server/native/monitoring`), reverse proxy routes (-> `domains/server/routes.nix`)

## Structure

```
domains/media/youtube/
├── README.md           # This file
├── index.nix           # Domain aggregator + hwc.media.youtube.* options
└── parts/
    └── yt-transcripts-api/
        └── default.nix # Job-based transcript API with worker
```

## Configuration

### Transcripts API (Job-based)

```nix
hwc.media.youtube.transcripts = {
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

## Dependencies

- PostgreSQL (`hwc.server.databases.postgresql`) - Required for the job-based API
- YouTube API key (optional) - Only needed for playlist/channel expansion
- Secrets: `youtube-transcripts-db-url`, `youtube-api-key` (optional)

## Services

| Service | Port | Description |
|---------|------|-------------|
| `yt-transcripts-api` | 8100 | Job-based transcript extraction |
| `yt-transcripts-worker` | - | Background transcript processor |

## Changelog

- 2026-07-06: Structure/Configuration/Services rewritten to match reality — the videos API (`parts/yt-videos-api/`) and the legacy transcript API (`parts/legacy-api.nix`) are both gone, leaving only `yt-transcripts-api`. Reflects: the 2026-04-12 "lots" commit that gutted `yt-videos-api/default.nix` and trimmed `index.nix`, the 2026-06-09 Law 3 path sweep (derive from `hwc.paths`), the 2026-06-02 server tailnet rename (`hwc` → `hwc-server` in `yt-transcripts-api/default.nix`), and the 2026-07-05 cleanup that removed `legacy-api.nix` entirely (never enabled, superseded by yt-transcripts-api v2, scriptDir pointed at a nonexistent path) along with its prometheus scrape block and server-config stanza.
- 2026-03-26: Workspace source moved from workspace/youtube-services/ to workspace/media/youtube-services/ (domain alignment); all nix refs updated
- 2026-03-04: Namespace migration hwc.server.native.youtube.* → hwc.media.youtube.*
- 2026-02-27: Initial domain creation with legacy API, transcripts API, and videos API
