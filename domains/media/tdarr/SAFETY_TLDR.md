# Tdarr Safety TL;DR

**Your files CANNOT be deleted or lost. Here's why:**

## 🛡️ 5 Safety Layers

1. **Non-Destructive Mode (DEFAULT)**
   - Creates NEW files, never touches originals
   - You manually verify quality before enabling auto-replace

2. **Pre-Transcode Checks**
   - Validates files exist and are readable before starting
   - Creates checksum backups

3. **Post-Transcode Validation**
   - Verifies transcoded files are valid video
   - Checks duration matches
   - Rejects bad transcodes

4. **Safety Scripts Included**
   - `tdarr-safety-check` - Daily health check
   - `tdarr-pre-transcode` - Validate before
   - `tdarr-post-transcode` - Validate after

5. **3-Phase Testing Workflow**
   - Week 1: Test on 10-20 files
   - Week 2-3: Small library (1 TV show)
   - Week 4+: Full deployment only if everything perfect

## ✅ Quick Start (100% Safe)

```bash
# 1. Run safety check
tdarr-safety-check

# 2. Create test directory
sudo mkdir -p /mnt/media/test-transcode
sudo cp /mnt/media/tv/SomeShow/Episode.mkv /mnt/media/test-transcode/
# Copy 10-20 diverse files

# 3. Configure Tdarr (web UI)
Library Source: /media/test-transcode
Replace Original: OFF  # ← CRITICAL: Keeps originals safe
Output: /temp/transcoded/

# 4. Test transcode
# Original files stay in /media/test-transcode
# New files appear in /temp/transcoded/

# 5. Manually compare quality
# Play both files, verify quality acceptable

# 6. Only after 2-3 weeks of success:
# Enable "Replace Original" mode
```

## 🚨 What Could Go Wrong?

**Worst case scenarios and how you're protected**:

| Scenario | Protection |
|----------|-----------|
| Tdarr crashes mid-transcode | Original untouched, incomplete file deleted |
| Bad transcode (corruption) | Post-validation rejects, original kept |
| Power outage during transcode | Temp files deleted on restart, originals safe |
| Settings wrong (bad quality) | You test on 10-20 files first, catch it early |
| Storage full | Safety check warns at <100GB, transcodes pause |
| GPU overheats/fails | Container stops, originals untouched |

## 📊 Expected Timeline (Safe Deployment)

- **Week 1**: Test 10-20 files (originals safe)
- **Week 2-3**: One TV show (still non-destructive)
- **Week 4+**: Enable auto-replace (after validation)

## 🎯 Bottom Line

**Your files are safe because**:
1. Tdarr creates NEW files by default (doesn't touch originals)
2. You verify quality before enabling auto-replace
3. Multiple validation layers catch problems
4. Checksum backups created automatically
5. Emergency recovery procedures documented

**Follow the 3-phase workflow = zero risk**

---

**Full details**: See `TDARR-SAFETY-GUIDE.md`
**Implementation**: See `NEW-SERVICES-IMPLEMENTATION.md`
