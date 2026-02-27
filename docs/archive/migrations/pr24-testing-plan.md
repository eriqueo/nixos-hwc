# PR #24 Paths Refactor - Testing Plan

**Version**: 1.0
**Date**: 2026-01-12
**Purpose**: Comprehensive validation plan for paths refactor after successful build

---

## Testing Philosophy

**Risk-Based Approach**: Test critical paths first, then supporting systems
**Validation Strategy**: Verify path resolution → service startup → runtime functionality

---

## Pre-Test Checklist

Before starting tests, verify baseline system health:

```bash
# 1. Verify build completed successfully
sudo nixos-rebuild build --flake .#hwc-laptop  # or hwc-server
echo "Exit code: $?"

# 2. Check system generation
sudo nixos-rebuild list-generations | head -5

# 3. Verify no immediate errors in journal
sudo journalctl -b -p err --no-pager | wc -l
```

---

## Phase 1: Critical Path Resolution (BLOCKER TESTS)

**Goal**: Verify all paths resolve correctly and directories exist
**Risk**: HIGH - Path resolution failures will cascade to all services

### Test 1.1: Core Path Variables
```bash
# Verify environment variables are set
echo "=== Core Path Variables ==="
env | grep HWC_ | sort

# Expected variables:
# HWC_HOT_STORAGE, HWC_MEDIA_STORAGE, HWC_USER_HOME, etc.

# Verify they resolve to correct paths
test -d "$HWC_HOT_STORAGE" && echo "✓ Hot storage exists" || echo "✗ Hot storage missing"
test -d "$HWC_MEDIA_STORAGE" && echo "✓ Media storage exists" || echo "✗ Media storage missing"
test -d "$HWC_USER_HOME" && echo "✓ User home exists" || echo "✗ User home missing"
```

### Test 1.2: Machine-Specific Overrides
```bash
# Verify overrides applied correctly (server only)
# Expected: /mnt/hot, /mnt/media (not ~/storage/*)
echo "Hot storage: $HWC_HOT_STORAGE"
echo "Media storage: $HWC_MEDIA_STORAGE"

# On server, these should be /mnt/* paths
# On laptop, these should be ~/storage/* paths
```

### Test 1.3: HWC Service Directories
```bash
# Verify minimal materializer created core directories
echo "=== HWC Service Directories ==="
ls -ld /var/lib/hwc /var/cache/hwc /var/log/hwc 2>&1

# Expected: all three directories exist with 0755 eric:users
```

### Test 1.4: Path Primitive Module Evaluation
```bash
# Verify paths.nix evaluates without errors
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.paths.hot.root --json
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.paths.media.root --json
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.paths.user.home --json

# Should return valid paths, not errors
```

**Pass Criteria**: All paths resolve, all HWC directories exist, no evaluation errors

---

## Phase 2: Service Startup Validation (HIGH PRIORITY)

**Goal**: Verify all services start without path-related errors
**Risk**: HIGH - Service failures indicate path misconfigurations

### Test 2.1: System Service Health
```bash
# Check all system services are active
systemctl --failed --no-pager

# Should show "0 loaded units listed"

# Check for path-related errors in last boot
sudo journalctl -b -p err --no-pager | grep -i "path\|directory\|no such file"
```

### Test 2.2: Updated Consumer Services

#### Beets (if enabled)
```bash
# Verify beets service (or container) started
systemctl status beets 2>/dev/null || echo "Beets not enabled (native)"
sudo podman ps -a --filter name=beets 2>/dev/null || echo "Beets not enabled (container)"

# Check beets can access music directory
beet stats 2>&1 | head -5
```

#### Frigate (if enabled)
```bash
# Verify Frigate container running
sudo podman ps --filter name=frigate

# Check Frigate media path exists and is writable
test -w "$HWC_MEDIA_STORAGE/surveillance/frigate/media" && \
  echo "✓ Frigate media path writable" || \
  echo "✗ Frigate media path issue"

# Check Frigate logs for path errors
sudo podman logs frigate 2>&1 | tail -20 | grep -i "error\|path"
```

#### Pi-hole (if enabled)
```bash
# Verify Pi-hole container running
sudo podman ps --filter name=pihole

# Check Pi-hole data directory
ls -l /opt/networking/pihole/ 2>&1

# Verify Pi-hole responding
dig @127.0.0.1 -p 5053 google.com +short | head -1
```

#### Storage Cleanup Service
```bash
# Verify storage service exists
systemctl status hwc-storage-cleanup.timer 2>&1 | head -10

# Check it can access hot storage paths
systemctl cat hwc-storage-cleanup.service | grep ExecStart
```

### Test 2.3: Monitoring Services (Use State/Cache/Logs)
```bash
# These services were updated to use hwc.paths.state/cache/logs

# Prometheus
systemctl status prometheus 2>&1 | head -5
ls -ld /var/lib/hwc/prometheus 2>/dev/null

# Grafana
systemctl status grafana 2>&1 | head -5
ls -ld /var/lib/hwc/grafana 2>/dev/null

# Check for path errors in monitoring logs
sudo journalctl -u prometheus -u grafana -b --no-pager | grep -i "path\|directory" | tail -10
```

### Test 2.4: Server Services (Namespace Changes)
```bash
# These services had namespace changes (hwc.services → hwc.server)

# NTFY
systemctl status ntfy 2>&1 | head -5

# Reverse Proxy (Caddy)
systemctl status caddy 2>&1 | head -5
curl -I https://hwc.ocelot-wahoo.ts.net 2>&1 | head -5

# Transcript API
systemctl status transcript-api 2>&1 | head -5

# Storage service
systemctl status hwc-storage-cleanup.timer 2>&1 | head -5
```

**Pass Criteria**: All enabled services are active, no path errors in logs

---

## Phase 3: Container Volume Mounts (MEDIUM PRIORITY)

**Goal**: Verify containers can access mounted volumes correctly
**Risk**: MEDIUM - Volume issues prevent container functionality

### Test 3.1: Container Volume Inspection
```bash
# List all running containers
sudo podman ps --format "{{.Names}}"

# For each container, inspect volumes
for container in $(sudo podman ps --format "{{.Names}}"); do
  echo "=== $container volumes ==="
  sudo podman inspect $container | jq '.[0].Mounts[] | {Destination, Source, RW}'
  echo ""
done
```

### Test 3.2: Container Path Access
```bash
# Test write access to critical container volumes
# Example: qBittorrent downloads
sudo podman exec qbittorrent touch /downloads/test-write-access 2>&1
sudo podman exec qbittorrent rm /downloads/test-write-access 2>&1

# Example: Sonarr temp directory
sudo podman exec sonarr ls -ld /mnt/hot/processing/sonarr-temp 2>&1

# Check for permission denied errors
sudo podman ps --format "{{.Names}}" | while read container; do
  echo "=== $container logs (last 20 lines) ==="
  sudo podman logs $container 2>&1 | tail -20 | grep -i "permission\|denied\|path"
done
```

### Test 3.3: Media Container Access
```bash
# Jellyfin media access
curl -s http://localhost:8096/health | jq .

# Navidrome music access
curl -s http://localhost:4533/ping

# Immich photo access
curl -s http://localhost:2283/api/server-info/ping
```

**Pass Criteria**: All containers running, volumes mounted, no permission errors

---

## Phase 4: User Environment (LOW PRIORITY)

**Goal**: Verify user-facing paths and PARA structure
**Risk**: LOW - Doesn't affect system services but impacts user workflow

### Test 4.1: PARA Directory Structure
```bash
# Verify PARA directories exist and are accessible
echo "=== PARA Structure ==="
ls -ld ~/000_inbox 2>&1
ls -ld ~/100_hwc 2>&1
ls -ld ~/200_personal 2>&1
ls -ld ~/300_tech 2>&1
ls -ld ~/400_mail 2>&1
ls -ld ~/500_media 2>&1
ls -ld ~/900_vaults 2>&1

# Verify environment variables
echo "Inbox: $HWC_INBOX_DIR"
echo "Work: $HWC_WORK_DIR"
echo "Personal: $HWC_PERSONAL_DIR"
```

### Test 4.2: Application Path Access
```bash
# Test applications can access user paths
# Example: File manager
nautilus ~/000_inbox 2>&1 &
sleep 2
pkill nautilus

# Example: Terminal in work directory
echo "Can cd to work directory:"
cd "$HWC_WORK_DIR" && pwd || echo "Failed"
```

### Test 4.3: SSH and Config Paths
```bash
# Verify SSH path
ls -ld ~/.ssh 2>&1
echo "SSH path: $HWC_USER_HOME/.ssh"

# Verify config path
ls -ld ~/.config 2>&1
echo "Config path: $HWC_USER_HOME/.config"
```

**Pass Criteria**: All PARA directories accessible, user paths resolve correctly

---

## Phase 5: Storage Tier Validation (MEDIUM PRIORITY)

**Goal**: Verify hot/media/cold storage tiers work correctly
**Risk**: MEDIUM - Storage misconfigurations affect media services

### Test 5.1: Storage Tier Paths
```bash
# Verify storage tier structure
echo "=== Storage Tiers ==="
df -h "$HWC_HOT_STORAGE" "$HWC_MEDIA_STORAGE" "$HWC_COLD_STORAGE" 2>&1

# Check expected subdirectories
ls -l "$HWC_HOT_STORAGE/" 2>&1
ls -l "$HWC_MEDIA_STORAGE/" 2>&1
```

### Test 5.2: Storage Service Integration
```bash
# Verify media services can access storage
# *arr services
curl -s http://localhost:7878/api/v3/rootfolder | jq -r '.[].path' # Radarr
curl -s http://localhost:8989/api/v3/rootfolder | jq -r '.[].path' # Sonarr
curl -s http://localhost:8686/api/v1/rootfolder | jq -r '.[].path' # Lidarr

# Download clients
curl -s http://localhost:8080/api/v2/app/preferences | jq .save_path # qBittorrent
curl -s http://localhost:8081/api?mode=get_config | jq .config.misc.complete_dir # SABnzbd
```

### Test 5.3: Storage Cleanup Service
```bash
# Verify cleanup service can access paths
systemctl cat hwc-storage-cleanup.service | grep Environment

# Check cleanup script paths
sudo systemctl start hwc-storage-cleanup.service
sudo journalctl -u hwc-storage-cleanup.service -n 50 --no-pager
```

**Pass Criteria**: All storage tiers accessible, services use correct paths

---

## Phase 6: Secret Path Validation (HIGH PRIORITY)

**Goal**: Verify services can access secrets at correct paths
**Risk**: HIGH - Secret access failures prevent service authentication

### Test 6.1: Secret Files Exist
```bash
# Verify agenix secrets are decrypted
sudo ls -la /run/agenix/ 2>&1

# Check secret permissions (should be 0440, group secrets)
sudo ls -l /run/agenix/ | head -10
```

### Test 6.2: Service Secret Access
```bash
# Check services that use secrets
systemctl status navidrome 2>&1 | grep -i "secret\|password"
systemctl status grafana 2>&1 | grep -i "secret\|password"

# Verify services are in secrets group
sudo systemctl show navidrome | grep SupplementaryGroups
sudo systemctl show grafana | grep SupplementaryGroups
```

### Test 6.3: Age Key Path
```bash
# Verify age key exists
sudo ls -l /etc/sops/age/keys.txt 2>&1

# Test decryption works
sudo age -d -i /etc/sops/age/keys.txt \
  domains/secrets/parts/api/navidrome-admin-password.age 2>&1 | head -1
```

**Pass Criteria**: All secrets decrypted, correct permissions, services can access

---

## Phase 7: Regression Testing (FINAL VALIDATION)

**Goal**: Ensure no functionality broke from refactor
**Risk**: MEDIUM - Catch any subtle breakage not covered by earlier tests

### Test 7.1: Media Playback
```bash
# Test Jellyfin can stream media
# Access Jellyfin UI and play a video for 10 seconds

# Test Navidrome can stream music
# Access Navidrome UI and play a song for 10 seconds
```

### Test 7.2: Download Workflow
```bash
# Test full download → import workflow
# 1. Add a test torrent to qBittorrent
# 2. Verify it downloads to correct path
# 3. Check *arr services detect completion
# 4. Verify import to media library

# Or just check recent downloads imported correctly
ls -lt "$HWC_MEDIA_STORAGE"/tv/ | head -5
ls -lt "$HWC_MEDIA_STORAGE"/movies/ | head -5
```

### Test 7.3: Backup Verification
```bash
# Verify backup service can access paths
systemctl status hwc-backup.timer 2>&1
sudo systemctl start hwc-backup.service
sudo journalctl -u hwc-backup.service -n 50 --no-pager
```

### Test 7.4: AI Services (if enabled)
```bash
# Ollama
curl -s http://localhost:11434/api/tags | jq .models[].name

# Open WebUI
curl -I http://localhost:3000 2>&1 | head -5

# Verify model storage path
ls -l /opt/ai/models/ 2>&1 | head -5
```

**Pass Criteria**: All workflows functional, no regressions detected

---

## Automated Test Script

Run all critical tests automatically:

```bash
#!/usr/bin/env bash
# pr24-validation.sh - Automated testing for paths refactor

set -e
PASS=0
FAIL=0

test_cmd() {
  local name="$1"
  local cmd="$2"
  echo -n "Testing $name... "
  if eval "$cmd" >/dev/null 2>&1; then
    echo "✓ PASS"
    ((PASS++))
  else
    echo "✗ FAIL"
    ((FAIL++))
  fi
}

echo "=== PR #24 Paths Refactor - Automated Validation ==="
echo ""

# Phase 1: Path Resolution
echo "PHASE 1: Path Resolution"
test_cmd "Hot storage exists" "test -d \"\$HWC_HOT_STORAGE\""
test_cmd "Media storage exists" "test -d \"\$HWC_MEDIA_STORAGE\""
test_cmd "User home exists" "test -d \"\$HWC_USER_HOME\""
test_cmd "/var/lib/hwc exists" "test -d /var/lib/hwc"
test_cmd "/var/cache/hwc exists" "test -d /var/cache/hwc"
test_cmd "/var/log/hwc exists" "test -d /var/log/hwc"
echo ""

# Phase 2: Service Health
echo "PHASE 2: Service Health"
test_cmd "No failed services" "systemctl --failed --no-pager | grep -q '0 loaded units'"
test_cmd "Caddy running" "systemctl is-active caddy"
test_cmd "Prometheus running" "systemctl is-active prometheus"
test_cmd "Grafana running" "systemctl is-active grafana"
echo ""

# Phase 3: Container Health (if server)
if [[ -f /etc/nixos/machines/server/config.nix ]]; then
  echo "PHASE 3: Container Health"
  test_cmd "qBittorrent running" "sudo podman ps | grep -q qbittorrent"
  test_cmd "Sonarr running" "sudo podman ps | grep -q sonarr"
  test_cmd "Radarr running" "sudo podman ps | grep -q radarr"
  echo ""
fi

# Summary
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -eq 0 ]]; then
  echo "✓ ALL TESTS PASSED"
  exit 0
else
  echo "✗ SOME TESTS FAILED"
  exit 1
fi
```

Save as `workspace/nixos/pr24-validation.sh` and run:
```bash
chmod +x workspace/nixos/pr24-validation.sh
./workspace/nixos/pr24-validation.sh
```

---

## Rollback Plan

If critical tests fail:

```bash
# 1. Identify failing generation
sudo nixos-rebuild list-generations

# 2. Rollback to previous generation
sudo nixos-rebuild switch --rollback

# 3. Verify system is functional
systemctl --failed

# 4. Document failures for fixing
sudo journalctl -b -p err --no-pager > /tmp/rollback-errors.log
```

---

## Success Criteria

**Minimum for Production:**
- ✅ Phase 1: All path resolution tests pass
- ✅ Phase 2: All critical services start
- ✅ Phase 6: All secrets accessible

**Full Validation:**
- ✅ All phases complete without critical failures
- ✅ No service failures in `systemctl --failed`
- ✅ No path errors in `journalctl -b -p err`
- ✅ Automated test script passes

---

## Notes

- **Test on laptop first**: Lower risk, easier rollback
- **Then test on server**: Higher complexity, more services
- **Document any failures**: Create issues for non-critical problems
- **Verify monitoring**: Check Grafana dashboards show metrics correctly

**Testing Time Estimate:**
- Manual testing: 30-45 minutes
- Automated script: 2-5 minutes
- Full validation: 1 hour including observation

---

**Last Updated**: 2026-01-12
**Tested By**: [Pending]
**Result**: [Pending]
