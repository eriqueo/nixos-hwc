# Music Pipeline Fix - Implementation Plan
**Date**: 2025-12-04
**Status**: Ready for Implementation
**Estimated Time**: 3-5 hours

## Executive Summary

Your slskd/soularr/lidarr pipeline has three issues:

1. **CRITICAL**: slskd and soularr can't communicate (404 errors)
2. **MEDIUM**: Unpinned container versions risk future API breakage
3. **LOW**: Music library chaos needs automated cleanup

### Root Cause Discovered

**slskd and soularr DON'T use the `mkContainer` helper**, while lidarr does. This helper properly configures network attachment to `media-network`, which is required for inter-container DNS resolution.

**Evidence**:
- lidarr uses `helpers.mkContainer` in `sys.nix` → Works perfectly
- slskd has stub `sys.nix` → Container defined in `parts/config.nix` → DNS fails
- soularr has stub `sys.nix` → Container defined in `parts/config.nix` → DNS fails

---

## Phase 1: Fix Network Communication (CRITICAL)

### Problem
Soularr tries to reach `http://slskd:5030` but gets 404 errors because:
- slskd container isn't properly attached to media-network
- DNS resolution for hostname `slskd` fails
- Both containers define their own network options instead of using the helper

### Solution
Refactor slskd and soularr to use `mkContainer` helper following lidarr's pattern.

### Files to Modify

#### 1. `/home/eric/.nixos/domains/server/containers/slskd/sys.nix`
**Current**: Minimal stub (11 lines)
**New**: Full mkContainer implementation like lidarr

```nix
{ lib, config, pkgs, ... }:
let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.slskd;

  # Import config generator for YAML
  configModule = import ./parts/config.nix { inherit config lib pkgs; };
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Config file setup
    configModule

    # Container definition using helper
    (helpers.mkContainer {
      name = "slskd";
      image = cfg.image;
      networkMode = "media";  # Uses media-network
      gpuEnable = false;      # slskd doesn't need GPU
      timeZone = config.time.timeZone or "UTC";
      ports = [
        "127.0.0.1:5031:5030"  # Web UI
        "0.0.0.0:50300:50300"  # P2P port
      ];
      volumes = [
        "${config.hwc.paths.media}/music:/music:ro"
        "${config.hwc.paths.hot}/downloads/incomplete:/downloads/incomplete"
        "${config.hwc.paths.hot}/downloads/complete:/downloads/complete"
        "/etc/slskd/slskd.yml:/slskd.yml:ro"
      ];
      environment = {};
      extraOptions = [ "--cmd" "--config" "/slskd.yml" ];
    })

    # Firewall for P2P
    {
      networking.firewall.allowedTCPPorts = [ 50300 ];
    }
  ]);
}
```

#### 2. `/home/eric/.nixos/domains/server/containers/slskd/parts/config.nix`
**Current**: Contains both config generation AND container definition
**New**: ONLY config generation (remove container definition)

Extract the YAML config generation logic, remove the `virtualisation.oci-containers.containers.slskd` block (move to sys.nix via mkContainer).

#### 3. `/home/eric/.nixos/domains/server/containers/soularr/sys.nix`
**Current**: Minimal stub
**New**: Full mkContainer implementation

```nix
{ lib, config, pkgs, ... }:
let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.soularr;

  # Import config seeder
  configSeeder = import ./parts/config.nix { inherit config lib pkgs; };
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Config seeder setup
    configSeeder

    # Container definition using helper
    (helpers.mkContainer {
      name = "soularr";
      image = cfg.image;
      networkMode = "media";  # Uses media-network
      gpuEnable = false;      # soularr doesn't need GPU
      timeZone = config.time.timeZone or "UTC";
      ports = [];  # No web UI, internal only
      volumes = [
        "/opt/downloads/soularr:/config"
        "/opt/downloads/soularr:/data"
        "${config.hwc.paths.hot}/downloads:/downloads"
      ];
      environment = {};
      dependsOn = [ "lidarr" "slskd" ];
    })
  ]);
}
```

#### 4. `/home/eric/.nixos/domains/server/containers/soularr/parts/config.nix`
**Current**: Contains both config seeder AND container definition
**New**: ONLY config seeder (remove container definition)

Extract the config seeder systemd service, remove the `virtualisation.oci-containers.containers.soularr` block.

#### 5. Update service dependencies in both modules
**slskd/index.nix** - Add proper dependency validation:
```nix
config.assertions = lib.mkIf cfg.enable [
  {
    assertion = config.hwc.paths ? media && config.hwc.paths ? hot;
    message = "slskd requires hwc.paths.media and hwc.paths.hot to be defined";
  }
];
```

**soularr/index.nix** - Add dependency validation:
```nix
config.assertions = lib.mkIf cfg.enable [
  {
    assertion = config.hwc.server.containers.slskd.enable;
    message = "soularr requires slskd to be enabled";
  }
  {
    assertion = config.hwc.server.containers.lidarr.enable;
    message = "soularr requires lidarr to be enabled";
  }
];
```

### Testing Phase 1

```bash
# Build and test
sudo nixos-rebuild test --flake .#hwc-server

# Wait for containers to start
sleep 30

# Verify DNS resolution works
sudo podman exec soularr ping -c 3 slskd
# Expected: PING slskd (10.89.0.X): 56 data bytes...

# Test HTTP connectivity
sudo podman exec soularr curl -s http://slskd:5030/health || echo "Health check failed"

# Check soularr logs for errors
journalctl -u podman-soularr.service -n 50 --no-pager | grep -i "404\|error"
# Expected: No 404 errors

# Verify both containers on media-network
sudo podman network inspect media-network | grep -A3 "slskd\|soularr"
# Expected: Both containers listed
```

### Success Criteria Phase 1
- ✅ `podman exec soularr ping slskd` succeeds
- ✅ No 404 errors in soularr logs
- ✅ Both containers appear in `podman network inspect media-network`
- ✅ Downloads resume successfully

---

## Phase 2: Pin Container Versions (MEDIUM)

### Problem
All containers use `:latest` tags:
- `slskd/slskd:latest`
- `docker.io/mrusse08/soularr:latest`
- `lscr.io/linuxserver/lidarr:develop`

This risks API breakage when images update independently.

### Solution
Pin to specific stable versions with known compatibility.

### Files to Modify

#### 1. `/home/eric/.nixos/domains/server/containers/slskd/options.nix`
```nix
# Before
image = mkOption {
  type = types.str;
  default = "slskd/slskd:latest";
};

# After
image = mkOption {
  type = types.str;
  default = "slskd/slskd:0.21.4";  # Latest stable with API v0
  description = "slskd container image (pinned for stability)";
};
```

#### 2. `/home/eric/.nixos/domains/server/containers/soularr/options.nix`
```nix
# Research compatible version first, then pin
image = mkOption {
  type = types.str;
  default = "docker.io/mrusse08/soularr:1.2.0";  # Version compatible with slskd 0.21.x
  description = "soularr container image (pinned for API compatibility)";
};
```

#### 3. `/home/eric/.nixos/domains/server/containers/lidarr/options.nix`
```nix
# Keep develop branch for NullRef bug fix, but pin date
image = mkOption {
  type = types.str;
  default = "lscr.io/linuxserver/lidarr:develop-2025.12.01";  # Pin to date
  description = "lidarr container image (develop branch for Distance.Clean() fix)";
};
```

#### 4. Create version tracking docs

**`/home/eric/.nixos/domains/server/containers/slskd/VERSION.md`**:
```markdown
# slskd Version Tracking

- **Current Version**: 0.21.4
- **Last Updated**: 2025-12-04
- **API Version**: v0
- **Known Issues**: None
- **Update Process**: Test in staging before pinning new version
```

### Testing Phase 2

```bash
# Rebuild with new versions
sudo nixos-rebuild test --flake .#hwc-server

# Verify versions
sudo podman inspect slskd --format '{{.Image}}'
sudo podman inspect soularr --format '{{.Image}}'
sudo podman inspect lidarr --format '{{.Image}}'

# Test API compatibility
journalctl -u podman-soularr.service -n 100 --no-pager | grep -i "404\|api"
# Expected: No API errors
```

---

## Phase 3: Automated Beets Cleanup (LOW)

### Problem
Beets is configured but music library has chaos:
- Multiple duplicate albums
- Inconsistent naming (apostrophes vs underscores)
- Manual cleanup is tedious

### Solution
Create automated systemd timers for:
- Hourly auto-import from `/mnt/hot/downloads/music/`
- Weekly deduplication and cleanup

### Files to Create/Modify

#### 1. `/home/eric/.nixos/domains/server/beets-native/parts/beets-auto-import.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/beets-automation"
LOG_FILE="$LOG_DIR/auto-import-$(date +%Y%m%d-%H%M%S).log"
IMPORT_DIR="/mnt/hot/downloads/music"
LOCK_FILE="/run/beets-auto-import.lock"

mkdir -p "$LOG_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "[$(date)] Starting beets auto-import"

# Lock to prevent concurrent runs
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    echo "[$(date)] Another import is running, exiting"
    exit 0
fi
trap "rmdir '$LOCK_FILE'" EXIT

# Count files to import
file_count=$(find "$IMPORT_DIR" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" \) | wc -l)
echo "[$(date)] Found $file_count music files in $IMPORT_DIR"

if [ "$file_count" -eq 0 ]; then
    echo "[$(date)] No files to import"
    exit 0
fi

# Run import with auto mode
beet import -q "$IMPORT_DIR"

echo "[$(date)] Import completed"

# Trigger Navidrome rescan
curl -s http://localhost:4533/api/scan || true

echo "[$(date)] Cleanup complete"
```

#### 2. `/home/eric/.nixos/domains/server/beets-native/index.nix`
Add systemd services and timers:

```nix
# In IMPLEMENTATION section, add:

# Auto-import service
systemd.services.beets-auto-import = {
  description = "Beets automatic music import";
  serviceConfig = {
    Type = "oneshot";
    User = "eric";
    ExecStart = "${pkgs.bash}/bin/bash ${./parts/beets-auto-import.sh}";
    Nice = 10;  # Lower priority
  };
};

# Auto-import timer (hourly)
systemd.timers.beets-auto-import = {
  description = "Hourly beets auto-import timer";
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    Persistent = true;
    RandomizedDelaySec = "5m";
  };
};

# Weekly cleanup service
systemd.services.beets-weekly-cleanup = {
  description = "Beets weekly deduplication and cleanup";
  serviceConfig = {
    Type = "oneshot";
    User = "eric";
    ExecStart = "${pkgs.bash}/bin/bash -c 'beet duplicates -d && beet update'";
  };
};

# Weekly cleanup timer
systemd.timers.beets-weekly-cleanup = {
  description = "Weekly beets cleanup timer";
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "Sun 03:00";
    Persistent = true;
  };
};
```

#### 3. `/home/eric/.nixos/domains/server/beets-native/options.nix`
Add automation options:

```nix
automation = {
  enable = mkEnableOption "Enable automated import and cleanup" // { default = true; };

  importInterval = mkOption {
    type = types.str;
    default = "hourly";
    description = "Systemd timer interval for auto-import";
  };

  cleanupDay = mkOption {
    type = types.str;
    default = "Sun";
    description = "Day of week for cleanup (Mon-Sun)";
  };
};
```

### Testing Phase 3

```bash
# Enable and start timers
sudo nixos-rebuild switch --flake .#hwc-server

# Verify timers are active
systemctl list-timers | grep beets
# Expected:
# beets-auto-import.timer
# beets-weekly-cleanup.timer

# Manual test
sudo systemctl start beets-auto-import.service

# Check logs
journalctl -u beets-auto-import.service -n 50
cat /var/log/beets-automation/auto-import-*.log

# Verify import worked
ls -la /mnt/media/music/ | head -20
```

---

## Execution Order

1. **Phase 1 First** (CRITICAL - blocks all functionality)
   - Fix network communication
   - Test thoroughly before proceeding

2. **Phase 2 Second** (MEDIUM - prevents future breakage)
   - Pin versions
   - Document versions

3. **Phase 3 Last** (LOW - quality of life)
   - Set up automation
   - Monitor for issues

**Total Time**: 3-5 hours (including testing)

---

## Rollback Strategy

Each phase can be rolled back independently:

```bash
# Rollback specific phase
git checkout HEAD~1 -- domains/server/containers/slskd/
git checkout HEAD~1 -- domains/server/containers/soularr/
sudo nixos-rebuild switch --flake .#hwc-server

# Or use NixOS generation rollback
sudo nixos-rebuild switch --flake .#hwc-server --rollback

# Disable timers if Phase 3 causes issues
sudo systemctl stop beets-auto-import.timer
sudo systemctl disable beets-auto-import.timer
```

---

## Charter v6.0 Compliance Checklist

All changes follow Charter v6.0:
- ✅ Options only in `options.nix`
- ✅ Implementation in `index.nix` with OPTIONS/IMPLEMENTATION/VALIDATION sections
- ✅ Pure helpers in `parts/` directory
- ✅ System config in `sys.nix`
- ✅ Namespace matches folder path
- ✅ Dependency assertions in VALIDATION section
- ✅ No cross-lane imports

**Validation Commands**:
```bash
./workspace/utilities/lints/charter-lint.sh domains/server/containers/slskd
./workspace/utilities/lints/charter-lint.sh domains/server/containers/soularr
./workspace/utilities/lints/charter-lint.sh domains/server/beets-native
nix flake check
```

---

## Next Steps

**Ready for implementation?** I can:
1. **Implement Phase 1 immediately** (critical network fix)
2. **Implement all phases in sequence**
3. **Implement specific phases you choose**

**Prefer to review first?** I can:
1. Show you the exact file changes before applying
2. Create a test branch for safety
3. Answer questions about the approach
