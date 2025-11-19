# Immich Storage Configuration Guide

This guide covers the robust storage layout for Immich in nixos-hwc, including storage templates, backup integration, and migration strategies.

## Table of Contents

1. [Overview](#overview)
2. [Storage Architecture](#storage-architecture)
3. [Storage Templates](#storage-templates)
4. [Configuration Examples](#configuration-examples)
5. [Backup Integration](#backup-integration)
6. [Migration Plan](#migration-plan)
7. [Multi-User Setup](#multi-user-setup)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The Immich module in nixos-hwc provides:

- **Declarative storage layout** with separate directories for library, thumbnails, transcoded videos, and profiles
- **Automatic backup integration** for both media files and PostgreSQL database
- **Storage template guidance** for organizing photos by date, user, camera, and album
- **GPU acceleration** for ML processing and video transcoding
- **Database backup** with zstd compression

---

## Storage Architecture

### Directory Structure

```
/mnt/photos/                    # Base path (configurable)
├── library/                    # Primary photo/video library
│   ├── 2025/                  # Organized by storage template
│   │   ├── 01/                # (configured via web UI)
│   │   │   ├── 01/
│   │   │   │   ├── IMG_20250101_120000.jpg
│   │   │   │   └── VID_20250101_143000.mp4
│   │   │   └── 15/
│   │   │       └── IMG_20250115_090000.jpg
│   │   └── 02/
│   │       └── ...
│   └── 2024/
│       └── ...
├── thumbs/                     # Thumbnail cache
│   └── [auto-generated]
├── encoded-video/              # Transcoded videos (H.264/H.265)
│   └── [auto-generated]
└── profile/                    # User profile pictures
    └── [user-id]/

/var/backup/immich-db/          # PostgreSQL database dumps
├── immich.sql.zst             # Latest backup (zstd compressed)
└── [timestamped backups]
```

### Storage Locations

Each storage type is separated for:
- **Performance**: Thumbnails can be on faster storage (SSD)
- **Backup optimization**: Exclude thumbnails from backups (regenerable)
- **Capacity planning**: Monitor growth of each type independently
- **Migration flexibility**: Move transcoded videos to different storage

---

## Storage Templates

### What are Storage Templates?

Storage templates control how Immich organizes uploaded files within the `library/` directory. They use variables to create dynamic folder structures.

### Available Template Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{{y}}` | Year (4 digits) | `2025` |
| `{{yy}}` | Year (2 digits) | `25` |
| `{{MM}}` | Month (01-12) | `01`, `12` |
| `{{MMM}}` | Month (Jan-Dec) | `Jan`, `Dec` |
| `{{dd}}` | Day (01-31) | `01`, `31` |
| `{{hh}}` | Hour (00-23) | `09`, `23` |
| `{{mm}}` | Minute (00-59) | `00`, `59` |
| `{{ss}}` | Second (00-59) | `00`, `59` |
| `{{filename}}` | Original filename | `IMG_1234.jpg` |
| `{{ext}}` | File extension | `jpg`, `mp4` |
| `{{album}}` | Album name (if in album) | `Vacation`, `Family` |
| `{{assetId}}` | Immich asset ID | `abc123...` |

### Recommended Templates

#### 1. **Date-based (Recommended for Most Users)**
```
{{y}}/{{MM}}/{{dd}}/{{filename}}
```
**Result**: `/mnt/photos/library/2025/01/15/IMG_20250115_120000.jpg`

**Pros**:
- Chronological organization
- Easy to locate photos by date
- Works well with backup tools
- Future-proof for long-term storage

**Best for**: General photo management, family photos, travel

#### 2. **Monthly Organization (Simpler)**
```
{{y}}/{{MM}}/{{filename}}
```
**Result**: `/mnt/photos/library/2025/01/IMG_20250115_120000.jpg`

**Pros**:
- Simpler structure with fewer folders
- Good balance between organization and complexity

**Best for**: Users who prefer less granular organization

#### 3. **Album-based (Event-focused)**
```
{{y}}/{{MM}}/{{album}}/{{filename}}
```
**Result**: `/mnt/photos/library/2025/01/Vacation/IMG_20250115_120000.jpg`

**Pros**:
- Organized by event/album
- Mirrors traditional photo album structure
- Easy to share entire albums

**Best for**: Event photographers, users who organize by albums

**Note**: Photos not in albums will be placed in `{{y}}/{{MM}}/{{filename}}`

#### 4. **Camera/Device-based**
```
{{y}}/{{MM}}/{{assetId}}/{{filename}}
```
**Pros**:
- Prevents filename conflicts
- Useful for multi-camera setups

**Best for**: Professional photographers with multiple cameras

### How to Configure Storage Templates

**IMPORTANT**: Storage templates are configured via the Immich web UI, **NOT** via NixOS configuration.

1. **Log in as admin** to your Immich instance at `https://hwc.ocelot-wahoo.ts.net:7443`

2. **Navigate to**: `Administration → Settings → Storage Template`

3. **Use the template builder**:
   - Select variables from the dropdown
   - Preview the structure
   - Test with existing files

4. **Test before applying**:
   - Click "Test" to see how your template will organize files
   - Verify the structure matches your expectations

5. **Apply the template**:
   - Click "Save"
   - **New uploads** will use the new template
   - **Existing files** are NOT automatically moved

6. **Migrate existing files** (optional):
   - Go to `Administration → Jobs`
   - Find "Storage Migration Jobs"
   - Click "Run Job" to reorganize existing files

⚠️ **WARNING**: Storage template migration is a **destructive operation**. Always backup before migrating!

---

## Configuration Examples

### Example 1: Basic Configuration (Current Setup)

```nix
# In profiles/server.nix or machines/server/config.nix
hwc.server.immich = {
  enable = true;

  # Storage configuration (all paths auto-created)
  storage = {
    enable = true;  # Default: true
    basePath = "/mnt/photos";  # All subdirs created here
  };

  # Database and backup
  database = {
    name = "immich";
    user = "immich";
    createDB = false;  # Use existing database
  };

  backup = {
    enable = true;  # Automatically backs up photos + database
    includeDatabase = true;
    schedule = "daily";  # Database backup schedule
  };

  # Performance features
  redis.enable = true;
  gpu.enable = true;
};
```

### Example 2: Custom Storage Paths

```nix
hwc.server.immich = {
  enable = true;

  storage = {
    enable = true;
    basePath = "/mnt/photos";

    locations = {
      library = "/mnt/photos/library";        # Primary storage
      thumbs = "/mnt/fast-ssd/immich-cache";  # Put cache on SSD
      encodedVideo = "/mnt/storage/immich-video";  # Separate video storage
      profile = "/mnt/photos/profile";
    };
  };

  backup = {
    enable = true;
    includeDatabase = true;
    databaseBackupPath = "/var/backup/immich-db";
    schedule = "daily";
  };

  redis.enable = true;
  gpu.enable = true;
};
```

### Example 3: Minimal Configuration (Fallback to Defaults)

```nix
hwc.server.immich = {
  enable = true;
  redis.enable = true;
  gpu.enable = true;
};

# This uses:
# - storage.basePath = "/mnt/photos"
# - Automatic subdirectories
# - backup.enable = true (automatic)
# - database backups enabled
```

---

## Backup Integration

### What Gets Backed Up?

The backup configuration in `machines/server/config.nix` includes:

```nix
hwc.system.services.backup = {
  enable = true;
  local = {
    sources = [
      "/mnt/photos"           # All Immich media (library, thumbs, videos, profiles)
      "/var/backup/immich-db" # PostgreSQL database dumps
      # ... other sources
    ];
  };
};
```

### Backup Schedule

| Component | Schedule | Location | Compression |
|-----------|----------|----------|-------------|
| **Photos/Videos** | Weekly (03:00) | `/mnt/backup` | restic/borg |
| **Database** | Daily (02:00) | `/var/backup/immich-db/` | zstd |

### Backup Verification

```bash
# Check database backups
ls -lh /var/backup/immich-db/

# Check last backup status
systemctl status postgresqlBackup-immich.service

# View backup logs
journalctl -u postgresqlBackup-immich.service -n 50

# Test database restore (DANGER: This overwrites the database!)
# sudo -u postgres psql -d postgres -c "DROP DATABASE immich_test;"
# sudo -u postgres psql -d postgres -c "CREATE DATABASE immich_test;"
# zstdcat /var/backup/immich-db/immich.sql.zst | sudo -u postgres psql -d immich_test
```

### Backup Exclusions (Optional)

If you want to exclude thumbnails from backups (they're regenerable):

```nix
hwc.system.services.backup = {
  local = {
    sources = [
      "/mnt/photos"
    ];
    exclude = [
      "/mnt/photos/thumbs"  # Exclude thumbnail cache (regenerable)
    ];
  };
};
```

---

## Migration Plan

### Scenario 1: Fresh Installation (No Existing Data)

✅ **No migration needed!** Just:

1. Deploy the configuration:
   ```bash
   sudo nixos-rebuild switch
   ```

2. Configure storage template via web UI (see [How to Configure](#how-to-configure-storage-templates))

3. Start uploading photos

### Scenario 2: Existing Immich with Default Layout

**Current structure**:
```
/mnt/photos/
└── upload/
    └── [user-id]/
        └── [date]/
            └── [asset-id]/
                └── files
```

**Migration steps**:

1. **BACKUP FIRST** (CRITICAL):
   ```bash
   # Create a manual backup before migrating
   sudo rsync -av /mnt/photos/ /mnt/backup/immich-pre-migration/

   # Backup database
   sudo -u postgres pg_dump immich | zstd > /var/backup/immich-pre-migration.sql.zst
   ```

2. **Deploy new configuration**:
   ```bash
   sudo nixos-rebuild switch
   ```

3. **Verify directories created**:
   ```bash
   ls -la /mnt/photos/
   # Should see: library, thumbs, encoded-video, profile
   ```

4. **Move existing files** (if needed):

   **Option A: Let Immich handle it** (Recommended)
   - Log in to Immich web UI
   - Go to `Administration → Jobs → Storage Migration Jobs`
   - Click "Run Job"
   - Monitor progress in the UI

   **Option B: Manual migration** (Advanced)
   ```bash
   # Stop Immich services
   sudo systemctl stop immich-server immich-machine-learning

   # Move files to new structure
   sudo mv /mnt/photos/upload/* /mnt/photos/library/

   # Fix permissions
   sudo chown -R immich:immich /mnt/photos/library/

   # Restart services
   sudo systemctl start immich-server immich-machine-learning
   ```

5. **Configure storage template via web UI** (see [How to Configure](#how-to-configure-storage-templates))

6. **Run storage migration job** (optional, for existing files)

7. **Verify**:
   - Check that new uploads use the template structure
   - Verify existing photos are visible
   - Test searching and facial recognition

### Scenario 3: Existing Data with Different Base Path

If your current data is at `/mnt/media/immich` and you want to move to `/mnt/photos`:

1. **Stop Immich**:
   ```bash
   sudo systemctl stop immich-server immich-machine-learning
   ```

2. **Move data**:
   ```bash
   sudo mkdir -p /mnt/photos/library
   sudo rsync -av --progress /mnt/media/immich/ /mnt/photos/library/
   ```

3. **Update configuration**:
   ```nix
   hwc.server.immich.storage.basePath = "/mnt/photos";
   ```

4. **Deploy**:
   ```bash
   sudo nixos-rebuild switch
   ```

5. **Verify and cleanup**:
   ```bash
   # Verify all photos accessible in web UI
   # Then remove old location:
   # sudo rm -rf /mnt/media/immich
   ```

---

## Multi-User Setup

### How Immich Handles Multiple Users

Immich **automatically** creates user-specific namespaces:
- Each user gets a unique internal user ID
- Storage template applies **per-user**
- Users can only see their own photos (unless shared)

### Example Multi-User Storage Structure

```
/mnt/photos/library/
├── [user-alice-id]/
│   ├── 2025/
│   │   ├── 01/
│   │   │   └── 15/
│   │   │       └── IMG_20250115_120000.jpg
│   │   └── 02/
│   └── 2024/
└── [user-bob-id]/
    └── 2025/
        └── 01/
            └── 20/
                └── VID_20250120_150000.mp4
```

### Configuration (Same as Single User)

```nix
hwc.server.immich = {
  enable = true;
  storage.enable = true;
  # Storage template configured per-user via web UI
};
```

### Sharing Between Users

- **Albums**: Share albums with specific users
- **Links**: Generate public links with passwords
- **Partner Sharing**: Full library sharing with partner user

---

## Troubleshooting

### Issue: Storage template not applying

**Symptoms**: New uploads not using configured template

**Solution**:
1. Verify you configured the template in the web UI (not NixOS config)
2. Check for errors in Immich logs:
   ```bash
   journalctl -u immich-server -f
   ```
3. Ensure template variables are valid (no typos)

### Issue: Permission denied when accessing photos

**Symptoms**: 500 errors, "permission denied" in logs

**Solution**:
```bash
# Fix ownership
sudo chown -R immich:immich /mnt/photos/

# Fix permissions
sudo chmod -R 750 /mnt/photos/
```

### Issue: Database backup failing

**Symptoms**: No files in `/var/backup/immich-db/`

**Solution**:
1. Check PostgreSQL backup service:
   ```bash
   systemctl status postgresqlBackup-immich.service
   journalctl -u postgresqlBackup-immich.service
   ```

2. Verify directory permissions:
   ```bash
   sudo ls -la /var/backup/immich-db/
   # Should be owned by postgres:postgres
   ```

3. Manually trigger backup:
   ```bash
   sudo systemctl start postgresqlBackup-immich.service
   ```

### Issue: Storage migration job stuck

**Symptoms**: Migration job runs forever

**Solution**:
1. Check Immich logs:
   ```bash
   journalctl -u immich-server -u immich-machine-learning -f
   ```

2. Check disk space:
   ```bash
   df -h /mnt/photos
   ```

3. Restart Immich services:
   ```bash
   sudo systemctl restart immich-server immich-machine-learning
   ```

### Issue: Out of disk space

**Symptoms**: "No space left on device"

**Solution**:
1. Check disk usage:
   ```bash
   du -sh /mnt/photos/*
   ```

2. Clean up thumbnails (regenerable):
   ```bash
   sudo systemctl stop immich-server immich-machine-learning
   sudo rm -rf /mnt/photos/thumbs/*
   sudo systemctl start immich-server immich-machine-learning
   # Thumbnails will regenerate on access
   ```

3. Clean up encoded videos (if source videos still exist):
   ```bash
   # DANGER: Only if you have originals
   sudo rm -rf /mnt/photos/encoded-video/*
   # Restart Immich to re-transcode on access
   ```

---

## Best Practices

### 1. Always Backup Before Changes

```bash
# Create full backup before storage template changes
sudo rsync -av /mnt/photos/ /mnt/backup/immich-pre-change-$(date +%Y%m%d)/
```

### 2. Test Storage Template First

- Use the "Test" feature in the web UI
- Apply to a test upload before migrating all files

### 3. Monitor Disk Space

```bash
# Add to cron or systemd timer
df -h /mnt/photos | mail -s "Immich Disk Usage" admin@example.com
```

### 4. Regular Database Backups

The module automatically backs up the database daily. To manually backup:

```bash
sudo systemctl start postgresqlBackup-immich.service
```

### 5. Keep Backups Offsite

```nix
hwc.system.services.backup = {
  cloud.enable = true;  # Enable cloud backup for offsite storage
};
```

### 6. Use GPU Acceleration

```nix
hwc.server.immich.gpu.enable = true;
hwc.infrastructure.hardware.gpu.enable = true;
```

This speeds up:
- Video transcoding (7x faster)
- Thumbnail generation (16x faster)
- ML processing (15x faster)

---

## References

- **Immich Official Docs**: https://docs.immich.app/
- **Storage Templates**: https://docs.immich.app/administration/storage-template/
- **Environment Variables**: https://docs.immich.app/install/environment-variables/
- **GPU Setup Guide**: See `IMMICH-GPU-SETUP.md` in this directory
- **NixOS PostgreSQL Backup**: https://search.nixos.org/options?query=services.postgresqlBackup

---

## Summary

| Feature | Status | Notes |
|---------|--------|-------|
| **Storage Layout** | ✅ Implemented | Separate dirs for library, thumbs, videos, profiles |
| **Storage Templates** | ✅ Supported | Configured via web UI (not NixOS) |
| **Database Backup** | ✅ Automated | Daily at 02:00, zstd compression |
| **Media Backup** | ✅ Integrated | Weekly at 03:00 via restic/borg |
| **GPU Acceleration** | ✅ Enabled | NVIDIA P1000 support |
| **Multi-User** | ✅ Supported | Automatic user namespacing |

**Recommended Storage Template**: `{{y}}/{{MM}}/{{dd}}/{{filename}}`

**Next Steps**:
1. Deploy configuration: `sudo nixos-rebuild switch`
2. Log in to Immich web UI
3. Configure storage template: `Administration → Settings → Storage Template`
4. Upload test photo to verify template
5. (Optional) Migrate existing files via Jobs UI
