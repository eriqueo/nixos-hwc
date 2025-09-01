# Phase 2: Deconstruction & Relocation - Execution Guide

**CRITICAL**: Do not proceed unless Phase 1 is complete with ZERO Charter v4 violations.

## Prerequisites Verification

**MANDATORY**: Before starting, run these commands and verify results:

```bash
./scripts/validate-charter-v4.sh
```
**REQUIRED RESULT**: "✅ No violations found"

```bash
nixos-rebuild test --flake .#hwc-laptop
```
**REQUIRED RESULT**: Build succeeds without errors

If either check fails, STOP and complete Phase 1 first.

## Phase 2 Overview

**GOAL**: Break down large, monolithic `.nix` files into smaller, domain-pure components according to Charter v4.

**SUCCESS CRITERIA**: 
- All services moved to individual files in appropriate domain directories
- System builds successfully after each step
- Zero new Charter v4 violations introduced

## Step 2.1: Identify Target Files for Deconstruction

**MANDATORY ACTIONS**:

1. **Run file size analysis**:
```bash
find modules/ -name "*.nix" -exec wc -l {} + | sort -nr | head -10
```

2. **Identify monolithic files** (files >150 lines containing multiple distinct services):
   - Look for files with multiple `virtualisation.oci-containers.containers.*` definitions
   - Look for files with multiple `systemd.services.*` definitions  
   - Look for files with multiple unrelated service configurations

3. **Create target list** by examining these patterns:
```bash
rg "virtualisation\.oci-containers\.containers\." modules/ -l | xargs -I {} sh -c 'echo "=== {} ==="; rg "virtualisation\.oci-containers\.containers\." {} | wc -l'
```

**EXPECTED TARGETS**: Files like `modules/services/media/arr-stack.nix` or similar that configure multiple services.

## Step 2.2: Service Extraction Protocol

**CRITICAL**: Follow this exact sequence for EACH service extraction:

### 2.2.1: Select Single Service

**MANDATORY**: Choose ONE service from the target file. Start with the simplest/smallest service first.

**EXAMPLE**: If `arr-stack.nix` contains Radarr, Sonarr, and Lidarr, start with Radarr.

### 2.2.2: Create New Service Module

**MANDATORY FILE STRUCTURE**:

1. **Create directory** (if needed):
```bash
mkdir -p modules/services/media/
```

2. **Create service file** using this EXACT template:
```bash
touch modules/services/media/radarr.nix
```

3. **Use Charter v4 template** - copy this EXACTLY:
```nix
# nixos-hwc/modules/services/media/radarr.nix
#
# RADARR - Movie collection management service
# Automated movie downloading and library management via OCI container
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.infrastructure.* (networking, storage)
#
# USED BY (Downstream):
#   - profiles/media-server.nix (enables via hwc.services.radarr.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/media-server.nix: ../modules/services/media/radarr.nix
#
# USAGE:
#   hwc.services.radarr.enable = true;
#   hwc.services.radarr.port = 7878;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.radarr;
  paths = config.hwc.paths;
in {

  #============================================================================
  # OPTIONS - Service Configuration Interface
  #============================================================================

  options.hwc.services.radarr = {
    enable = lib.mkEnableOption "Radarr movie collection management";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7878;
      description = "Port for Radarr web interface";
    };

    # Add other options as needed from original configuration
  };

  #============================================================================
  # IMPLEMENTATION - Service Definition
  #============================================================================

  config = lib.mkIf cfg.enable {

    # Copy ONLY the Radarr-related configuration from the original file
    # Include container definition, networking, storage mounts, etc.
    
  };
}
```

### 2.2.3: Extract Service Configuration

**MANDATORY PROCESS**:

1. **Copy (don't move)** the service configuration from original file to new file
2. **Replace hardcoded values** with options where appropriate
3. **Verify all paths use `config.hwc.paths.*`**
4. **Ensure container networking follows Charter v4 patterns**

**FORBIDDEN**: 
- Do NOT delete from original file yet
- Do NOT modify original file
- Do NOT combine multiple services in one new file

### 2.2.4: Import New Module

**MANDATORY STEPS**:

1. **Add import** to appropriate profile:
```nix
# In profiles/media-server.nix (or relevant profile)
imports = [
  # ... existing imports ...
  ../modules/services/media/radarr.nix
];
```

2. **Enable service**:
```nix
# In profiles/media-server.nix
hwc.services.radarr.enable = true;
# Copy any other service-specific settings from machines/*/config.nix
```

### 2.2.5: Test Build

**MANDATORY VERIFICATION**:

```bash
nixos-rebuild test --flake .#hwc-laptop
```

**REQUIRED RESULT**: Build succeeds. If it fails:
1. Revert all changes: `git checkout HEAD -- .`
2. Identify the issue
3. Fix and repeat step 2.2

### 2.2.6: Test Service Functionality

**MANDATORY CHECKS**:

1. **Verify container starts**: 
```bash
sudo systemctl status podman-radarr.service
```

2. **Verify port accessibility**:
```bash
curl -f http://localhost:7878 || echo "Service not responding"
```

3. **Verify data persistence** (check that config/data directories exist and are writable)

### 2.2.7: Clean Up Original File

**ONLY after successful testing**:

1. **Comment out** the original Radarr configuration in the source file
2. **Add reference comment**:
```nix
# Radarr moved to modules/services/media/radarr.nix
# hwc.services.radarr.enable = true; # Enable in profiles/
```

3. **Test build again**:
```bash
nixos-rebuild test --flake .#hwc-laptop
```

4. **Delete commented code** only after successful test

### 2.2.8: Validate Charter Compliance

**MANDATORY**:
```bash
./scripts/validate-charter-v4.sh
```

**REQUIRED RESULT**: No new violations. If violations appear, fix immediately.

## Step 2.3: Repeat for All Services

**MANDATORY SEQUENCE**:

1. **Complete steps 2.2.1-2.2.8 for EACH service**
2. **Only work on ONE service at a time**
3. **Do not start next service until current one is fully complete and tested**

**TARGET COMPLETION**: All services in separate files under appropriate domain directories:
- `modules/services/media/radarr.nix`
- `modules/services/media/sonarr.nix`
- `modules/services/media/lidarr.nix`
- `modules/services/media/prowlarr.nix`
- `modules/services/media/qbittorrent.nix`
- etc.

## Step 2.4: Relocate Waybar Hardware Scripts

**MANDATORY**: Move any remaining hardware-related logic out of `modules/home/waybar/`

### 2.4.1: Identify Hardware Scripts

**SEARCH PATTERNS**:
```bash
rg "writeScriptBin|writeShellScript" modules/home/waybar/ -A 5 -B 2
```

### 2.4.2: Extract Hardware Tools

**FOR EACH hardware script found**:

1. **Create infrastructure module**:
```bash
# Example for GPU tools
touch modules/infrastructure/waybar-gpu-tools.nix
```

2. **Use Charter v4 template** with hardware domain classification

3. **Move `writeScriptBin` logic** to infrastructure module

4. **Expose via `environment.systemPackages`**

5. **Update Waybar config** to call binary by name:
```nix
# In waybar tool config
exec = "waybar-gpu-status";  # Not a script path
```

### 2.4.3: Test Hardware Integration

**MANDATORY VERIFICATION**:

1. **Build test**: `nixos-rebuild test --flake .#hwc-laptop`
2. **Physical test**: Click waybar button, verify functionality
3. **Script availability**: `which waybar-gpu-status`

## Phase 2 Completion Criteria

**ALL of the following MUST be true**:

1. **Zero monolithic files**: No service files >150 lines with multiple distinct services
2. **Build success**: `nixos-rebuild test --flake .#hwc-laptop` succeeds
3. **Service functionality**: All services start and respond correctly
4. **Charter compliance**: `./scripts/validate-charter-v4.sh` shows zero violations
5. **Domain purity**: All waybar hardware scripts in infrastructure layer
6. **Profile simplicity**: Profiles only contain imports and toggles

## Failure Recovery

**If any step fails**:

1. **Immediate rollback**: `git checkout HEAD -- .`
2. **Re-run prerequisites verification**
3. **Identify root cause before proceeding**
4. **Do not attempt shortcuts or parallel work**

## Documentation Updates

**MANDATORY at completion**:

1. **Update MIGRATION_STATUS.md**:
   - Phase 2: 100% Complete
   - List all new service files created
   - Document any architectural decisions

2. **Run validation and document results**:
```bash
./scripts/validate-charter-v4.sh > docs/PHASE_2_VALIDATION_RESULTS.txt
```

**Phase 2 is complete when this document can be marked as successfully executed with zero deviations.**