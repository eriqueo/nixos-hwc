# Tdarr, Recyclarr, and Organizr Implementation Guide

**Date**: 2025-11-06
**Services**: Tdarr (GPU transcoding), Recyclarr (config sync), Organizr (dashboard)
**Architecture**: HWC Charter v6.0

---

## Overview

This guide walks through implementing three new services:

1. **Tdarr** - GPU-accelerated video transcoding to save storage
2. **Recyclarr** - Automatic *arr configuration sync using TRaSH Guides
3. **Organizr** - Unified dashboard for all services

All three follow your existing HWC architecture patterns.

---

## Prerequisites

✅ All prerequisites already met in your setup:
- NVIDIA P1000 GPU enabled (`hwc.infrastructure.hardware.gpu.enable = true`)
- Podman container runtime configured
- Caddy reverse proxy with Tailscale TLS
- Existing *arr stack (Sonarr, Radarr, Lidarr)
- Agenix secrets management

---

## Step 1: Create Configuration Directories

```bash
# Create config directories for all three services
sudo mkdir -p /opt/downloads/tdarr/{server,configs,logs}
sudo mkdir -p /opt/downloads/recyclarr/config
sudo mkdir -p /opt/downloads/organizr
sudo mkdir -p /mnt/hot/processing/tdarr-temp

# Set permissions
sudo chown -R 1000:1000 /opt/downloads/tdarr
sudo chown -R 1000:1000 /opt/downloads/recyclarr
sudo chown -R 1000:1000 /opt/downloads/organizr
sudo chown -R 1000:1000 /mnt/hot/processing/tdarr-temp
```

---

## Step 2: Set Up Recyclarr API Key Secrets

Recyclarr needs API keys to connect to your *arr services.

### Option A: Use Existing Secrets (If You Have Them)

If you already have API key secrets configured via agenix, skip to Step 3.

### Option B: Create Placeholder Secrets

**For now, we'll use a simplified approach without agenix secrets:**

The Recyclarr config will generate placeholder API keys that you'll need to update manually after first run.

**To get your API keys:**

1. **Sonarr**: Go to http://hwc.ocelot-wahoo.ts.net/sonarr → Settings → General → API Key
2. **Radarr**: Go to http://hwc.ocelot-wahoo.ts.net/radarr → Settings → General → API Key
3. **Lidarr**: Go to http://hwc.ocelot-wahoo.ts.net/lidarr → Settings → General → API Key

**After deployment, you'll manually edit:**
```bash
sudo nano /opt/downloads/recyclarr/config/secrets.yml
# Replace PLACEHOLDER_*_API_KEY with actual keys
```

---

## Step 3: Enable Services in Server Profile

Edit your server profile to enable all three services:

```bash
# Edit the server profile
nano /home/eric/.nixos/profiles/server.nix
```

Add these lines in the appropriate section (around line 275, after the other container services):

```nix
  # Phase 7: Media Optimization and Management
  hwc.services.containers.tdarr.enable = true;
  hwc.services.containers.recyclarr.enable = true;
  hwc.services.containers.organizr.enable = true;
```

**Full context** (what it should look like):

```nix
  # Phase 4: Specialized Services (Soulseek integration)
  hwc.services.containers.slskd.enable = true;
  hwc.services.containers.soularr.enable = true;

  # Phase 7: Media Optimization and Management
  hwc.services.containers.tdarr.enable = true;
  hwc.services.containers.recyclarr.enable = true;
  hwc.services.containers.organizr.enable = true;

  # Native Media Services (Charter compliant)
  hwc.server.navidrome = {
```

---

## Step 4: Rebuild and Deploy

```bash
# Navigate to your NixOS config directory
cd /home/eric/.nixos

# Add new modules to git
git add domains/server/containers/tdarr/
git add domains/server/containers/recyclarr/
git add domains/server/containers/organizr/
git add domains/server/routes.nix
git add docs/NEW-SERVICES-IMPLEMENTATION.md

# Commit changes
git commit -m "feat: add Tdarr (GPU transcoding), Recyclarr (config sync), and Organizr (dashboard)"

# Build configuration (don't switch yet)
sudo nixos-rebuild build --flake .#hwc-server
```

**Check for errors**. If build succeeds:

```bash
# Switch to new configuration
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Step 5: Verify Container Status

```bash
# Check all containers are running
sudo podman ps | rg -E "(tdarr|organizr)"

# Check systemd services
sudo systemctl status podman-tdarr
sudo systemctl status podman-organizr
sudo systemctl status recyclarr-sync.timer

# Check logs
sudo podman logs tdarr
sudo podman logs organizr
sudo journalctl -u recyclarr-sync -n 50
```

---

## Step 6: Access and Configure Services

### **Tdarr** - GPU Transcoding

**Access**: https://hwc.ocelot-wahoo.ts.net:8265

**⚠️ IMPORTANT**: Read `TDARR-SAFETY-GUIDE.md` before configuring!
- Quick version: `TDARR-SAFETY-TLDR.md`
- Your files are protected by 5 safety layers
- Follow 3-phase testing workflow (3-4 weeks)

**Initial Setup**:

1. **First Login**:
   - Click "Get Started"
   - Set admin username/password
   - Click through setup wizard

2. **Configure Libraries**:
   - Go to "Libraries" tab
   - Add library: "TV Shows"
     - Source: `/media/tv`
     - Schedule: `0 */6 * * *` (every 6 hours)
   - Add library: "Movies"
     - Source: `/media/movies`
     - Schedule: `0 */6 * * *`

3. **Configure Transcode Settings**:
   - Go to "Plugins" tab
   - Enable plugin: "Transcode using Nvidia GPU"
   - Settings:
     - Container: `hevc_nvenc` (H.265 hardware encoding)
     - Preset: `medium`
     - CRF: `23` (quality, lower = better)

4. **Configure Flow**:
   - Go to "Transcode" → "Flow"
   - Create flow:
     ```
     Input: Any file
     ↓
     Check: If codec is NOT H.265
     ↓
     Action: Transcode with NVENC to H.265
     ↓
     Action: Replace original file
     ```

5. **Test GPU**:
   - Go to "Status" tab
   - Check "Hardware" section
   - Should show: `NVIDIA Quadro P1000`
   - GPU transcoding will be 10-20x faster than CPU

**Expected behavior**:
- Tdarr scans your media libraries every 6 hours
- Finds large H.264 files
- Transcodes them to H.265 using GPU (saves 50-70% space)
- Replaces originals automatically

---

### **Recyclarr** - Configuration Sync

**Access**: No web UI (runs as systemd timer)

**Initial Setup**:

1. **Update API Keys**:
   ```bash
   # Edit secrets file
   sudo nano /opt/downloads/recyclarr/config/secrets.yml
   ```

   Replace placeholders with actual API keys:
   ```yaml
   secrets:
     sonarr_api_key: <your-sonarr-api-key>
     radarr_api_key: <your-radarr-api-key>
     lidarr_api_key: <your-lidarr-api-key>
   ```

2. **Run Manual Sync** (test it works):
   ```bash
   # Trigger manual sync
   sudo systemctl start recyclarr-sync

   # Watch logs
   sudo journalctl -u recyclarr-sync -f
   ```

3. **Verify Sync**:
   - Go to Sonarr → Settings → Profiles
   - Should see quality profile: "HD-1080p" (auto-created by Recyclarr)
   - Go to Sonarr → Settings → Custom Formats
   - Should see custom formats from TRaSH Guides (DV, HDR, etc.)

4. **Check Timer**:
   ```bash
   # Verify timer is enabled
   sudo systemctl status recyclarr-sync.timer

   # Check next run time
   systemctl list-timers recyclarr-sync
   ```

**Expected behavior**:
- Runs daily at random time (within 1 hour window)
- Syncs quality profiles, custom formats, naming schemes to all *arr instances
- Uses TRaSH Guides best practices
- Keeps all your *arr services configured identically

---

### **Organizr** - Unified Dashboard

**Access**: https://hwc.ocelot-wahoo.ts.net/ (root path)

**Initial Setup**:

1. **First Login**:
   - Navigate to https://hwc.ocelot-wahoo.ts.net/
   - Click "Setup Organizr"
   - Choose admin username/password
   - Database: SQLite (default)
   - Click "Finish Setup"

2. **Add Service Tabs**:

   Go to "Settings" → "Tab Editor" → "Add Tab"

   **Add these tabs:**

   | Tab Name | Category | URL |
   |----------|----------|-----|
   | Jellyfin | Media | `https://hwc.ocelot-wahoo.ts.net/media` |
   | Jellyseerr | Requests | `https://hwc.ocelot-wahoo.ts.net:5543` |
   | Sonarr | Downloads | `https://hwc.ocelot-wahoo.ts.net/sonarr` |
   | Radarr | Downloads | `https://hwc.ocelot-wahoo.ts.net/radarr` |
   | Lidarr | Downloads | `https://hwc.ocelot-wahoo.ts.net/lidarr` |
   | Prowlarr | Downloads | `https://hwc.ocelot-wahoo.ts.net/prowlarr` |
   | qBittorrent | Downloads | `https://hwc.ocelot-wahoo.ts.net/qbt` |
   | SABnzbd | Downloads | `https://hwc.ocelot-wahoo.ts.net/sab` |
   | Tdarr | Management | `https://hwc.ocelot-wahoo.ts.net:8265` |
   | Navidrome | Media | `https://hwc.ocelot-wahoo.ts.net/music` |
   | Immich | Media | `https://hwc.ocelot-wahoo.ts.net:7443` |
   | Frigate | Monitoring | `https://hwc.ocelot-wahoo.ts.net:5443` |

3. **Configure Tab Settings**:
   - For each tab, enable "iFrame embed"
   - Set "Icon" (Organizr has built-in icons for most services)
   - Set category color

4. **Homepage Settings**:
   - Go to "Settings" → "Customize" → "Appearance"
   - Choose theme (dark mode recommended)
   - Enable "Show service status dots"

5. **Optional: Set as Homepage**:
   - Settings → "Homepage Items"
   - Enable: Recently Added (Jellyfin), Active Streams, Download Stats

**Expected behavior**:
- Single homepage with tabs for all services
- Click tab → service loads in iFrame
- No need to remember individual URLs
- Service status indicators (green = up, red = down)

---

## Step 7: Configure *arr Services for Tdarr

Your *arr services should be configured to use Tdarr's output directory:

**In Sonarr/Radarr/Lidarr:**

1. Go to Settings → Media Management
2. Enable "Use Hardlinks instead of Copy"
3. This prevents duplicate files during transcoding

**Optional**: Configure post-processing to trigger Tdarr after download:

1. Settings → Connect → Add Webhook
2. URL: `http://localhost:8266/api/v2/scan-folder`
3. Trigger: On Import

---

## Troubleshooting

### Tdarr: GPU Not Detected

**Symptom**: Tdarr shows "No GPU available"

**Fix**:
```bash
# Check GPU is accessible to container
sudo podman exec tdarr nvidia-smi

# Should show P1000 GPU. If not:
sudo systemctl restart podman-tdarr
```

### Tdarr: "Permission Denied" on Media Files

**Symptom**: Tdarr can't read/write media files

**Fix**:
```bash
# Check ownership
ls -la /mnt/media/tv
ls -la /mnt/media/movies

# Should be owned by uid 1000. If not:
sudo chown -R 1000:1000 /mnt/media/tv
sudo chown -R 1000:1000 /mnt/media/movies
```

### Recyclarr: "API Key Invalid"

**Symptom**: Recyclarr sync fails with authentication error

**Fix**:
```bash
# Get API keys from each service
# Sonarr: Settings → General → API Key
# Update secrets file
sudo nano /opt/downloads/recyclarr/config/secrets.yml

# Restart sync
sudo systemctl restart recyclarr-sync
```

### Organizr: Services Won't Load in iFrame

**Symptom**: Tab shows "Refused to connect" or blank page

**Fix**:

Some services block iFrame embedding. Use "Open in New Tab" button instead.

**Services that work in iFrame**:
- ✅ Sonarr, Radarr, Lidarr, Prowlarr
- ✅ qBittorrent, SABnzbd
- ✅ Tdarr
- ⚠️ Jellyfin (works but may have issues)
- ❌ Jellyseerr (blocked by CSP)

For blocked services, Organizr will show "Open in New Tab" button.

### Organizr: Can't Access at Root Path

**Symptom**: Organizr not accessible at `https://hwc.ocelot-wahoo.ts.net/`

**Check Caddy routing**:
```bash
# Verify route is configured
sudo journalctl -u caddy | rg -i "organizr"

# Test from server
curl http://localhost:9983
# Should return HTML

# Restart Caddy
sudo systemctl restart caddy
```

---

## Performance & Resource Usage

### Expected Resource Consumption

**Tdarr** (while transcoding):
- CPU: 20% (low - GPU does the work)
- GPU: 80-100% utilization (NVENC/NVDEC)
- RAM: 2-4GB
- Disk I/O: High (reading/writing video files)

**Tdarr** (idle):
- CPU: <1%
- RAM: ~500MB

**Organizr**:
- CPU: <1%
- RAM: ~200MB

**Recyclarr**:
- Runs for ~30 seconds daily
- CPU: 10% during sync
- RAM: ~100MB

**Total Impact**: Minimal when idle, significant GPU usage during transcoding.

---

## Storage Savings (Tdarr)

**Expected space savings**:

| Original Format | Size | After H.265 Transcode | Savings |
|-----------------|------|----------------------|---------|
| 4K H.264 Movie | 40GB | 15GB | 62% |
| 1080p H.264 TV Episode | 3GB | 1.2GB | 60% |
| 1080p H.264 Movie | 8GB | 3.5GB | 56% |

**Example**: If you have 500 movies averaging 8GB each:
- Before: 4TB
- After: 1.8TB
- **Saved: 2.2TB** 🎉

---

## Maintenance

### Tdarr

**Weekly**:
- Check "Statistics" tab for transcode completion rate
- Monitor GPU temperature (shouldn't exceed 80°C)

**Monthly**:
- Review transcode settings (quality vs size)
- Check for failed transcodes (errors tab)

### Recyclarr

**Weekly**:
- Check timer ran successfully: `systemctl status recyclarr-sync.timer`

**When TRaSH Guides update** (monthly-ish):
- Recyclarr auto-pulls updates
- Check *arr custom formats were updated

### Organizr

**As needed**:
- Add new services as tabs when you deploy them
- Update tab URLs if service ports change

---

## Next Steps

1. **Let Tdarr run for 24-48 hours** - It will transcode your library in background
2. **Monitor GPU usage**: `watch -n 1 nvidia-smi` (see GPU work)
3. **Check storage savings**: `df -h /mnt/media` (before/after)
4. **Set Organizr as browser homepage** for quick access to everything

---

## Optional: Advanced Tdarr Configuration

### Transcode Profiles by Quality

Create separate flows for different source qualities:

**4K Content** (preserve quality):
- CRF: `20` (higher quality)
- Preset: `slow` (better compression)

**1080p Content** (balance):
- CRF: `23` (good quality)
- Preset: `medium`

**720p/SD Content** (aggressive):
- CRF: `26` (smaller size)
- Preset: `fast`

### Schedule Heavy Transcoding

Configure Tdarr to transcode only during specific hours:

Settings → Tdarr Server → Schedule:
```
Transcode Hours: 22:00 - 06:00  # Only at night
Max Workers: 1  # Don't overload GPU
```

---

## Architecture Integration

All three services follow your HWC patterns:

**Container Networking**:
```
Service → media-network (10.89.0.x) → Port-mapped to localhost → Caddy → External
```

**GPU Passthrough** (Tdarr):
```
Container → /dev/nvidia0, /dev/nvidiactl → P1000 GPU → NVENC hardware encoding
```

**Secrets Management** (Recyclarr):
```
Agenix secrets → /run/agenix/<key> → Config file generation → Container
```

**Reverse Proxy** (All):
```
Tdarr: Port mode (8265)
Organizr: Subpath mode (/) - Root homepage
Recyclarr: No web UI (systemd timer)
```

---

## Summary

**What you now have**:

1. ✅ **Tdarr**: Automatic GPU-accelerated transcoding saving 50-70% storage
2. ✅ **Recyclarr**: Automatic *arr configuration sync using TRaSH Guides
3. ✅ **Organizr**: Single dashboard for all 15+ services

**URLs**:
- Tdarr: `https://hwc.ocelot-wahoo.ts.net:8265`
- Organizr: `https://hwc.ocelot-wahoo.ts.net/` (homepage)
- Recyclarr: (no UI - check `systemctl status recyclarr-sync.timer`)

**All following HWC Charter v6.0 architecture** ✨

---

**Questions or Issues?** Check the troubleshooting section or review logs:
```bash
sudo podman logs tdarr
sudo podman logs organizr
sudo journalctl -u recyclarr-sync -n 100
```
