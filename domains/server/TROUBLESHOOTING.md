# Server Domain Troubleshooting Guide

**Last Updated**: November 6, 2025

This document captures known issues, their resolutions, and preventive measures for the HWC server domain.

---

## Table of Contents

- [Media Orchestration Issues](#media-orchestration-issues)
- [Fake/Malicious Torrent Detection](#fakemalicious-torrent-detection)
- [Container Volume Mount Issues](#container-volume-mount-issues)
- [Best Practices](#best-practices)
- [Verification Commands](#verification-commands)

---

## Media Orchestration Issues

### Issue: Media Orchestrator Service Failing to Start

**Date**: November 5, 2025
**Symptom**: `media-orchestrator.service` fails with "Failed to load environment files: No such file or directory"

#### Root Cause
The service attempted to read API keys from agenix secrets before `agenix.service` had created them. The preStart script tried to create `/tmp/media-orchestrator.env` by reading from `/run/agenix/*` files that didn't exist yet.

#### Solution
Add explicit systemd dependencies on `agenix.service`:

```nix
# domains/server/orchestration/media-orchestrator.nix
systemd.services.media-orchestrator = {
  description = "Event-driven *Arr nudger (no file moves)";
  after = [
    "agenix.service"              # ← Added
    "network-online.target"
    "media-orchestrator-install.service"
    "podman-sonarr.service" "podman-radarr.service" "podman-lidarr.service"
  ];
  wants = [ "agenix.service" "network-online.target" ];  # ← Added agenix
  wantedBy = [ "multi-user.target" ];
  # ...
};
```

**Fixed in**: Commit `8e5e14d`

#### Verification
```bash
# Check service status
systemctl status media-orchestrator.service

# Verify environment file is created
ls -la /tmp/media-orchestrator.env

# Check dependencies are satisfied
systemctl list-dependencies media-orchestrator.service
```

---

## Container Volume Mount Issues

### Issue: qBittorrent Completion Events Not Triggering

**Date**: November 5, 2025
**Symptom**: qBittorrent downloads complete but Sonarr/Radarr never import them. Event log file `/mnt/hot/events/qbt.ndjson` remains empty.

#### Root Cause
qBittorrent container was configured to run `/scripts/qbt-finished.sh` on completion, but the paths weren't mounted in the container:
- `/opt/downloads/scripts` → `/scripts` (completion scripts)
- `/mnt/hot/events` → `/mnt/hot/events` (event logging)

Without these mounts, the completion hook couldn't execute or write events.

#### Solution
Add missing volume mounts to qBittorrent container:

```nix
# domains/server/containers/qbittorrent/parts/config.nix
volumes = [
  "/opt/downloads/qbittorrent:/config"
  "${paths.hot}/downloads:/downloads"
  "/opt/downloads/scripts:/scripts:ro"        # ← Added (read-only)
  "${paths.hot}/events:/mnt/hot/events"       # ← Added (read-write)
];
```

**Fixed in**: Commit `4f3f3a3`

#### Verification
```bash
# Check volumes are mounted
sudo podman exec qbittorrent ls -la /scripts/
sudo podman exec qbittorrent ls -la /mnt/hot/events/

# Trigger a test (complete a small download) and verify event is logged
tail -f /mnt/hot/events/qbt.ndjson

# Check orchestrator processes events
journalctl -u media-orchestrator.service -f
```

#### Why This Matters
The media automation workflow depends on completion events:

```
qBittorrent Download Completes
    ↓
Runs /scripts/qbt-finished.sh
    ↓
Writes event to /mnt/hot/events/qbt.ndjson
    ↓
media-orchestrator.py reads event
    ↓
Triggers Sonarr/Radarr rescan API
    ↓
Media imported to /mnt/media/{tv,movies}/
```

Without the volume mounts, this entire chain breaks at step 2.

---

## Fake/Malicious Torrent Detection

### Issue: Completed Downloads Not Importing Despite Working Orchestration

**Date**: November 5, 2025
**Symptom**: Multiple TV show torrents completed and appear in `/mnt/hot/downloads/` but Sonarr refuses to import them. Movies import fine.

#### Investigation Results

**TV Shows (ALL FAKE)**:
- South Park S28E02, S28E03
- The Simpsons S37E05, S37E06
- The Chair Company S01E03, S01E04, S01E05

**Analysis**: All TV show torrents from ThePirateBay contained:
```bash
# Actual RAR contents (example):
$ unrar l "South Park S28E03.rar"
732104192  South Park S28E03.exe                      # ← MALWARE
        0  Torrent Downloaded From thepiratebay.org.txt
462045219  vis/Countdown.2025.S01E07.1080p.mkv        # ← Wrong show!
658559059  vis/Stick.S01E10.1080p.HEVC.x265.mkv       # ← Wrong show!
```

**Movies (Legitimate)**:
- Cool Runnings (1993) from YTS.AG - Legitimate MP4 file
- Dr. No (1962) from YTS.MX - Legitimate 4K MKV file

Both movies imported successfully to `/mnt/media/movies/`.

#### Why Sonarr/Radarr Refused to Import

The *arr services were **working correctly** and **protecting the system** by:
1. **Content Validation**: Detected files didn't match expected show metadata
2. **Quality Parsing**: Couldn't parse quality/codec from malicious filenames
3. **Episode Detection**: No valid episode files found in RAR archives
4. **Security Feature**: Refused to import suspicious content

This is the correct behavior and demonstrates why using Sonarr/Radarr's built-in search (via Prowlarr) is safer than manual downloads.

#### Detection Methods

**Manual Inspection**:
```bash
# Check for suspicious RAR files in completed downloads
find /mnt/hot/downloads/ -name "*.rar" -exec echo {} \;

# List RAR contents without extracting (safe)
sudo podman exec sabnzbd unrar l "/downloads/path/to/file.rar"

# Look for warning signs:
# - .exe files (especially on Linux server)
# - Mismatched show names in subdirectories
# - Files from "thepiratebay.org" subdirectories
# - Wrong episode numbers or show titles
```

**Automated Detection** (future enhancement):
```bash
# Could add to media-orchestrator.py
def is_suspicious_download(path):
    # Check for .exe files
    if any(f.endswith('.exe') for f in os.listdir(path)):
        return True
    # Check for RAR with mismatched content
    # Check for common fake torrent patterns
    return False
```

#### Cleanup
```bash
# Remove fake torrents from hot storage
sudo rm -rf "/mnt/hot/downloads/South Park S28E"*
sudo rm -rf "/mnt/hot/downloads/The Simpsons S37E"*
sudo rm -rf "/mnt/hot/downloads/The Chair Company"*

# Verify storage reclaimed
du -sh /mnt/hot/downloads/
```

#### Prevention

**DO**:
- ✅ Always use Sonarr/Radarr's built-in search (via Prowlarr)
- ✅ Configure trusted indexers in Prowlarr only
- ✅ Let Sonarr/Radarr download automatically when monitoring shows
- ✅ Use reputable sources like YTS for movies (if manual downloads needed)
- ✅ Verify file types before extracting (use `unrar l` to list contents)

**DON'T**:
- ❌ Download torrents manually from ThePirateBay
- ❌ Extract RAR files containing .exe files on Linux
- ❌ Trust torrents with mismatched content in subdirectories
- ❌ Bypass Sonarr/Radarr's import validation
- ❌ Disable Sonarr/Radarr's content verification features

#### Recommended Prowlarr Indexers

**Public Indexers** (use with caution):
- EZTV (TV shows) - Generally reliable
- YTS/YIFY (Movies) - High quality, legitimate files
- RARBG (both) - Generally reliable but closed

**Private Indexers** (recommended if access available):
- BTN (TV) - Best quality, heavily moderated
- PTP (Movies) - Best quality, heavily moderated
- RED (Music) - Best quality, heavily moderated

**Avoid**:
- ThePirateBay - High rate of fake/malicious content
- Torrentz2 - Aggregator with minimal moderation
- 1337x - Inconsistent quality control

#### Security Recommendations

If you suspect you may have executed malicious files:

```bash
# 1. Check for suspicious processes
ps aux | grep -i "countdown\|stick"

# 2. Check recent systemd logs for unusual activity
journalctl --since "24 hours ago" | grep -i "fail\|error\|suspicious"

# 3. Scan for persistence mechanisms
find /home /tmp /var/tmp -name "*.sh" -mtime -1

# 4. Review crontabs
crontab -l
sudo crontab -l

# 5. Check for unauthorized network connections
ss -tunap | grep ESTABLISHED
```

**Note**: The .exe files in these RAR archives are Windows malware and wouldn't execute on Linux without Wine. However, always treat unexpected executables with suspicion.

---

## Best Practices

### Safe Download Workflow

**Recommended Process**:

1. **Add Media to *arr Apps**:
   ```
   Sonarr → Add Series → Search by name → Monitor future episodes
   Radarr → Add Movie → Search by title → Monitor for availability
   ```

2. **Let *arr Apps Search**:
   - Sonarr/Radarr will search Prowlarr indexers automatically
   - Quality profiles ensure you get correct resolution/codec
   - Release profiles filter out bad releases

3. **Automatic Download**:
   - Download clients (qBittorrent/SABnzbd) handle the download
   - VPN routing (via Gluetun) protects your IP
   - Completion hooks trigger automatically

4. **Automatic Import**:
   - media-orchestrator detects completion
   - Sonarr/Radarr verify and import files
   - Files moved to `/mnt/media/{tv,movies}/`
   - Original downloads cleaned up

**Manual Downloads** (only when necessary):

1. ✅ **Through *arr Apps**: Search → Manual Import
   - Still gets validation and quality checking
   - Proper naming and organization
   - Metadata downloaded automatically

2. ⚠️ **Direct Download** (not recommended):
   - Only from trusted sources (YTS, EZTV with verification)
   - Check file extensions before extracting
   - Use "Manual Import" in *arr apps to add

### Storage Management

**Hot Storage** (`/mnt/hot/downloads/`):
- Temporary download staging area
- Cleaned automatically by media-cleanup.service (daily)
- Retention: 7 days for processed files
- Monitor usage: `du -sh /mnt/hot/downloads/`

**Cold Storage** (`/mnt/media/`):
- Permanent media library
- Organized by Sonarr/Radarr/Lidarr
- Accessed by Jellyfin, Navidrome
- Monitor usage: `du -sh /mnt/media/{tv,movies,music}/`

**Cleanup Schedule**:
```bash
# Check cleanup service status
systemctl status media-cleanup.service
systemctl status media-cleanup.timer

# Manual cleanup (if needed)
sudo systemctl start media-cleanup.service

# View cleanup logs
journalctl -u media-cleanup.service --since today
```

### Container Maintenance

**Adding New Packages to Containers**:

If you need to add tools to a LinuxServer.io container (temporary):
```bash
# Example: Adding extraction tools to Sonarr
sudo podman exec sonarr apk add --no-cache p7zip

# Note: This is NOT permanent! Container recreation will lose it.
```

**Making Packages Permanent**:

For permanent package additions, create a custom init script:
```nix
# domains/server/containers/sonarr/parts/config.nix
volumes = [
  # ... existing volumes ...
  "/opt/init-scripts:/custom-cont-init.d:ro"
];

# Then create: /opt/init-scripts/install-packages.sh
#!/bin/bash
apk add --no-cache p7zip
```

LinuxServer.io containers automatically run scripts in `/custom-cont-init.d/` on startup.

---

## Verification Commands

### Check Full Media Pipeline

```bash
# 1. Check all container services
sudo podman ps | grep -E "sonarr|radarr|lidarr|qbittorrent|sabnzbd"

# 2. Check orchestrator
systemctl status media-orchestrator.service
cat /var/lib/node_exporter/textfile_collector/media_orchestrator.prom

# 3. Check events are being logged
ls -lh /mnt/hot/events/
tail /mnt/hot/events/{qbt,sab,slskd}.ndjson

# 4. Check API connectivity
curl -s http://localhost:8989/api/v3/system/status \
  -H "X-Api-Key: $(sudo cat /run/agenix/sonarr-api-key)" | jq .

curl -s http://localhost:7878/api/v3/system/status \
  -H "X-Api-Key: $(sudo cat /run/agenix/radarr-api-key)" | jq .

# 5. Check storage usage
df -h /mnt/hot /mnt/media

# 6. Check recent imports
find /mnt/media/tv/ -type f -mtime -1 | head -10
find /mnt/media/movies/ -type f -mtime -1 | head -10
```

### Troubleshoot Import Failures

```bash
# Check Sonarr logs for import errors
journalctl -u podman-sonarr.service --since "1 hour ago" | grep -i "import\|error"

# Check Radarr logs
journalctl -u podman-radarr.service --since "1 hour ago" | grep -i "import\|error"

# Check if files are accessible from containers
sudo podman exec sonarr ls -la /downloads/
sudo podman exec radarr ls -la /downloads/

# Manually trigger import
curl -X POST http://localhost:8989/api/v3/command \
  -H "X-Api-Key: $(sudo cat /run/agenix/sonarr-api-key)" \
  -H "Content-Type: application/json" \
  -d '{"name":"DownloadedEpisodesScan","path":"/downloads"}'
```

### Check VPN Routing

```bash
# Verify download clients are using VPN
sudo podman exec gluetun curl -s ifconfig.me     # Shows VPN IP
sudo podman exec qbittorrent curl -s ifconfig.me # Should match VPN IP
sudo podman exec sabnzbd curl -s ifconfig.me     # Should match VPN IP

# Check your actual public IP (for comparison)
curl -s ifconfig.me
```

### Verify Volume Mounts

```bash
# Check qBittorrent has required mounts
sudo podman inspect qbittorrent | jq '.[0].Mounts'

# Verify scripts are accessible
sudo podman exec qbittorrent ls -la /scripts/

# Verify events directory is writable
sudo podman exec qbittorrent touch /mnt/hot/events/test && \
sudo podman exec qbittorrent rm /mnt/hot/events/test && \
echo "Events directory is writable"
```

---

## Common Error Messages

### "Failed to load environment files: No such file or directory"
**Cause**: Service starting before agenix.service creates secrets
**Solution**: Add agenix.service dependency (see [Media Orchestration Issues](#media-orchestration-issues))

### "Import failed, path does not exist or is not accessible"
**Cause**:
1. File was deleted/moved before import
2. Permissions issue
3. Path mismatch between container and host

**Debug**:
```bash
# Check if file exists on host
ls -la /mnt/hot/downloads/<path-from-error>

# Check if accessible from container
sudo podman exec sonarr ls -la /downloads/<path-from-error>

# Check ownership
stat /mnt/hot/downloads/<path-from-error>
```

### "Failed to get runtime from the file, make sure ffprobe is available"
**Cause**: Sonarr trying to detect sample files but ffprobe missing
**Impact**: Warning only, doesn't prevent imports
**Solution**: Add ffmpeg to container (optional):
```bash
sudo podman exec sonarr apk add --no-cache ffmpeg
```

### "Cannot open the file as archive"
**Cause**:
1. Corrupt RAR file
2. RAR5 format not supported by old unrar
3. Multi-part RAR (missing parts)
4. Fake/malicious torrent

**Debug**:
```bash
# Check file type
file /mnt/hot/downloads/<file>.rar

# List RAR contents safely
sudo podman exec sabnzbd unrar l "/downloads/<file>.rar"

# Check for multi-part RAR
ls -la /mnt/hot/downloads/<directory>/ | grep -E ".r[0-9]|.part"
```

---

## Historical Issues & Fixes

### November 6, 2025 - Media Pipeline Restoration
- **Issue**: Completed downloads not importing to cold storage
- **Root Causes**:
  1. media-orchestrator.service missing agenix dependency
  2. qBittorrent container missing volume mounts
  3. Multiple fake/malicious torrents from ThePirateBay
- **Resolution**:
  1. Added systemd dependencies (commit `8e5e14d`)
  2. Added volume mounts (commit `4f3f3a3`)
  3. Removed malicious content and documented detection methods
- **Lessons Learned**:
  - Always use *arr apps' built-in search via Prowlarr
  - Sonarr/Radarr's import validation is a security feature
  - ThePirateBay is not a reliable source
  - Volume mounts must be verified after container configuration changes

### October 2024 - Workspace Reorganization
- Moved automation scripts from `scripts/` to `workspace/automation/`
- Updated media-orchestrator to deploy from new location
- All services updated to use new paths

### October 2024 - Sops→Agenix Migration
- Migrated all secrets from sops-nix to agenix
- Updated all services to use new secret paths
- Fixed media-orchestrator secret integration

---

## Related Documentation

- **[README.md](README.md)** - Server domain overview and architecture
- **[SERVICES.md](SERVICES.md)** - Comprehensive service guide
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Quick command reference
- **[Charter v6.0](../../CHARTER.md)** - HWC architecture principles

---

**Document Version**: 1.0
**Maintainer**: System Administrator
**Review Schedule**: After each major incident or quarterly
