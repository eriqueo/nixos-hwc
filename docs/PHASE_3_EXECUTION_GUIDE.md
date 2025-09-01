# Phase 3: Interface Refinement & Finalization - Execution Guide

**CRITICAL**: Do not proceed unless Phase 2 is complete with ALL services in separate files and ZERO Charter v4 violations.

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

```bash
find modules/services/ -name "*.nix" -exec wc -l {} + | sort -nr | head -5
```
**REQUIRED RESULT**: No service files >150 lines (except legitimate single-service complexity)

If any check fails, STOP and complete Phase 2 first.

## Phase 3 Overview

**GOAL**: Solidify interfaces between modules by implementing the `hwc.*` toggle system and removing any remaining cross-domain impurities.

**SUCCESS CRITERIA**:
- All services controlled by Charter-compliant toggles
- Clean separation between profiles (orchestration) and modules (implementation)
- Zero Charter v4 violations maintained
- System fully functional with toggle-based control

## Step 3.1: Implement hwc.* Toggle System

**CRITICAL**: Work on ONE module at a time. Never modify multiple modules simultaneously.

### 3.1.1: Select Target Module

**MANDATORY CRITERIA**:
- Choose simplest module first (fewest dependencies)
- Module must be in its own file from Phase 2
- Module must not already have proper hwc.* toggles

**VERIFICATION**: Check current structure:
```bash
rg "options\.hwc\." modules/services/media/jellyfin.nix
```

If no hwc options exist, this module needs conversion.

### 3.1.2: Convert Module to hwc.* Toggle Pattern

**MANDATORY TEMPLATE**:

1. **Verify module structure** matches Charter v4:
```nix
# Current module should look like:
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.jellyfin;  # MUST use hwc.services.*
  paths = config.hwc.paths;
in {
  options.hwc.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";
    # ... other options
  };
  
  config = lib.mkIf cfg.enable {
    # ... implementation
  };
}
```

2. **If module lacks hwc.* structure**, convert using this EXACT pattern:

**BEFORE (incorrect)**:
```nix
options.services.jellyfin = {
  enable = lib.mkEnableOption "...";
};
config = lib.mkIf config.services.jellyfin.enable {
```

**AFTER (correct)**:
```nix
options.hwc.services.jellyfin = {
  enable = lib.mkEnableOption "Jellyfin media server";
};
config = lib.mkIf config.hwc.services.jellyfin.enable {
```

### 3.1.3: Validate Toggle Interface

**MANDATORY CHECKS**:

1. **Option naming follows Charter v4 taxonomy**:
   - Services: `hwc.services.*`
   - Infrastructure: `hwc.infrastructure.*` 
   - Home/User: `hwc.home.*`
   - System: `hwc.system.*`

2. **Implementation wrapped in mkIf**:
```bash
rg "config = lib\.mkIf" modules/services/media/jellyfin.nix
```
**REQUIRED**: Must exist

3. **No unconditional configuration**:
```bash
rg "virtualisation\.oci-containers" modules/services/media/jellyfin.nix
```
**REQUIRED**: All container configs must be inside mkIf blocks

### 3.1.4: Update Profile to Use Toggle

**MANDATORY STEPS**:

1. **Identify controlling profile** (usually media-server.nix for media services)

2. **Add toggle activation**:
```nix
# In profiles/media-server.nix or profiles/workstation.nix
hwc.services.jellyfin.enable = true;
```

3. **Remove any old-style service enablement**:
```bash
# Search for and remove patterns like:
rg "services\.jellyfin" profiles/
```

### 3.1.5: Test Toggle Functionality

**MANDATORY VERIFICATION**:

1. **Test enabled state**:
```bash
nixos-rebuild test --flake .#hwc-laptop
# Service should be running
sudo systemctl status podman-jellyfin.service
```

2. **Test disabled state**:
```nix
# Temporarily set in profile:
hwc.services.jellyfin.enable = false;
```
```bash
nixos-rebuild test --flake .#hwc-laptop
# Service should NOT exist
sudo systemctl status podman-jellyfin.service  # Should show "not found"
```

3. **Restore enabled state**:
```nix
hwc.services.jellyfin.enable = true;
```
```bash
nixos-rebuild test --flake .#hwc-laptop
```

**CRITICAL**: If any test fails, revert changes and debug before proceeding.

### 3.1.6: Validate Charter Compliance

**MANDATORY**:
```bash
./scripts/validate-charter-v4.sh
```
**REQUIRED RESULT**: No new violations

## Step 3.2: Systematic Toggle Rollout

**MANDATORY SEQUENCE**: Apply Step 3.1 to every service module created in Phase 2.

### 3.2.1: Create Module Priority List

**MANDATORY ORDER**:

1. **List all service modules**:
```bash
find modules/services/ -name "*.nix" | sort
```

2. **Process in dependency order** (services with fewest dependencies first):
   - Basic services (no external dependencies)
   - Networking services 
   - Database services
   - Application services
   - Complex orchestrated services

### 3.2.2: Batch Processing Rules

**MANDATORY CONSTRAINTS**:

- **Never modify more than 3 modules** between tests
- **Always test build** after every 3 modules maximum
- **Immediately fix violations** before continuing

**VERIFICATION AFTER EACH BATCH**:
```bash
nixos-rebuild test --flake .#hwc-laptop
./scripts/validate-charter-v4.sh
```

### 3.2.3: Infrastructure Module Toggles

**MANDATORY**: Apply same toggle pattern to infrastructure modules:

**EXAMPLES**:
- `hwc.infrastructure.printing.enable = true;`
- `hwc.infrastructure.virtualization.enable = true;`
- `hwc.infrastructure.waybarGpuTools.enable = true;`

**VERIFICATION**: All infrastructure services controlled by toggles:
```bash
rg "hwc\.infrastructure\." profiles/ | wc -l
```

## Step 3.3: Final System-Wide Validation

**MANDATORY COMPREHENSIVE TESTING**:

### 3.3.1: Toggle Matrix Testing

**FOR EACH major service category, test these states**:

1. **All services disabled**:
```nix
# In relevant profile
hwc.services = {
  # Comment out or set all to false
  # jellyfin.enable = false;
  # radarr.enable = false;
  # sonarr.enable = false;
};
```

2. **Individual service enablement**:
```bash
# Test each service can be enabled independently
nixos-rebuild test --flake .#hwc-laptop
```

3. **All services enabled** (final state):
```bash
nixos-rebuild test --flake .#hwc-laptop
```

### 3.3.2: Profile Validation

**MANDATORY CHECKS**:

1. **Profiles contain only orchestration**:
```bash
# Profiles should only have imports and hwc.* toggles
rg "systemd\.|virtualisation\.|services\.[^h]" profiles/
```
**REQUIRED RESULT**: No matches (or only hwc.services.*)

2. **No hardcoded implementation in profiles**:
```bash
rg "writeScriptBin|writeShellScript|mkIf.*enable" profiles/
```
**REQUIRED RESULT**: No matches

### 3.3.3: Cross-Domain Dependency Validation

**MANDATORY**: Verify dependency direction compliance:

1. **Check imports follow dependency direction**:
```bash
rg "modules/infrastructure" modules/home/ | grep -v "^#"
```
**REQUIRED RESULT**: No matches (home should not import infrastructure)

2. **Check no reverse dependencies**:
```bash
rg "hwc\.home\." modules/infrastructure/ | grep -v "^#"
```
**REQUIRED RESULT**: No matches (infrastructure should not depend on home)

### 3.3.4: Machine Configuration Cleanup

**MANDATORY**: Ensure machine configs contain only facts and toggles:

1. **Review machine configs**:
```bash
find machines/ -name "config.nix" -exec head -50 {} \;
```

2. **Verify machine configs contain ONLY**:
   - Hardware facts (`hwc.gpu.type = "nvidia";`)
   - Storage paths (`hwc.paths.hot = "/path";`)
   - Service toggles (`hwc.services.ollama.enable = true;`)
   - Profile imports

3. **Remove any implementation details** from machine configs

## Step 3.4: Performance and Resource Optimization

**MANDATORY VERIFICATION**:

### 3.4.1: Build Performance Test

**MEASURE baseline**:
```bash
time nixos-rebuild test --flake .#hwc-laptop
```

**RECORD RESULTS**: Document build time for comparison

### 3.4.2: Module Dependency Analysis

**GENERATE DEPENDENCY MAP**:
```bash
rg "config\.hwc\." modules/ -A 1 -B 1 > docs/DEPENDENCY_ANALYSIS.txt
```

**REVIEW FOR**:
- Circular dependencies (forbidden)
- Overly complex dependency chains
- Missing dependency declarations in headers

## Phase 3 Completion Criteria

**ALL of the following MUST be true**:

1. **Toggle Control**: Every service controlled by `hwc.*` toggles
2. **Build Success**: `nixos-rebuild test --flake .#hwc-laptop` succeeds
3. **Charter Compliance**: `./scripts/validate-charter-v4.sh` shows zero violations
4. **Profile Purity**: Profiles contain only imports and toggles
5. **Machine Purity**: Machine configs contain only facts and toggles
6. **Dependency Direction**: All dependencies flow correctly (profiles → modules)
7. **Service Isolation**: Each service can be independently enabled/disabled
8. **Functionality**: All services work correctly when enabled

## Failure Recovery

**If any criterion fails**:

1. **Identify specific failure**:
```bash
./scripts/validate-charter-v4.sh
nixos-rebuild test --flake .#hwc-laptop 2>&1 | tee build-error.log
```

2. **Isolate problem area**:
   - Single service issue: Fix that service
   - Profile issue: Review profile purity
   - Dependency issue: Check module headers

3. **Systematic debugging**:
   - Disable all services
   - Enable one at a time to isolate issue
   - Fix root cause before re-enabling others

## Documentation Updates

**MANDATORY at completion**:

1. **Update MIGRATION_STATUS.md**:
   - Phase 3: 100% Complete
   - Document toggle structure
   - List any architectural decisions

2. **Create toggle reference**:
```bash
rg "options\.hwc\." modules/ -A 2 | grep "mkEnableOption\|mkOption" > docs/HWC_TOGGLE_REFERENCE.md
```

3. **Final validation documentation**:
```bash
./scripts/validate-charter-v4.sh > docs/PHASE_3_VALIDATION_RESULTS.txt
```

**Phase 3 is complete when the system is fully toggle-controlled and Charter v4 compliant.**