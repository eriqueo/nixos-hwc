# Media Storage Audit & Cleanup Report
**Date:** 2025-12-04
**Total Used:** 5.5TB / 7.3TB (80% full)
**Goal:** Free up space + organize for 2.7TB backup capacity

---

## 🔴 CRITICAL ISSUES

### 1. Surveillance Data: **1.7TB** (31% of total!)
**Problem:** Multiple Frigate instances with overlapping/old data

| Directory | Size | Last Modified | Status |
|-----------|------|---------------|--------|
| `/mnt/media/surveillance/frigate-v2` | 646GB | Nov 23, 2025 | ✅ CURRENT |
| `/mnt/media/surveillance/frigate` | 679GB | Jun 1, 2025 | ⚠️ OLD (6 months) |
| `/mnt/media/surveillance/recordings` | 385GB | May 31, 2025 | ⚠️ OLD (7 months) |
| `/mnt/media/surveillance/clips` | 9.9GB | Oct 15, 2025 | ⚠️ OLD |

**Current Retention:** 7 days per camera (config.yml)
**Actual Data:** 6-7 months of recordings!

**Recommended Actions:**
```bash
# SAFE TO DELETE (1.06TB freed):
sudo rm -rf /mnt/media/surveillance/frigate      # 679GB (old v1 data)
sudo rm -rf /mnt/media/surveillance/recordings   # 385GB (orphaned)

# REVIEW BEFORE DELETE:
# Check if frigate-v2 is current, then delete clips
```

**After cleanup:**
- Surveillance: ~650GB (current frigate-v2 only)
- **Savings: 1.06TB** ✅

---

### 2. Duplicate Files Found

#### Band of Brothers Extras (17.4GB duplicate)
```
/mnt/media/tv/Band of Brothers (2001)/Specials/
├── Band.Of.Brothers.S01.Extras.iNTERNAL.1080p.BluRay.x264.1-TENEIGHTY-Obfuscated.mkv (8.7GB)
└── Band of Brothers - Extras.mkv (8.7GB)  # DUPLICATE!
```

**Recommended:** Delete one copy, save **8.7GB**

---

### 3. Quarantine Folders (71GB)

| Folder | Size | Purpose |
|--------|------|---------|
| `/mnt/media/quarantine` | 26GB | Mixed content |
| `/mnt/media/.quarantine` | 45GB | Hidden duplicates |

**Recommended:** Review and either:
- Move valid files to proper locations
- Delete if already in library
- **Potential savings: 50-70GB**

---

### 4. Oversized Remux Files (Example)

| File | Size | Encoding | Recommendation |
|------|------|----------|----------------|
| Godfather Part II (1974) Remux-1080p.mkv | 38GB | Lossless | Re-encode to 8-10GB |
| Incredibles 2 (2018) Remux-1080p.mkv | 22GB | Lossless | Re-encode to 6-8GB |
| Mary Poppins (1964) Bluray-1080p.mkv | 22GB | Lossless | Re-encode to 6-8GB |
| Vegas Vacation (1997) Remux-1080p.mkv | 20GB | Lossless | Re-encode to 5-7GB |

**Estimated savings from re-encoding 10 largest:** ~150-200GB

---

## 📊 Storage Breakdown

```
5.5TB Total Used:
├── 2.1TB (38%) - TV Shows
├── 1.7TB (31%) - Surveillance ⚠️ CLEANUP TARGET
├── 1.2TB (22%) - Movies
├── 261GB (5%) - Music
├── 132GB (2%) - Backups
├── 92GB (2%) - Pictures
└── <100GB - Other
```

---

## 🎯 CLEANUP PLAN

### Phase 1: LOW-RISK (Immediate) - **1.13TB freed**
1. ✅ **Delete old Frigate data** (1.06TB)
   ```bash
   sudo rm -rf /mnt/media/surveillance/frigate
   sudo rm -rf /mnt/media/surveillance/recordings
   ```

2. ✅ **Delete Band of Brothers duplicate** (8.7GB)
   ```bash
   rm "/mnt/media/tv/Band of Brothers (2001)/Specials/Band.Of.Brothers.S01.Extras.iNTERNAL.1080p.BluRay.x264.1-TENEIGHTY-Obfuscated.mkv"
   ```

3. ✅ **Review and clean quarantine** (50-70GB)
   ```bash
   # Manual review required
   cd /mnt/media/quarantine
   cd /mnt/media/.quarantine
   ```

**After Phase 1:** ~4.4TB used (60% full) ✅

### Phase 2: OPTIMIZATION (Optional) - **200-400GB freed**
1. Re-encode 10 largest Remux files (150-200GB saved)
2. Deduplicate music library with beets (50-100GB saved)
3. Clean up `/mnt/media/backups` (132GB - review if needed)
4. Clean up `/mnt/media/cache` (18GB)

**After Phase 2:** ~4.0TB used (55% full) ✅

### Phase 3: MAINTENANCE (Ongoing)
1. ✅ **Configure Frigate auto-cleanup** (keep 7 days max)
2. ✅ **Add media quarantine cleanup** (auto-delete >90 days)
3. ✅ **Schedule monthly duplicate scan**

---

## 🔧 FRIGATE RETENTION FIX

**Current Issue:** Config says "7 days" but old data isn't being deleted

**Solution:** Add global retention + cleanup schedule

```yaml
# Add to /home/eric/.nixos/domains/server/frigate/config/config.yml

record:
  enabled: true
  retain:
    days: 7  # Global default
    mode: all
  events:
    retain:
      default: 10  # Event clips
      mode: active_objects
```

**Automated Cleanup Schedule:**
```nix
# Add to machines/server/config.nix
systemd.timers.frigate-cleanup = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.frigate-cleanup = {
  script = ''
    # Delete recordings older than 7 days
    find /mnt/media/surveillance/frigate-v2/recordings -type f -mtime +7 -delete
    # Delete clips older than 10 days
    find /mnt/media/surveillance/frigate-v2/clips -type f -mtime +10 -delete
  '';
};
```

---

## 📋 BACKUP STRATEGY (Post-Cleanup)

**After Phase 1 cleanup:** ~4.4TB used

**Backup Plan for 2.7TB Pool:**
```nix
# Recommended backup sources (fits in 2.7TB):
sources = [
  "/home"                  # 11GB - Critical
  "/etc/nixos"            # 29MB - Critical
  "/opt/business"         # 96KB - Critical
  "/mnt/media/pictures"   # 92GB - Critical (irreplaceable)
  # EXCLUDE media (replaceable):
  # "/mnt/media/movies"   # 1.2TB - Can re-download
  # "/mnt/media/tv"       # 2.1TB - Can re-download
  # "/mnt/media/music"    # 261GB - Can re-download
  # "/mnt/media/surveillance" # 650GB - Keep only current, auto-rotates
];
```

**Total backed up:** ~103GB (well within 2.7TB)

---

## ⚡ QUICK WINS

**Run these commands to free 1TB+ immediately:**

```bash
# 1. Delete old Frigate data (1.06TB freed)
sudo rm -rf /mnt/media/surveillance/frigate
sudo rm -rf /mnt/media/surveillance/recordings

# 2. Delete Band of Brothers duplicate (8.7GB freed)
rm "/mnt/media/tv/Band of Brothers (2001)/Specials/Band.Of.Brothers.S01.Extras.iNTERNAL.1080p.BluRay.x264.1-TENEIGHTY-Obfuscated.mkv"

# 3. Check disk usage
df -h /mnt/media
```

---

## 🔍 NEXT STEPS

1. **Review this report** and confirm deletions
2. **Run Phase 1 cleanup** (low-risk, high-impact)
3. **Configure Frigate retention** (prevent future bloat)
4. **Update backup config** (exclude replaceable media)
5. **Test backup** with new configuration
6. **Schedule quarterly audits** (prevent future bloat)

---

**Questions? Let me know which phase you want to start with!**
