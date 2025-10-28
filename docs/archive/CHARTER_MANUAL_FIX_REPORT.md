# HWC Charter Manual Fix Report
**Generated**: 2025-09-28
**Total Errors**: 53
**Priority**: High (blocking 100% charter compliance)

## 📊 Executive Summary

All remaining charter violations fall into **3 clear categories** with well-defined fix patterns:

1. **Lane Purity Violations** (3 errors) - System code in Home domain
2. **Anti-Patterns** (40 errors) - Options defined outside options.nix
3. **Namespace Misalignments** (7 errors) - Directory structure mismatch
4. **Remaining Issues** (3 errors) - Template files with option examples

## 🎯 Category 1: Lane Purity Violations (3 errors)

**Priority**: CRITICAL - Architectural violations
**Fix Effort**: Medium (requires moving code)

### Issues:
1. **`domains/home/apps/hyprland/parts/session.nix:17`**
   - **Problem**: `pkgs.writeScriptBin` in Home Manager domain
   - **Fix**: Move script creation to `domains/home/apps/hyprland/sys.nix`

2. **`domains/home/theme/index.nix:49`** (Comment references)
   - **Problem**: Comments mention `systemd.services` and `environment.systemPackages`
   - **Fix**: Update comments to clarify Home Manager boundaries

### Fix Pattern:
```nix
# BEFORE (in home domain):
hyprlandStartupScript = pkgs.writeScriptBin "name" ''content'';

# AFTER (move to sys.nix):
# domains/home/apps/hyprland/sys.nix
environment.systemPackages = [ hyprlandStartupScript ];
```

## 🎯 Category 2: Anti-Patterns - Options Outside options.nix (40 errors)

**Priority**: HIGH - Core architectural pattern
**Fix Effort**: High (requires systematic refactoring)

### Pattern Analysis:
All 40 files have embedded `options.hwc.*` definitions that should be extracted to dedicated `options.nix` files.

### High-Impact Files (most commonly used):
1. **System Packages** (3 files):
   - `domains/system/packages/server.nix`
   - `domains/system/packages/base.nix`
   - `domains/system/packages/security.nix`

2. **Security Domain** (4 files):
   - `domains/security/materials.nix`
   - `domains/security/hardening.nix`
   - `domains/security/secrets.nix`
   - `domains/security/emergency-access.nix`

3. **Infrastructure** (3 files):
   - `domains/infrastructure/hardware/gpu.nix`
   - `domains/infrastructure/hardware/storage.nix`
   - `domains/infrastructure/hardware/peripherals.nix`

### Fix Pattern:
```nix
# BEFORE (single file with options + implementation):
# domains/example/feature.nix
{ lib, ... }: {
  options.hwc.example.feature = { enable = lib.mkEnableOption "..."; };
  config = lib.mkIf config.hwc.example.feature.enable { /* impl */ };
}

# AFTER (split into two files):
# domains/example/feature/options.nix
{ lib, ... }: {
  options.hwc.example.feature = { enable = lib.mkEnableOption "..."; };
}

# domains/example/feature/index.nix
{ lib, config, ... }: {
  imports = [ ./options.nix ];
  config = lib.mkIf config.hwc.example.feature.enable { /* impl */ };
}
```

### Complete File List:
**Server Domain** (8 files):
- `domains/server/business/business-api.nix`
- `domains/server/backup/user-backup.nix`
- `domains/server/ai/ollama/ollama.nix`
- `domains/server/ai/ollama/ollama-old.nix`
- `domains/server/ai/ai-bible/ai-bible.nix`
- `domains/server/jellyfin.nix`
- `domains/server/arr-stack.nix`
- `domains/server/monitoring/prometheus.nix`
- `domains/server/monitoring/grafana.nix`

**Server Networking** (5 files):
- `domains/server/networking/vpn.nix`
- `domains/server/networking/ntfy.nix`
- `domains/server/networking/transcript-api.nix`
- `domains/server/networking/databases.nix`
- `domains/server/networking/networking.nix`

**System Domain** (11 files):
- `domains/system/packages/server.nix`
- `domains/system/packages/base.nix`
- `domains/system/packages/security.nix`
- `domains/system/core/paths.nix`
- `domains/system/core/thermal.nix`
- `domains/system/core/polkit.nix`
- `domains/system/core/networking.nix`
- `domains/system/services/behavior.nix`
- `domains/system/services/samba.nix`
- `domains/system/services/session.nix`
- `domains/system/services/networking.nix`

**Infrastructure** (3 files):
- `domains/infrastructure/hardware/gpu.nix`
- `domains/infrastructure/hardware/peripherals.nix`
- `domains/infrastructure/hardware/storage.nix`

**Security** (4 files):
- `domains/security/materials.nix`
- `domains/security/emergency-access.nix`
- `domains/security/secrets.nix`
- `domains/security/hardening.nix`

**Home Environment** (2 files):
- `domains/home/environment/productivity.nix`
- `domains/home/environment/development.nix`

**Template/Helpers** (2 files):
- `scripts/templates/options-template.nix` (template file - can ignore)
- `scripts/helpers.nix`

## 🎯 Category 3: Namespace Misalignments (7 errors)

**Priority**: MEDIUM - Structural alignment
**Fix Effort**: Medium (rename options or move files)

### Issues & Solutions:

1. **`domains/server/backup/user-backup.nix`**
   - **Expected**: `options.hwc.server.backup.userBackup.*`
   - **Found**: `options.hwc.services.backup.user.*`
   - **Fix**: Rename namespace to match directory structure

2. **`domains/server/ai/ollama/ollama-old.nix`**
   - **Expected**: `options.hwc.server.ai.ollama.ollamaOld.*`
   - **Found**: `options.hwc.services.ollama.*`
   - **Fix**: Update namespace or move to services domain

3. **`domains/system/packages/server.nix`**
   - **Expected**: `options.hwc.system.packages.server.*`
   - **Found**: `options.hwc.system.serverPackages.*`
   - **Fix**: Rename to `options.hwc.system.packages.server.*`

4. **`domains/system/packages/base.nix`**
   - **Expected**: `options.hwc.system.packages.base.*`
   - **Found**: `options.hwc.system.basePackages.*`
   - **Fix**: Rename to `options.hwc.system.packages.base.*`

5. **`domains/system/packages/security.nix`**
   - **Expected**: `options.hwc.system.packages.security.*`
   - **Found**: `options.hwc.system.backupPackages.*`
   - **Fix**: Rename to `options.hwc.system.packages.security.*`

6. **`domains/system/core/filesystem/options.nix`**
   - **Expected**: `options.hwc.system.core.filesystem.*`
   - **Found**: `options.hwc.filesystem.*`
   - **Fix**: Rename to match directory structure

## 📋 Implementation Priorities

### Phase 1: Quick Wins (3 errors)
**Target**: Lane purity violations
**Effort**: 1-2 hours
**Impact**: Removes architectural violations

### Phase 2: High-Impact Anti-Patterns (10 files)
**Target**: Most commonly used system files
**Effort**: 4-6 hours
**Impact**: Major charter compliance improvement

**Recommended order**:
1. System packages (3 files)
2. Security domain (4 files)
3. Infrastructure hardware (3 files)

### Phase 3: Namespace Alignment (7 files)
**Target**: Directory/namespace mismatches
**Effort**: 2-3 hours
**Impact**: Structural consistency

### Phase 4: Remaining Anti-Patterns (30 files)
**Target**: All remaining option extractions
**Effort**: 8-12 hours
**Impact**: 100% charter compliance

## 🔧 Automation Opportunities

**Cannot be automated** (requires human judgment):
- Lane purity fixes (system vs home logic)
- Namespace design decisions
- Breaking changes coordination

**Could be semi-automated** (with careful review):
- Option extraction pattern
- File structure creation
- Import statement updates

## 🎯 Success Metrics

**100% Charter Compliance** achieved when:
- ✅ Module anatomy: 0 errors (COMPLETE)
- ⚠️ Lane purity: 0 errors (3 remaining)
- ⚠️ Anti-patterns: 0 errors (40 remaining)
- ⚠️ Namespace alignment: 0 errors (7 remaining)

**Estimated Total Effort**: 15-20 hours for complete compliance
**Recommended Approach**: Incremental phases with testing between each phase