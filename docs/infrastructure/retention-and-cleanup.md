# Retention & Cleanup Policies

**Status:** Production-ready
**Last Updated:** 2025-12-04
**Owner:** Infrastructure Team

---

## Overview

This document defines the declarative retention and cleanup policies for the HWC infrastructure, ensuring automated data lifecycle management without manual intervention.

### Design Principles

1. **Declarative First:** All retention policies defined in NixOS configuration
2. **Fail-Safe:** Automated enforcement even if primary application fails
3. **Predictable:** Time-based and size-based limits clearly documented
4. **Observable:** All cleanup operations logged to systemd journal
5. **Reproducible:** Configuration in version control, deployable to any machine

---

## Table of Contents

1. [Surveillance Retention](#surveillance-retention)
2. [Backup Retention](#backup-retention)
3. [Media Storage Policies](#media-storage-policies)
4. [Automated Cleanup Services](#automated-cleanup-services)
5. [Monitoring & Verification](#monitoring--verification)
6. [Troubleshooting](#troubleshooting)

---

## Surveillance Retention

### Policy Summary

| Type | Retention Period | Auto-Cleanup | Storage Path |
|------|------------------|--------------|--------------|
| **Recordings** | 7 days | ✅ Daily | `/mnt/media/surveillance/frigate-v2/recordings/` |
| **Event Clips** | 10 days | ✅ Daily | `/mnt/media/surveillance/frigate-v2/clips/` |
| **Snapshots** | 10 days | ✅ Daily | `/mnt/media/surveillance/frigate-v2/clips/snapshots/` |

### Implementation

**Primary:** Frigate built-in retention (config.yml)
```yaml
record:
  enabled: true
  retain:
    days: 7          # Keep recordings for 7 days
    mode: all        # All recordings (not just events)
  events:
    retain:
      default: 10    # Event clips kept for 10 days
      mode: active_objects
```

**Fail-Safe:** systemd timer backup enforcement
```nix
# machines/server/config.nix
systemd.timers.frigate-cleanup = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";           # Runs every day
    Persistent = true;               # Catch up if missed
    RandomizedDelaySec = "1h";       # Spread load
  };
};
```

### Expected Storage Usage

**Per Camera (1280x720 @ 1 fps):**
- Recordings: ~15-20GB per week
- Event clips: ~2-5GB per week

**Three Cameras Total:**
- ~45-60GB recordings (7 days)
- ~10-15GB clips (10 days)
- **Total: 55-75GB steady state**

### Verification Commands

```bash
# Check current surveillance storage
du -sh /mnt/media/surveillance/frigate-v2/*

# Check oldest recordings (should be < 7 days)
find /mnt/media/surveillance/frigate-v2/recordings -type f -name "*.mp4" | head -1 | xargs stat -c "%y %n"

# Check oldest clips (should be < 10 days)
find /mnt/media/surveillance/frigate-v2/clips -type f -name "*.mp4" | head -1 | xargs stat -c "%y %n"

# Check cleanup timer status
systemctl status frigate-cleanup.timer
journalctl -u frigate-cleanup.service -n 20
```

---

## Backup Retention

### Policy Summary

| Backup Type | Retention | Frequency | Storage Pool |
|-------------|-----------|-----------|--------------|
| **Daily** | 14 backups | Weekly Mon 03:00 | ZFS backup-pool (2.7TB) |
| **Weekly** | 8 backups | Every Sunday | ZFS backup-pool |
| **Monthly** | 12 backups | 1st of month | ZFS backup-pool |

### What Gets Backed Up

**Included (Critical/Irreplaceable Data):**
```nix
sources = [
  "/home"                     # 11GB - User data, configs, nixos repo
  "/opt/business"             # 96KB - Business data
  "/mnt/media/pictures"       # 92GB - IRREPLACEABLE photos
  "/mnt/media/databases"      # 252MB - Database backups
  "/mnt/media/backups"        # 132GB - Other backups
];

# Total: ~235GB (9% of 2.7TB pool)
```

**Excluded (Replaceable Data):**
- `/mnt/media/movies` (1.2TB) - Can re-download
- `/mnt/media/tv` (2.1TB) - Can re-download
- `/mnt/media/music` (261GB) - Can re-download
- `/mnt/media/surveillance` (646GB) - Auto-rotates every 7 days

### Backup Schedule

```
┌─────────────────────────────────────────────────────┐
│ Monday 03:00 AM: Full backup of critical data      │
│ ├─ If Sunday: Create weekly snapshot               │
│ └─ If 1st: Create monthly snapshot                 │
│                                                     │
│ Daily: Rotate old backups per retention policy     │
│ ├─ Delete daily backups older than 14 days        │
│ ├─ Delete weekly backups older than 8 weeks       │
│ └─ Delete monthly backups older than 12 months    │
└─────────────────────────────────────────────────────┘
```

### Backup Structure

```
/mnt/backup/hwc-server/
├── daily/
│   ├── 2025-12-01_03-00-00/          # Day 1
│   ├── 2025-12-08_03-00-00/          # Day 8
│   └── 2025-12-15_03-00-00/          # Day 15 (14 kept)
├── weekly/
│   ├── 2025-12-01_03-00-00/          # Week 1 (Sunday)
│   ├── 2025-12-08_03-00-00/          # Week 2
│   └── ...                            # (8 weeks kept)
├── monthly/
│   ├── 2025-12-01_03-00-00/          # Month 1
│   └── ...                            # (12 months kept)
└── latest -> daily/2025-12-15_03-00-00/
```

### Verification Commands

```bash
# Check backup status
sudo backup-status

# List all backups
ls -lh /mnt/backup/hwc-server/daily/
ls -lh /mnt/backup/hwc-server/weekly/
ls -lh /mnt/backup/hwc-server/monthly/

# Check ZFS pool health
sudo zpool status backup-pool

# Verify backup timer
systemctl status backup.timer
systemctl list-timers backup*

# Test restore
sudo backup-restore latest /home/eric/.nixos/flake.nix /tmp/test-restore.nix
```

---

## Media Storage Policies

### Current Usage (Post-Cleanup)

```
Total: 4.5TB / 7.3TB (65% full) - 2.5TB free

Breakdown:
├── 2.1TB (47%) - TV Shows             [Replaceable]
├── 1.2TB (27%) - Movies               [Replaceable]
├── 646GB (14%) - Surveillance         [Auto-managed, 7-day rotation]
├── 261GB (6%)  - Music                [Replaceable]
├── 132GB (3%)  - Backups              [Critical - backed up]
├── 92GB  (2%)  - Pictures             [CRITICAL - backed up]
└── <1GB        - Other                [Backed up]
```

### Classification System

| Category | Retention | Backup | Justification |
|----------|-----------|--------|---------------|
| **CRITICAL** | Indefinite | ✅ Weekly | Irreplaceable (photos, configs, business) |
| **REPLACEABLE** | Indefinite | ❌ No | Can re-download (movies, TV, music) |
| **AUTO-MANAGED** | 7-10 days | ❌ No | Surveillance (continuous rotation) |
| **EPHEMERAL** | <30 days | ❌ No | Cache, temp files, downloads |

### Cleanup Triggers

**Manual Review Quarterly:**
- `/mnt/media/quarantine` - Review and delete old files
- `/mnt/media/.quarantine` - Hidden quarantine folder
- `/mnt/media/cache` - Clear old cache files
- `/mnt/media/downloads` - Move or delete completed downloads

**Automated (Future):**
```nix
# TODO: Add to machines/server/config.nix
systemd.timers.media-cleanup = {
  wantedBy = [ "timers.target" ];
  timerConfig.OnCalendar = "monthly";
};
```

---

## Automated Cleanup Services

### Active Services

| Service | Schedule | Purpose | Next Run |
|---------|----------|---------|----------|
| `frigate-cleanup.service` | Daily 00:00 | Enforce surveillance retention | Check: `systemctl list-timers` |
| `backup.service` | Weekly Mon 03:00 | Backup critical data | Check: `systemctl list-timers` |
| `server-backup.service` | Daily 00:01 | Container/DB backups | Check: `systemctl list-timers` |
| `zfs-scrub.service` | Monthly | ZFS data integrity check | Check: `systemctl list-timers zfs-scrub` |
| `zpool-trim.service` | Weekly | ZFS TRIM for performance | Check: `systemctl list-timers zpool-trim` |

### Service Configuration Locations

```
Surveillance: domains/server/frigate/config/config.yml
              machines/server/config.nix (frigate-cleanup)

Backups:      machines/server/config.nix (hwc.system.services.backup)

ZFS:          machines/server/config.nix (services.zfs)
```

### Logs & Monitoring

```bash
# View all cleanup timers
systemctl list-timers --all | grep -E "backup|cleanup|scrub|trim"

# Frigate cleanup logs
journalctl -u frigate-cleanup.service -n 50
sudo tail -f /var/log/backup/backup-local.log

# Backup logs
journalctl -u backup-local.service -n 50
journalctl -u backup.timer

# ZFS health
sudo zpool status -v backup-pool
sudo zfs list
```

---

## Monitoring & Verification

### Daily Checks (Automated)

1. **Backup Health Check** (Weekly Mon 00:00)
   - Verifies latest backup exists
   - Checks ZFS pool health
   - Validates backup integrity

2. **Frigate Cleanup** (Daily 00:00)
   - Deletes old recordings (>7 days)
   - Deletes old clips (>10 days)
   - Logs storage stats

3. **ZFS Scrub** (Monthly)
   - Checksums all data
   - Detects silent corruption
   - Auto-repairs with mirror redundancy

### Manual Verification (Monthly)

```bash
# 1. Check storage usage trends
df -h /mnt/media /mnt/backup

# 2. Verify backup completeness
sudo backup-status
ls -lh /mnt/backup/hwc-server/daily/ | wc -l  # Should be ≤14

# 3. Test restore (sample file)
sudo backup-restore latest /home/eric/.nixos/flake.nix /tmp/test.nix
diff /home/eric/.nixos/flake.nix /tmp/test.nix

# 4. Check ZFS pool health
sudo zpool status -v backup-pool
sudo zpool list -o name,size,allocated,free,fragmentation,health

# 5. Review cleanup logs
journalctl -u frigate-cleanup.service --since "30 days ago" | grep "complete"
```

### Alerts & Notifications

**Backup Failures:**
- Logged to: `/var/log/backup/backup-local.log`
- Systemd journal: `journalctl -u backup-local.service`
- TODO: Integrate with ntfy for push notifications

**Storage Warnings:**
- Backup requires 50GB free space (configured)
- Fails gracefully if insufficient space
- Logged to systemd journal

---

## Troubleshooting

### Surveillance Storage Not Decreasing

**Symptom:** `/mnt/media/surveillance/frigate-v2` stays above 100GB

**Diagnosis:**
```bash
# Check if cleanup timer is running
systemctl status frigate-cleanup.timer
journalctl -u frigate-cleanup.service -n 20

# Check Frigate config retention
grep -A 5 "retain:" domains/server/frigate/config/config.yml

# Check oldest files
find /mnt/media/surveillance/frigate-v2 -type f -name "*.mp4" -mtime +7 -ls
```

**Solutions:**
1. Verify timer is active: `systemctl enable frigate-cleanup.timer`
2. Manual cleanup: `sudo systemctl start frigate-cleanup.service`
3. Restart Frigate: `sudo systemctl restart podman-frigate.service`

### Backups Failing

**Symptom:** `backup-now` fails or backups not running

**Diagnosis:**
```bash
# Check recent failures
journalctl -u backup-local.service -n 50

# Check ZFS pool
sudo zpool status backup-pool

# Check free space
df -h /mnt/backup

# Verify mount
mountpoint /mnt/backup
```

**Solutions:**
1. If unmounted: `sudo zpool import backup-pool`
2. If space full: Manually delete old backups or expand pool
3. If corrupted: Restore from last known good backup

### ZFS Pool Degraded

**Symptom:** `zpool status` shows DEGRADED

**Diagnosis:**
```bash
# Check pool status
sudo zpool status -v backup-pool

# Check drive health
sudo smartctl -a /dev/sdc
sudo smartctl -a /dev/sdd
```

**Solutions:**
1. If drive failed: Replace drive and resilver
   ```bash
   sudo zpool replace backup-pool /dev/sdX /dev/NEW_DRIVE
   ```
2. If degraded but no failures: Run scrub
   ```bash
   sudo zpool scrub backup-pool
   ```

---

## Configuration Reference

### Key Files

```
Frigate Config:
  domains/server/frigate/config/config.yml

Backup Config:
  machines/server/config.nix (hwc.system.services.backup)

Cleanup Timers:
  machines/server/config.nix (systemd.timers.frigate-cleanup)

ZFS Config:
  machines/server/config.nix (services.zfs, boot.supportedFilesystems)
```

### Default Values

```nix
# Surveillance (Frigate)
record.retain.days = 7
record.events.retain.default = 10

# Backups
backup.local.keepDaily = 14
backup.local.keepWeekly = 8
backup.local.keepMonthly = 12
backup.local.minSpaceGB = 50

# ZFS
services.zfs.autoScrub.interval = "monthly"
services.zfs.trim.interval = "weekly"
```

---

## Future Enhancements

### Planned Improvements

1. **Media Quarantine Auto-Cleanup**
   - Delete files in quarantine folders >90 days old
   - systemd timer for monthly cleanup

2. **ntfy Notifications**
   - Push notifications on backup failures
   - Weekly backup success summary
   - Storage warning alerts

3. **Backup Verification Automation**
   - Monthly automated restore tests
   - Checksum verification
   - Integrity reports

4. **Metrics & Dashboards**
   - Prometheus exporters for backup metrics
   - Grafana dashboard for storage trends
   - Alert rules for failures

5. **Off-Site Backup**
   - Encrypted cloud backup to Proton Drive
   - Critical data only (<100GB)
   - Monthly sync schedule

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-04 | Initial retention policies implemented | Claude + Eric |
| 2025-12-04 | Surveillance cleanup automated (1.08TB freed) | Claude + Eric |
| 2025-12-04 | Backup sources optimized (5.5TB → 235GB) | Claude + Eric |

---

## References

- [Frigate Documentation](https://docs.frigate.video/)
- [ZFS Best Practices](https://openzfs.github.io/openzfs-docs/)
- [NixOS Backup Module](../../../domains/system/services/backup/README.md)
- [Media Audit Report](../../MEDIA_AUDIT_REPORT.md)
- [CHARTER.md](../../CHARTER.md) - Architectural principles
