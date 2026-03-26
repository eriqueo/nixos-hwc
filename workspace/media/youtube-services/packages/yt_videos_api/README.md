# yt-videos-api

YouTube video download and archiving API service.

## Features

- Download videos from YouTube with yt-dlp
- Multi-extractor fallback: android → tv_embedded → web → default
- Atomic finalization (prevents corruption)
- Global deduplication (same video only downloaded once per container policy)
- Metadata embedding with ffmpeg (title, channel, date, cover art)
- Job-based API with status tracking
- Playlist and channel support
- Separate API and worker processes

## Architecture

- **API Server**: FastAPI application (runs with `--workers 1`)
- **Worker**: Separate background processor (independent systemd unit)
- **Database**: PostgreSQL with `yt_videos` schema
- **Atomic Downloads**: Staging area with filesystem-aware finalization
- **Deduplication**: Global `downloads` table keyed by `(video_id, container_policy)`

## Installation

```bash
cd packages/yt_videos_api
pip install -e .
```

## Configuration

Set via environment variables (prefix: `YT_VIDEOS_`):

- `DATABASE_URL`: PostgreSQL connection string
- `YOUTUBE_API_KEY`: YouTube Data API key (optional, for playlists/channels)
- `HOST`: API host (default: 127.0.0.1)
- `PORT`: API port (default: 8101)
- `WORKERS`: Worker concurrency (default: 4)
- `OUTPUT_DIRECTORY`: Video output directory (default: /mnt/media/youtube)
  - Staging area is automatically created at `<OUTPUT_DIRECTORY>/.staging`
  - This ensures same-filesystem atomic rename for correctness
- `CONTAINER_POLICY`: Default container (default: webm)
- `QUALITY_PREFERENCE`: Quality selector (default: best)
- `EMBED_METADATA`: Embed metadata (default: true)
- `EMBED_COVER_ART`: Embed cover art (default: true)

## Running

### Run migrations

```bash
cd migrations
alembic -x dbUrl="postgresql://user:pass@localhost/db" upgrade head
```

### Start API server

```bash
uvicorn yt_videos_api.main:app --host 127.0.0.1 --port 8101 --workers 1
```

### Start worker

```bash
python -m yt_videos_api.worker
```

## API Endpoints

- `POST /jobs` - Submit new download job
- `GET /jobs/{job_id}` - Get job status
- `GET /jobs` - List jobs (paginated)
- `DELETE /jobs/{job_id}` - Cancel job
- `GET /health` - Health check (includes disk space)

## Example

```bash
# Submit a video download job
curl -X POST http://localhost:8101/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "entity_type": "video",
    "entity_id": "dQw4w9WgXcQ",
    "container_policy": "webm",
    "embed_metadata": true,
    "embed_cover_art": true
  }'

# Check job status
curl http://localhost:8101/jobs/{job_id}
```

## Database Schema

- `jobs`: User requests
- `videos`: Global video metadata (deduplicated)
- `downloads`: Global downloads (deduplicated by video_id + container_policy)
- `job_videos`: Many-to-many job → videos
- `download_attempts`: Multi-extractor fallback tracking
- `staging`: Atomic finalization tracking
- `playlist_items`: Playlist item tracking (for optional removal)

## Atomic Finalization

Downloads use a staging area inside `OUTPUT_DIRECTORY` to prevent corruption:

1. Download to `<OUTPUT_DIRECTORY>/.staging/<video_id>_<timestamp>.<ext>`
2. Embed metadata in staging file
3. Atomically move to final location using `yt_core.paths.atomic_move()`:
   - **Same filesystem** (enforced by design): `os.rename()` (atomic, instant)
   - **Cross-filesystem** (transparent fallback): Copy to `.tmp` → fsync → rename
4. Update database with final path + SHA256 hash
5. PostgreSQL advisory lock prevents concurrent finalization

**Key Design**: Staging is ALWAYS inside output directory to ensure same-filesystem atomic rename.
Failed downloads remain in `.staging/` for debugging (cleaned after 24 hours by default).

## Multi-Extractor Fallback

yt-dlp tries extractors in order:

1. **android**: Most reliable
2. **tv_embedded**: Fallback 1
3. **web**: Fallback 2
4. **default**: Last resort (no player_client override)

All attempts are logged in `download_attempts` table.
