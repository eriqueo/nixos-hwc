# ⚠️ READ BEFORE USING TDARR

## Your Files Are Safe - Here's How

I've implemented **5 layers of protection** to ensure your media files are never lost or corrupted:

### 1️⃣ Non-Destructive Mode (DEFAULT)
- Tdarr creates NEW transcoded files
- Original files are NEVER touched
- You manually verify quality before enabling auto-replace

### 2️⃣ Pre-Transcode Validation
- Files validated before transcoding starts
- Bad/corrupt files are skipped
- Checksums created for every file

### 3️⃣ Post-Transcode Validation
- Transcoded files verified as valid video
- Duration checked (must match original ±1 second)
- Bad transcodes are rejected automatically

### 4️⃣ Safety Scripts (Included)
```bash
tdarr-safety-check          # Daily health check
tdarr-pre-transcode <file>  # Validate before transcode
tdarr-post-transcode <orig> <new>  # Validate after
```

### 5️⃣ 3-Phase Testing Workflow (3-4 weeks)
- **Week 1**: Test 10-20 files (manual verification)
- **Week 2-3**: One TV show (still non-destructive)
- **Week 4+**: Full deployment (only if everything perfect)

---

## 🚀 Quick Start (Safe Mode)

**Step 1**: Run safety check
```bash
tdarr-safety-check
```

**Step 2**: Create test directory with 10-20 files
```bash
sudo mkdir -p /mnt/media/test-transcode
# Copy diverse files: different codecs, sizes, qualities
sudo cp /mnt/media/tv/Show/Episode.mkv /mnt/media/test-transcode/
```

**Step 3**: Configure Tdarr
- Go to: https://hwc.ocelot-wahoo.ts.net:8265
- Add Library → Source: `/media/test-transcode`
- **CRITICAL**: Set "Replace Original" to **OFF**
- Output: `/temp/transcoded/`

**Step 4**: Test transcode
- Original files stay safe in `/media/test-transcode`
- New files appear in `/temp/transcoded/`

**Step 5**: Manually verify quality
- Play both original and transcoded files
- Check for artifacts, audio sync, subtitle issues
- Verify file plays on all devices

**Step 6**: Only after 2-3 weeks of perfect results
- Enable "Replace Original" mode
- Expand to more libraries gradually

---

## 📚 Documentation

**Read these in order**:

1. **TDARR-SAFETY-TLDR.md** (2 minutes)
   - Quick overview of safety features

2. **TDARR-SAFETY-GUIDE.md** (15 minutes)
   - Complete safety guide
   - 3-phase testing workflow
   - Troubleshooting and recovery

3. **NEW-SERVICES-IMPLEMENTATION.md** (30 minutes)
   - Full Tdarr setup instructions
   - Configuration examples
   - Performance expectations

---

## ✅ Safety Checklist

Before enabling "Replace Original":

- [ ] Ran `tdarr-safety-check` - passed
- [ ] Tested on 10-20 diverse files
- [ ] Manually verified quality on all test files
- [ ] Checked transcoded files play on all devices
- [ ] Verified file sizes reduced 40-70%
- [ ] Tested on one complete TV show (1-2 seasons)
- [ ] No errors or quality issues for 2+ weeks
- [ ] Have full backups of /mnt/media

**Only enable auto-replace after ALL boxes checked!**

---

## 🚨 Emergency Recovery

If something goes wrong:

**Stop Tdarr immediately**:
```bash
sudo systemctl stop podman-tdarr
```

**Restore from backup**:
```bash
# Originals are in: /mnt/media/.tdarr-originals-backup/
# Checksums are in: /mnt/hot/processing/tdarr-backups/

# Restore a file:
sudo cp /mnt/media/.tdarr-originals-backup/file.mkv /mnt/media/tv/Show/
```

**Disable Tdarr**:
```nix
# Edit profiles/server.nix:
hwc.services.containers.tdarr.enable = false;

# Rebuild:
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## 🎯 Bottom Line

**Your files CANNOT be lost because**:
1. ✅ Originals never touched (non-destructive mode)
2. ✅ You manually verify quality first
3. ✅ Multiple validation layers
4. ✅ Checksum backups created
5. ✅ 3-phase testing workflow

**Follow the guide = zero risk**

---

**Questions?** Read the full safety guide: `docs/TDARR-SAFETY-GUIDE.md`
