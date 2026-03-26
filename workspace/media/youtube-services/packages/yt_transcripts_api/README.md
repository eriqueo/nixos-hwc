# yt-transcripts-api

YouTube transcript extraction API service.

## Features

- Extract transcripts from videos, playlists, and channels
- Multi-strategy fallback: official captions → auto-generated → none
- Job-based API with status tracking
- Global deduplication (same video only extracted once)
- Rate limiting and YouTube API quota tracking
- Output formats: Markdown, JSONL
- Playlist caching
- Separate API and worker processes

## Architecture

- **API Server**: FastAPI application (runs with `--workers 1`)
- **Worker**: Separate background processor (independent systemd unit)
- **Database**: PostgreSQL with `yt_transcripts` schema
- **Job Queue**: `FOR UPDATE SKIP LOCKED` for parallel-safe job claiming

## Installation

```bash
cd packages/yt_transcripts_api
pip install -e .
```

## Configuration

Set via environment variables (prefix: `YT_TRANSCRIPTS_`):

- `DATABASE_URL`: PostgreSQL connection string
- `YOUTUBE_API_KEY`: YouTube Data API key (optional, for playlists/channels)
- `HOST`: API host (default: 127.0.0.1)
- `PORT`: API port (default: 8100)
- `WORKERS`: Worker concurrency (default: 4)
- `OUTPUT_DIRECTORY`: Transcript output directory (default: /mnt/hot/youtube-transcripts)
- `RATE_LIMIT_RPS`: HTTP rate limit (default: 10)
- `QUOTA_LIMIT`: YouTube API quota limit (default: 10000)

## Running

### Run migrations

```bash
cd migrations
alembic -x dbUrl="postgresql://user:pass@localhost/db" upgrade head
```

### Start API server

```bash
uvicorn yt_transcripts_api.main:app --host 127.0.0.1 --port 8100 --workers 1
```

### Start worker

```bash
python -m yt_transcripts_api.worker
```

## API Endpoints

- `POST /jobs` - Submit new job
- `GET /jobs/{job_id}` - Get job status
- `GET /jobs` - List jobs (paginated)
- `DELETE /jobs/{job_id}` - Cancel job
- `GET /health` - Health check

## Example

```bash
# Submit a video transcript job
curl -X POST http://localhost:8100/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "entity_type": "video",
    "entity_id": "dQw4w9WgXcQ",
    "output_format": "markdown"
  }'

# Check job status
curl http://localhost:8100/jobs/{job_id}
```

## Database Schema

- `jobs`: User requests
- `videos`: Global video metadata (deduplicated)
- `transcripts`: Global transcripts (deduplicated by video_id + language)
- `job_videos`: Many-to-many job → videos
- `extraction_attempts`: Retry tracking
- `playlist_cache`: Playlist expansion cache
