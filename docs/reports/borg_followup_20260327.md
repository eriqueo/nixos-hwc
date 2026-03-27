# Borg Backup Follow-Up Report — 2026-03-27

## Summary

Applied all recommended hardening from the ZFS SUSPENDED state incident.
Three areas addressed: ZFS failmode, service timeouts, and daily health monitoring via ntfy.

## Changes Made

### 1. ZFS failmode=continue on backup-pool

**File**: `machines/server/config.nix`

Added a systemd oneshot service that enforces `failmode=continue` on `backup-pool` after every import. This prevents ZFS from blocking all I/O when transient disk errors occur — instead, affected operations get `EIO` and the pool remains accessible.

The property persists in ZFS pool metadata once set, but the service acts as a boot-time safety net.

**Runtime command (run once now)**:
```bash
sudo zpool set failmode=continue backup-pool
zpool get failmode backup-pool   # verify
```

### 2. TimeoutSec on Borg services

**File**: `domains/data/borg/index.nix`

| Service | TimeoutStartSec | Rationale |
|---------|----------------|-----------|
| `borgbackup-job-hwc-backup` | 4h | Normal backup completes in ~1h. 4h catches stuck D-state processes. |
| `borg-check` | 6h | Full integrity check on ~2TB repo. 6h is generous but prevents infinite hangs. |

### 3. Daily backup health check with ntfy

**File**: `domains/data/borg/index.nix` (extended monitoring section)

New `hwc.data.borg.monitoring.healthCheck` option set, enabled in `machines/server/config.nix`.

**What it checks** (daily at 6:00 AM Mountain):
1. Backup timer is active
2. Backup service is not in failed state
3. Last backup completed within 26 hours
4. No borg process running longer than 4 hours (stuck detection)
5. `backup-pool` ZFS health is ONLINE
6. SMART attributes on backup drives (reallocated/pending sectors)

**Notifications** (via `hwc-ntfy-send` → `http://localhost:2586/alerts`):
- **Alert**: priority=urgent, tags=rotating_light,backup — lists all problems
- **Healthy**: priority=low, tags=white_check_mark,backup — confirms last backup age and pool status

**Systemd units created**:
- `borg-health-check.service` — oneshot, runs as root
- `borg-health-check.timer` — daily at 06:00 Mountain Time

### 4. Existing failure notifier reviewed

The existing `hwc-service-failure-notifier@` template service (in `domains/alerts/index.nix`) already catches immediate borg failures via `OnFailure=`. It routes to Slack via n8n webhooks. The borg job is already wired to it:

```nix
onFailure = [ "hwc-service-failure-notifier@borgbackup-job-hwc-backup.service" ];
```

The new health check timer complements this by catching **slow-burn failures** that `OnFailure` misses:
- Stale backups (timer disabled, service not running)
- D-state processes (stuck but not "failed")
- ZFS pool degradation
- SMART drive warnings

No changes made to the existing failure notifier — it continues to work alongside the new health check.

## Steps for Eric

### Immediate (runtime, no rebuild needed)
```bash
# Set failmode on backup-pool now
sudo zpool set failmode=continue backup-pool
zpool get failmode backup-pool

# Verify backup completed from prior session
systemctl status borgbackup-job-hwc-backup.service
sudo borg-hwc list --last 3
```

### Apply NixOS changes
```bash
cd ~/.nixos
git pull   # or fetch the branch changes
sudo nixos-rebuild switch --flake .#hwc-server
```

### Verify after rebuild
```bash
# Check new services exist
systemctl status borg-health-check.timer
systemctl status zfs-failmode-backup-pool.service

# Manual test of health check
sudo systemctl start borg-health-check.service
journalctl -u borg-health-check.service --no-pager

# Verify ntfy received the notification
# Check phone/ntfy app for "Backup OK" or "Backup ALERT"
```

## Files Changed

| File | Change |
|------|--------|
| `machines/server/config.nix` | Added `zfs-failmode-backup-pool` systemd service; enabled `monitoring.healthCheck` |
| `domains/data/borg/index.nix` | Added `TimeoutStartSec` to backup (4h) and check (6h); added health check options, script, service, and timer |
| `domains/data/borg/README.md` | Updated systemd units section and changelog |

## Remaining Concerns

1. **SMART check device paths**: The health check script resolves `/dev/disk/by-id/` symlinks via `readlink -f`. If `zpool status` shows a different path format, the SMART check may need adjustment. Verify after first run.

2. **ntfy server availability**: The health check uses `hwc-ntfy-send` which depends on the ntfy server being up. If ntfy is down when the check runs, the notification silently fails. Consider adding a local log fallback in the future.

3. **Timezone support**: The timer uses `America/Denver` in the OnCalendar spec, which requires systemd >= 245 (NixOS has this). If DST behavior is unexpected, switch to `Etc/MST7MDT` or set `TimezoneOfTimer` explicitly.
