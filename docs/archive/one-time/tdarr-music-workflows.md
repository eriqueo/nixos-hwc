# Tdarr Music Library Workflows

Access Tdarr at: **http://localhost:8265**

## Setup Order

Complete these workflows in order for best results:

1. [Library Setup](#1-library-setup) ⚙️
2. [Corrupt File Detection](#2-workflow-1-corrupt-file-detection) 🔍
3. [Quality Analysis](#3-workflow-2-quality-analysis) 📊
4. [Low-Quality MP3 Upgrade](#4-workflow-3-low-quality-mp3-upgrade) ⬆️
5. [FLAC Space Optimization](#5-workflow-4-flac-space-optimization) 💾
6. [Audio Standardization](#6-workflow-5-audio-standardization) 🎵
7. [Portable Library Creation](#7-workflow-6-portable-library-creation) 📱

---

## 1. Library Setup

### Add Music Library
1. Open **http://localhost:8265**
2. Go to **Libraries** tab
3. Click **Library +**
4. Configure:
   - **Source**: `/media/music`
   - **Cache**: `/temp`
   - **Output**: `/media/music` (same location = replace files)
   - **Folder Watch**: Enable
   - **Scan on Save**: Enable
5. Click **Save**

### Configure Worker
1. Go to **Nodes** tab
2. Enable **Internal Node**
3. Set **Transcode Limit**: 1 (to avoid overload)
4. Set **Health Check Limit**: 2
5. Click **Save**

---

## 2. Workflow 1: Corrupt File Detection

**Purpose**: Find unreadable/damaged files (like those Pink Floyd/Beatles tracks)

### Create Flow
1. Go to **Tdarr** tab
2. Click **Flows +**
3. Name: `Corrupt File Detection`
4. Add plugins in order:

#### Plugin 1: Check File Integrity
- **Plugin**: `Community: Check for Corrupt Media Streams`
- **Settings**: Default
- **Action on Error**: Tag as "corrupted"

#### Plugin 2: Log Corrupt Files
- **Plugin**: `Community: New File Size Check`
- **Settings**:
  - Min file size: 1 KB
  - Action: Log only
- **Output**: Skip processing, log results

### Assign to Library
1. Go to **Libraries**
2. Select `/media/music`
3. **Transcode Flow**: Select `Corrupt File Detection`
4. **Health Check Flow**: Select `Corrupt File Detection`
5. Click **Save**

### Run Initial Scan
1. Go to **Staging** tab
2. Click **Scan All**
3. Check **Files** tab for errors
4. Review logs at **Logs** tab

**Expected Results**: Will identify 4+ corrupt files in your quarantine folder

---

## 3. Workflow 2: Quality Analysis

**Purpose**: Analyze bitrates and find low-quality files

### Create Flow
1. **Flows** → **Add Flow**
2. Name: `Quality Analysis`
3. Add plugins:

#### Plugin 1: File Info
- **Plugin**: `Community: Get File Info`
- **Action**: Extract metadata

#### Plugin 2: Bitrate Check
- **Plugin**: `Community: Check Bitrate`
- **Settings**:
  - MP3 minimum: 192 kbps
  - FLAC minimum: 500 kbps
  - Tag low-quality files

### Configure
- **Processing Order**: Size (largest first)
- **Priority**: Low (background task)

### Results
After scanning, you'll see:
- Total files analyzed
- Files below quality threshold
- Bitrate distribution

---

## 4. Workflow 3: Low-Quality MP3 Upgrade

**Purpose**: Convert MP3s <192kbps to better quality

### Create Flow
1. Name: `MP3 Quality Upgrade`
2. Add plugins:

#### Plugin 1: Filter Input
- **Plugin**: `Community: Check Codecs`
- **Codec**: MP3
- **Bitrate**: < 192 kbps
- **Action**: Continue

#### Plugin 2: Transcode
- **Plugin**: `Community: Transcode to Opus`
- **Settings**:
  - Target bitrate: 192 kbps VBR
  - Quality: 9 (highest)
  - Keep metadata: Yes
- **Container**: Keep original (.mp3 → .opus)

#### Plugin 3: Replace Original
- **Plugin**: `Community: Replace Original`
- **Backup**: Yes (to `/temp/backups`)

### Before Running
**Test on a few files first**:
1. Set **File Limit**: 5
2. Monitor results in **Staging**
3. Verify quality with audio player
4. Once satisfied, remove file limit

---

## 5. Workflow 4: FLAC Space Optimization

**Purpose**: Compress FLAC files that don't benefit from lossless

### Target Files
Good candidates for lossy conversion:
- Ambient music
- Electronic music
- Podcasts/audiobooks
- Live recordings with audience noise

### Create Flow
1. Name: `FLAC Optimization`
2. Add plugins:

#### Plugin 1: Filter FLAC
- **Plugin**: `Community: Filter by Codec`
- **Codec**: FLAC
- **Action**: Continue if FLAC

#### Plugin 2: Genre Filter (Optional)
- **Plugin**: `Community: Filter by Tag`
- **Tag**: Genre
- **Values**: Ambient, Electronic, Experimental
- **Action**: Continue if matched

#### Plugin 3: Transcode
- **Plugin**: `Community: Transcode to Opus`
- **Settings**:
  - Target bitrate: 256 kbps VBR
  - Quality: 10 (maximum)
  - Preserve metadata: Yes

#### Plugin 4: Size Check
- **Plugin**: `Community: Check File Size Ratio`
- **Min savings**: 30%
- **Action**: Only keep if >30% smaller

### Safety Settings
- **Backup originals**: Yes
- **Test batch size**: 10 files
- **Verify before deletion**: 24 hours

**Expected Savings**: 40-60% smaller files, transparent quality

---

## 6. Workflow 5: Audio Standardization

**Purpose**: Normalize volume and clean up audio streams

### Create Flow
1. Name: `Audio Normalization`
2. Add plugins:

#### Plugin 1: ReplayGain
- **Plugin**: `Community: Add ReplayGain Tags`
- **Method**: EBU R128
- **Target**: -18 LUFS

#### Plugin 2: Remove Extras
- **Plugin**: `Community: Remove Streams`
- **Keep**: Primary audio only
- **Remove**: Commentary tracks, extras

#### Plugin 3: Metadata Cleanup
- **Plugin**: `Community: Clean Metadata`
- **Remove**: Empty tags, duplicates
- **Standardize**: Artist/Album naming

---

## 7. Workflow 6: Portable Library Creation

**Purpose**: Create smaller copies for mobile devices

### Create Output Library
1. **Libraries** → **Add Library**
2. **Source**: `/media/music`
3. **Output**: `/media/music-portable`
4. **Processing**: Copy mode (keep originals)

### Create Flow
1. Name: `Portable Conversion`
2. Add plugins:

#### Plugin 1: Universal Transcode
- **Plugin**: `Community: Transcode All Audio`
- **Target codec**: Opus
- **Bitrate**: 128-160 kbps VBR
- **Sample rate**: 48kHz

#### Plugin 2: Metadata Preserve
- **Plugin**: `Community: Copy All Tags`
- **Include**: All metadata + cover art

### Results
- **Original**: 97GB lossless/high-quality
- **Portable**: ~30GB Opus (transparent quality for mobile)
- **Savings**: 70% reduction

---

## Monitoring & Maintenance

### Check Progress
1. **Staging** tab: See active transcodes
2. **Files** tab: Filter by status
   - Staged: Waiting for processing
   - Transcoded: Successfully processed
   - Error: Failed processing
3. **Statistics** tab: View savings/progress

### Schedule Processing
1. Go to **Options** → **Schedule**
2. Set active hours: Off-peak (2am-6am)
3. Set limits:
   - Max CPU: 50%
   - Max workers: 1
   - Max files/hour: 100

### Backup Strategy
Before running any workflow:
1. Verify Beets database is backed up
2. Enable Tdarr's backup feature
3. Test on small batch (10-20 files)
4. Monitor for 24-48 hours
5. Scale up gradually

---

## Workflow Priority

Run in this order:

1. ✅ **Corrupt Detection** (1-2 hours)
2. ✅ **Quality Analysis** (2-3 hours)
3. **Low-Quality Upgrade** (4-6 hours)
4. **FLAC Optimization** (8-12 hours) *optional*
5. **Audio Standardization** (6-8 hours)
6. **Portable Creation** (12-24 hours) *optional*

**Total Time**: 2-3 days for complete processing
**Expected Storage Savings**: 20-40GB (depending on options chosen)

---

## Troubleshooting

### Common Issues

**Transcoding stuck**:
- Check Tdarr node status
- Verify `/temp` directory has space
- Restart Tdarr: `systemctl restart podman-tdarr`

**Files not processing**:
- Ensure library is scanned
- Check file permissions
- Review **Error** logs in Files tab

**Quality concerns**:
- Start with higher bitrates
- Test on non-critical files
- Use A/B comparison tools

### Rollback
If you need to undo changes:
1. Check `/temp/backups` for originals
2. Restore from Beets if metadata corrupted
3. Use system snapshots if needed

---

## Best Practices

1. **Always test first**: Process 5-10 files before batch
2. **Monitor actively**: Watch first hour of each workflow
3. **Backup everything**: Keep originals until verified
4. **Document changes**: Note what workflows you ran
5. **Use staging**: Don't process entire library at once

Your 97GB library is well-organized thanks to Beets. These Tdarr workflows will optimize storage and quality while maintaining your careful organization.
