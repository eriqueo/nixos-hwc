# YouTube Services Deployment Guide

## Status: Ready for Deployment

The YouTube transcripts and videos services are fully configured and ready to deploy.

## Secrets Created

✅ **youtube-db-url.age** - PostgreSQL connection string
```
postgresql://youtube_user@localhost/youtube_services
```

✅ **youtube-api-key.age** - YouTube Data API key (PLACEHOLDER)
```
Current value: REPLACE_WITH_YOUR_YOUTUBE_DATA_API_KEY_FROM_GOOGLE_CLOUD_CONSOLE
```

## Pre-Deployment Steps

### 1. Replace YouTube API Key (Optional but Recommended)

The YouTube API key enables playlist and channel expansion. If you have one:

```bash
# Get server public key
sudo age-keygen -y /etc/age/keys.txt

# Replace placeholder with your actual API key
echo "YOUR_ACTUAL_YOUTUBE_API_KEY" | \
  age -r <pubkey> -o domains/secrets/parts/server/youtube-api-key.age
```

**Note**: Without an API key, services will work for single videos but not playlists/channels.

### 2. Create PostgreSQL Database and User

On the server, run:

```bash
sudo -u postgres psql <<EOF
CREATE DATABASE youtube_services;
CREATE USER youtube_user;
GRANT ALL PRIVILEGES ON DATABASE youtube_services TO youtube_user;
\c youtube_services
GRANT ALL ON SCHEMA public TO youtube_user;
EOF
```

### 3. Deploy Configuration

```bash
# From nixos-hwc directory
sudo nixos-rebuild switch --flake .#hwc-server
```

### 4. Verify Services Started

```bash
# Check API servers
systemctl status yt-transcripts-api
systemctl status yt-videos-api

# Check workers
systemctl status yt-transcripts-worker
systemctl status yt-videos-worker

# Check database setup
systemctl status yt-transcripts-api-setup
systemctl status yt-videos-api-setup
```

## Service Endpoints

After deployment, services will be available at:

- **Transcripts API**: `https://hwc-server.ts.net/api/transcripts`
- **Videos API**: `https://hwc-server.ts.net/api/videos`

### Health Checks

```bash
curl https://hwc-server.ts.net/api/transcripts/health
curl https://hwc-server.ts.net/api/videos/health
```

## Example Usage

### Submit a Transcript Extraction Job

```bash
curl -X POST https://hwc-server.ts.net/api/transcripts/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "entity_type": "video",
    "entity_id": "dQw4w9WgXcQ",
    "output_format": "markdown"
  }'
```

### Submit a Video Download Job

```bash
curl -X POST https://hwc-server.ts.net/api/videos/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "entity_type": "video",
    "entity_id": "dQw4w9WgXcQ",
    "container_policy": "webm",
    "embed_metadata": true
  }'
```

### Check Job Status

```bash
curl https://hwc-server.ts.net/api/transcripts/jobs/{job_id}
curl https://hwc-server.ts.net/api/videos/jobs/{job_id}
```

## Output Locations

- **Transcripts**: `/mnt/hot/youtube-transcripts/`
- **Videos**: `/mnt/media/youtube/`
- **Staging**: `/mnt/media/youtube/.staging/` (auto-created, auto-cleaned)

## Architecture Highlights

### Crash Recovery
- Jobs use lease-based locking with automatic recovery
- Expired leases are automatically reclaimed
- Failed downloads remain in staging for debugging (24h cleanup)

### Atomic Finalization
- Downloads stage in `<output>/.staging/` for same-filesystem atomic rename
- Cross-filesystem scenarios handled transparently with copy+fsync+rename
- PostgreSQL advisory locks prevent concurrent finalization

### Rate Limiting
- HTTP scraping: 10 req/s with burst of 50
- YouTube API quota: 10,000 units/day tracked and enforced
- Automatic quota reset every 24 hours

### Multi-Worker Support
- API servers run with `--workers 1` (single process)
- Worker processes run independently (scalable via systemd)
- FOR UPDATE SKIP LOCKED enables parallel job processing

## Monitoring

```bash
# View logs
journalctl -u yt-transcripts-api -f
journalctl -u yt-transcripts-worker -f
journalctl -u yt-videos-api -f
journalctl -u yt-videos-worker -f

# Check database
sudo -u postgres psql youtube_services -c "SELECT * FROM yt_transcripts.jobs LIMIT 10;"
sudo -u postgres psql youtube_services -c "SELECT * FROM yt_videos.jobs LIMIT 10;"
```

## Troubleshooting

### Services won't start
- Check PostgreSQL is running: `systemctl status postgresql`
- Verify database exists: `sudo -u postgres psql -l | grep youtube`
- Check secrets are accessible: `ls -la /run/agenix/youtube-*`

### Jobs stuck in processing
- Check worker logs: `journalctl -u yt-transcripts-worker -n 100`
- Check for expired leases: `SELECT * FROM yt_transcripts.jobs WHERE status='processing' AND lease_expires_at < NOW();`
- Restart workers: `systemctl restart yt-transcripts-worker yt-videos-worker`

### Quota exceeded
- Check quota usage: `SELECT SUM(quota_units_used) FROM yt_transcripts.jobs WHERE requested_at > NOW() - INTERVAL '24 hours';`
- Quota resets automatically after 24 hours
- Reduce worker count or add delays if hitting limits

## Next Steps

1. ✅ Secrets created
2. ✅ Configuration validated (`nix flake check` passed)
3. ⏳ Replace YouTube API key with real value
4. ⏳ Create PostgreSQL database and user on server
5. ⏳ Deploy to server
6. ⏳ Verify services are running
7. ⏳ Test end-to-end with sample jobs

---

**Date Created**: 2026-01-02
**Configuration Version**: Phase 4 Complete
**Services**: yt-transcripts-api v0.1.0, yt-videos-api v0.1.0
