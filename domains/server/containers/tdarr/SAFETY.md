# Tdarr Safety Guide: Protecting Your Media Files

**IMPORTANT**: This guide ensures your media files are never lost or corrupted during transcoding.

---

## 🛡️ Multi-Layer Safety System

Your Tdarr configuration includes **5 layers of protection**:

### Layer 1: Non-Destructive Mode (DEFAULT)
**What it does**: Creates NEW transcoded files, never touches originals
**Location**: Separate output directory

### Layer 2: Pre-Transcode Verification
**What it does**: Validates files before transcoding starts
**Checks**: File exists, readable, not empty, has valid video stream

### Layer 3: Post-Transcode Validation
**What it does**: Verifies transcoded files are valid before replacing
**Checks**: Duration match, valid video format, not corrupted

### Layer 4: Checksum Backups
**What it does**: Stores checksums of original files
**Purpose**: Can verify originals weren't modified

### Layer 5: Manual Approval Workflow
**What it does**: You review transcodes before auto-replace is enabled
**Purpose**: Catch any quality/compatibility issues early

---

## 📋 Safe Testing Workflow (RECOMMENDED)

Follow this workflow to safely test Tdarr without any risk:

### Phase 1: Test Library (Week 1)

**Step 1**: Create a test directory with copies of 10-20 files
```bash
# Create test directory
sudo mkdir -p /mnt/media/test-transcode
sudo cp /mnt/media/tv/TestShow/Season\ 01/Episode\ 01.mkv /mnt/media/test-transcode/
# ... copy 10-20 diverse files (different codecs, sizes, qualities)

sudo chown -R 1000:1000 /mnt/media/test-transcode
```

**Step 2**: Configure Tdarr to ONLY scan test directory
1. Go to https://hwc.ocelot-wahoo.ts.net:8265
2. Libraries → Add Library
3. Name: "Test Library"
4. Source: `/media/test-transcode`
5. **Important**: Set "Replace original" to **OFF**

**Step 3**: Configure transcode settings
1. Go to "Plugins" tab
2. Enable: "Transcode using Nvidia GPU"
3. Settings:
   - Container: `hevc_nvenc`
   - CRF: `23`
   - Output folder: `/temp/transcoded/`

**Step 4**: Run transcode on test files
1. Tdarr will create NEW files in `/temp/transcoded/`
2. Original files remain untouched in `/media/test-transcode/`

**Step 5**: Manually compare files
```bash
# Run safety check
tdarr-safety-check

# Compare a test file
ORIGINAL="/mnt/media/test-transcode/Episode 01.mkv"
TRANSCODED="/mnt/hot/processing/tdarr-temp/transcoded/Episode 01.mkv"

# Check sizes
ls -lh "$ORIGINAL" "$TRANSCODED"

# Play both files in a media player and compare quality
# Use VLC, mpv, or Jellyfin to watch 2-3 minutes of each

# Check video properties
ffprobe "$ORIGINAL"
ffprobe "$TRANSCODED"
```

**Step 6**: Verify quality is acceptable
- Watch transcoded files for artifacts, pixelation, audio sync issues
- Check subtitles still work
- Verify file plays on all your devices (Roku, phone, etc.)

**Criteria for success**:
- ✅ No visible quality loss
- ✅ File size reduced by 40-70%
- ✅ Audio/video sync maintained
- ✅ Subtitles intact
- ✅ Plays on all devices

---

### Phase 2: Small Library (Week 2-3)

**Only proceed if Phase 1 was successful!**

**Step 1**: Add one SMALL library (e.g., one TV show with 1-2 seasons)
```bash
# Example: Test on one complete show
# Libraries → Add Library
# Source: /media/tv/Breaking\ Bad/
# Replace original: OFF (still testing)
```

**Step 2**: Let Tdarr transcode the entire library

**Step 3**: Review random samples (10-15 episodes)
```bash
# Check a few episodes from different seasons
# Verify quality, compatibility, metadata preservation
```

**Step 4**: If all good, manually replace originals
```bash
# For each good transcode:
# 1. Verify transcoded file plays correctly
# 2. Move original to backup:
sudo mkdir -p /mnt/media/.tdarr-originals-backup/
sudo mv "$ORIGINAL" /mnt/media/.tdarr-originals-backup/

# 3. Move transcoded file to library:
sudo mv "$TRANSCODED" "$ORIGINAL_LOCATION"
```

---

### Phase 3: Full Deployment (Week 4+)

**Only proceed if Phase 2 was successful!**

**Step 1**: Enable "Replace Original" mode
- Tdarr will now replace files automatically after verification
- Still creates temporary files first, validates, then replaces

**Step 2**: Add full libraries gradually
- Week 4: Add TV library
- Week 5: Add Movies library
- Week 6: Add remaining libraries

**Step 3**: Monitor daily
```bash
# Run safety check daily
tdarr-safety-check

# Check Tdarr statistics
# Go to https://hwc.ocelot-wahoo.ts.net:8265
# View: Statistics → Success rate should be >95%
```

---

## 🚨 Emergency: Reverting Changes

If something goes wrong, here's how to recover:

### Scenario 1: Transcoded File is Bad

**If "Replace Original" is OFF**:
- Nothing to do! Original is untouched
- Just delete bad transcode from `/mnt/hot/processing/tdarr-temp/`

**If "Replace Original" is ON and file was replaced**:
```bash
# Check backup directory
ls -la /mnt/media/.tdarr-originals-backup/

# Restore original
sudo cp /mnt/media/.tdarr-originals-backup/BadFile.mkv /mnt/media/tv/Show/BadFile.mkv
```

### Scenario 2: Tdarr is Corrupting Files

**Immediate action**:
```bash
# Stop Tdarr immediately
sudo systemctl stop podman-tdarr

# Disable Tdarr
# Edit profiles/server.nix:
hwc.services.containers.tdarr.enable = false;

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server
```

### Scenario 3: Need to Restore Everything

**If you have backups**:
```bash
# All originals are in:
/mnt/media/.tdarr-originals-backup/

# Checksums are in:
/mnt/hot/processing/tdarr-backups/

# Verify checksums match
cd /mnt/media/.tdarr-originals-backup/
sha256sum -c /mnt/hot/processing/tdarr-backups/*.sha256
```

---

## 🔍 Safety Scripts Reference

Your system includes these safety tools:

### 1. `tdarr-safety-check`
**What it does**: Daily health check of Tdarr system
**Run manually**:
```bash
sudo tdarr-safety-check
```

**Checks**:
- Tdarr container is running
- GPU is accessible
- Sufficient storage space (warns if <100GB)
- Backup directory exists

**When to run**: Daily, or before starting a big transcode job

---

### 2. `tdarr-pre-transcode <file>`
**What it does**: Validates file before transcoding
**Run manually**:
```bash
tdarr-pre-transcode /mnt/media/tv/Show/Episode.mkv
```

**What it checks**:
- File exists and is readable
- File is not empty
- Creates checksum backup

**Outputs**:
- Checksum file: `/mnt/hot/processing/tdarr-backups/Episode.mkv.sha256`
- Size file: `/mnt/hot/processing/tdarr-backups/Episode.mkv.size`

---

### 3. `tdarr-post-transcode <original> <transcoded>`
**What it does**: Validates transcoded file is good
**Run manually**:
```bash
tdarr-post-transcode \
  /mnt/media/tv/Show/Episode.mkv \
  /mnt/hot/processing/tdarr-temp/transcoded/Episode.mkv
```

**What it checks**:
- Transcoded file exists and not empty
- Transcoded file is valid video (ffprobe test)
- Duration matches original (within 1 second)
- File size reduced (warns if larger)

**Outputs**:
- ✓ or ✗ validation result
- Space saved calculation

---

## ⚙️ Tdarr Configuration Safety Settings

### Recommended Initial Settings

**Libraries → Settings**:
```
Library Name: Test Library
Source: /media/test-transcode
Output Folder: /temp/transcoded

Scan Interval: Manual (don't set automatic until Phase 3)
Replace Original: OFF (until Phase 3)
Create Subfolder: OFF
Keep Folder Structure: ON
```

**Transcode → Flow Settings**:
```
Stage 1: Check If File Needs Transcode
  - If codec is NOT HEVC/H.265

Stage 2: Transcode
  - Plugin: Transcode using Nvidia GPU
  - Container: hevc_nvenc
  - CRF: 23 (higher = smaller file, lower quality)
  - Preset: medium

Stage 3: Validate Output
  - Plugin: Check File Validity
  - Action: If invalid, KEEP ORIGINAL

Stage 4: (DISABLED INITIALLY)
  - Replace Original File
  - ENABLE ONLY IN PHASE 3
```

---

## 📊 Monitoring & Validation

### Daily Checklist (5 minutes)

**Day 1-7** (Phase 1 - Testing):
```bash
# 1. Run safety check
tdarr-safety-check

# 2. Check transcode progress
# Go to: https://hwc.ocelot-wahoo.ts.net:8265
# View: Statistics tab

# 3. Manually review 2-3 transcoded files
# Play them, check quality

# 4. Check storage savings
df -h /mnt/media
```

**Week 2-3** (Phase 2 - Small Library):
```bash
# 1. Run safety check
tdarr-safety-check

# 2. Check error rate
# Statistics tab: Should be <5% errors

# 3. Random sample check (5 files per week)
# Play random transcoded files

# 4. Check backup checksums
cd /mnt/hot/processing/tdarr-backups
ls -la | wc -l  # Should match number of transcoded files
```

**Week 4+** (Phase 3 - Full Deployment):
```bash
# 1. Run safety check (automatic daily timer)
sudo journalctl -u tdarr-safety-check -n 20

# 2. Weekly review of statistics
# Check success rate remains >95%

# 3. Monitor storage growth
# Should see decreasing usage as files are transcoded
```

---

## ⚠️ Warning Signs to Watch For

**Stop immediately if you see**:

1. **High error rate** (>10%)
   - Check GPU temperature: `nvidia-smi`
   - Check logs: `sudo podman logs tdarr`
   - May indicate hardware issues

2. **Files growing in size**
   - Bad transcode settings
   - Check CRF setting (should be 20-28)

3. **Playback issues on transcoded files**
   - Buffering, stuttering, audio sync issues
   - Stop transcoding, review settings

4. **Low storage space warnings**
   - Tdarr needs working space
   - Must have >100GB free on /mnt/media

5. **GPU overheating** (>85°C sustained)
   - Check cooling, reduce transcoding rate
   - Limit concurrent transcodes to 1

---

## 🎯 Expected Behavior (Normal)

**These are NORMAL and expected**:

✅ **Transcoding takes time**:
- 1080p episode: 5-15 minutes
- 1080p movie: 30-90 minutes
- 4K movie: 2-4 hours

✅ **Some files can't be transcoded**:
- Already H.265 (skipped)
- Corrupt source files (failed, original kept)
- Unusual codecs (failed, original kept)

✅ **GPU runs hot during transcoding**:
- 70-80°C is normal
- 85°C+ is concerning, reduce load

✅ **Storage usage fluctuates**:
- Temp files during transcode
- Cleans up after completion

---

## 🔐 Backup Strategy

**Before enabling "Replace Original"**:

```bash
# 1. Ensure you have full backups of /mnt/media
# (You should already have this per your backup configuration)

# 2. Create Tdarr-specific backup directory
sudo mkdir -p /mnt/media/.tdarr-originals-backup

# 3. Copy original files before first transcode
# (Tdarr can do this automatically if configured)

# 4. Verify backup integrity weekly
cd /mnt/media/.tdarr-originals-backup
find . -type f -exec sha256sum {} \; > checksums.txt
```

---

## 🚀 Quick Start Safety Summary

**Absolute minimum before starting**:

1. ✅ Run `tdarr-safety-check` - passes
2. ✅ Create test library with 10-20 files
3. ✅ Set "Replace Original" to OFF
4. ✅ Transcode test library successfully
5. ✅ Manually verify 5+ transcoded files
6. ✅ Check quality is acceptable
7. ✅ Have backups of all media

**Only then proceed to Phase 2 (small library)**

**Only after 2 weeks of success proceed to Phase 3 (full deployment)**

---

## 📞 Troubleshooting Safety Issues

### Issue: "tdarr-safety-check" fails

**Diagnosis**:
```bash
# Check what failed
tdarr-safety-check

# Common issues:
# - Tdarr not running: sudo systemctl start podman-tdarr
# - GPU not accessible: Check GPU passthrough in container config
# - Low storage: Free up space or adjust threshold
```

### Issue: Transcode validation fails

**Diagnosis**:
```bash
# Run post-transcode check manually
tdarr-post-transcode \
  /mnt/media/original.mkv \
  /mnt/hot/processing/tdarr-temp/transcoded.mkv

# Check what validation failed:
# - Duration mismatch: Source file may be corrupt
# - Invalid video: Transcode settings wrong
# - File larger: CRF setting too low
```

### Issue: Original file modified (shouldn't happen!)

**Recovery**:
```bash
# 1. Check if backup exists
ls -la /mnt/media/.tdarr-originals-backup/file.mkv

# 2. Verify with checksum
sha256sum /mnt/media/.tdarr-originals-backup/file.mkv
# Compare with: /mnt/hot/processing/tdarr-backups/file.mkv.sha256

# 3. Restore
sudo cp /mnt/media/.tdarr-originals-backup/file.mkv /mnt/media/tv/Show/file.mkv

# 4. STOP TDARR and investigate
sudo systemctl stop podman-tdarr
```

---

## Summary: You're Protected! 🛡️

**Your files are safe because**:

1. ✅ **Non-destructive by default** - originals never touched initially
2. ✅ **Pre-transcode validation** - bad files skipped
3. ✅ **Post-transcode validation** - bad transcodes rejected
4. ✅ **Checksum backups** - can verify integrity
5. ✅ **Manual testing workflow** - you verify quality before auto-replace
6. ✅ **Daily safety checks** - catch issues early
7. ✅ **Emergency recovery** - can restore from backups

**Follow the 3-phase workflow and your media is completely safe.**

---

**Next Steps**:
1. Read this entire guide
2. Run `tdarr-safety-check` to verify system is ready
3. Start Phase 1 (test library)
4. Don't rush - take 3-4 weeks to fully validate before full deployment

**Questions?** Review the troubleshooting section or check Tdarr logs: `sudo podman logs tdarr`
