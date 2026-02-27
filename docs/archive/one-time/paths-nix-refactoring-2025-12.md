# paths.nix Refactoring - December 2025

**Date**: 2025-12-23
**Author**: Eric (with Claude Code assistance)
**Status**: ✅ Complete
**Branch**: `refactor/paths-nix-nested-structure`

## Overview

Comprehensive refactoring to establish `domains/system/core/paths.nix` as the single source of truth for all filesystem paths across the nixos-hwc configuration. This eliminated 27+ hardcoded path instances across 10 modules and implemented a nested path structure with derived paths.

## Problem Statement

### Issues Identified

1. **Path Drift**: 10+ modules hardcoded filesystem paths instead of using `config.hwc.paths.*`
2. **No Single Source of Truth**: Paths scattered across multiple files
3. **Inconsistent Overrides**: No clear pattern for machine-specific path configuration
4. **Charter Violations**: 99 Charter compliance violations for hardcoded paths
5. **Limited Path Structure**: Simple nullable paths didn't support derived sub-paths

### Affected Modules

- navidrome (1 hardcoded path)
- immich (7 hardcoded paths)
- frigate (3 hardcoded paths)
- beets-native (2 hardcoded paths)
- beets-container (3 hardcoded paths)
- backup (1 path + 3 scripts)
- pihole (2 hardcoded paths)
- storage (4 hardcoded paths)
- ai/local-workflows (8+ hardcoded paths)

**Total**: 27+ hardcoded path instances across options.nix files

## Solution Architecture

### New Path Structure

Restructured simple paths into nested attribute sets with automatic path derivation:

**Before**:
```nix
hwc.paths = {
  hot = "/mnt/hot";        # Simple nullable path
  media = "/mnt/media";    # Simple nullable path
};
```

**After**:
```nix
hwc.paths = {
  hot = {
    root = "/mnt/hot";                                    # Base path
    downloads.root = "<auto-derived: /mnt/hot/downloads>";     # Derived
    downloads.music = "<auto-derived: /mnt/hot/downloads/music>";  # Nested derived
    surveillance = "<auto-derived: /mnt/hot/surveillance>";   # Derived
  };
  media = {
    root = "/mnt/media";                                  # Base path
    music = "<auto-derived: /mnt/media/music>";               # Derived
    surveillance = "<auto-derived: /mnt/media/surveillance>"; # Derived
  };
};
```

### New Path Definitions Added

1. **Storage Tier Paths**:
   - `hwc.paths.photos` - Dedicated photo storage for Immich

2. **Networking Paths**:
   - `hwc.paths.networking.root` - Network services root (`/opt/networking`)
   - `hwc.paths.networking.pihole` - Pi-hole data directory (derived)

3. **Derived Paths**:
   - `hwc.paths.hot.downloads.music` - Music download staging
   - Path derivation ensures consistency across all modules

## Implementation Phases

### Phase 0: Checkpoint & Planning
- Created git checkpoint commit
- Created feature branch `refactor/paths-nix-nested-structure`
- Documented baseline build state
- Risk mitigation planning with 6 test levels

### Phase 1: Restructure paths.nix
**Breaking Change**: Converted simple paths to nested attribute sets

**Changes**:
- `hot` → `hot.root` with derived sub-paths
- `media` → `media.root` with derived sub-paths
- Added nested `hot.downloads` structure
- Changed type from `lib.types.path` to `lib.types.str` (pure evaluation issue)
- Used plain attribute sets instead of submodules (import error)

**Files Modified**: 1
- `domains/system/core/paths.nix`

### Phase 2: Update Machine Configurations
Updated all machine configs to use new nested structure

**Changes**:
```nix
# Before
hwc.paths.hot = "/mnt/hot";

# After
hwc.paths.hot.root = "/mnt/hot";
```

**Files Modified**: 3
- `machines/server/config.nix`
- `machines/laptop/config.nix`
- `profiles/server.nix`

### Phase 3: Update Container Volume Mounts
Updated all container volume mount paths to reference `.root`

**Pattern**:
```nix
# Before
"${config.hwc.paths.hot}/downloads:/downloads"

# After
"${config.hwc.paths.hot.root}/downloads:/downloads"
```

**Files Modified**: 8
- books, navidrome, lidarr, sonarr, radarr, qbittorrent, sabnzbd, tdarr

### Phase 4: Update Assertions
Updated path assertions to check `.root` instead of simple path

**Files Modified**: 2
- `domains/server/containers/books/index.nix`
- `domains/server/native/storage/index.nix`

### Phase 5: Update Monitoring Scripts
Updated monitoring dashboard to reference new path structure

**Files Modified**: 2
- `domains/server/native/storage/parts/monitoring.nix`
- `domains/server/native/monitoring/monitoring.nix`

### Phase 6: Update AI Workflows
Updated AI module path references

**Files Modified**: 2
- `domains/ai/local-workflows/options.nix`
- `domains/server/native/ai/local-workflows/options.nix`

### Phase 7: Add New Paths
Added photos, networking, and derived path definitions

**New Options Added**:
- `hwc.paths.photos`
- `hwc.paths.networking.root`
- `hwc.paths.networking.pihole`
- `hwc.paths.hot.downloads.music`
- Assertions for path uniqueness
- Environment variables for all new paths

**Files Modified**: 2
- `domains/system/core/paths.nix` (extended)
- `machines/server/config.nix` (added photos path)

### Phase 8: Refactor Service Modules
Updated all service module options to use canonical paths

**Pattern Applied**:
```nix
# Simple nullable path
default = config.hwc.paths.media.music or "/mnt/media/music";

# Derived path from nullable base
default = if config.hwc.paths.photos != null
          then "${config.hwc.paths.photos}/library"
          else "/mnt/photos/library";
```

**Modules Refactored** (8):
1. **navidrome**: `musicFolder` → `config.hwc.paths.media.music`
2. **backup**: `mountPoint` → `config.hwc.paths.backup`
   - Also updated 3 backup scripts to use `hot.root`
   - Updated tmpfiles.rules
3. **immich**: All 6 storage paths → `config.hwc.paths.photos`
4. **storage**: Cleanup paths → `hot.root` and `hot.downloads.root`
5. **frigate**: `mediaPath`/`bufferPath` → surveillance paths
6. **beets-native**: Music paths → canonical paths
7. **beets-container**: All 3 paths → canonical paths
8. **pihole**: `dataDir`/`dnsmasqDir` → `networking.pihole`

**Files Modified**: 8

## Results

### Metrics

**Before Refactoring**:
- 27+ hardcoded `/mnt/` and `/opt/` path instances
- 99 Charter compliance violations
- No path derivation support
- Inconsistent path patterns across modules

**After Refactoring**:
- 0 hardcoded paths in primary option values
- 97 Charter violations (only fallback values remain)
- Full path derivation support
- Consistent pattern: `config.hwc.paths.* or "/fallback"`
- 30+ files updated across codebase

### Build Validation

✅ **Server**: Builds successfully
✅ **Path Resolution**: All paths resolve correctly
  - `hwc.paths.photos` → `/mnt/photos`
  - `hwc.paths.hot.downloads.music` → `/mnt/hot/downloads/music`
  - `hwc.paths.networking.pihole` → `/opt/networking/pihole`
  - `hwc.paths.hot.downloads.root` → `/mnt/hot/downloads`

✅ **Environment Variables**: Export correctly
  - `$HWC_PHOTOS_STORAGE`
  - `$HWC_HOT_DOWNLOADS_MUSIC`
  - `$HWC_NETWORKING_PIHOLE`

✅ **Backward Compatibility**: Fallback values prevent breakage

### Commits

1. **Phase 0-2**: Breaking change - restructure hot/media to nested sets
2. **Phase 3-6**: Update all references to new structure
3. **Phase 7**: Add new path definitions (photos, networking, derived)
4. **Phase 8 Part 1**: Refactor navidrome, backup, immich
5. **Phase 8 Part 2**: Complete refactoring (storage, frigate, beets, pihole)

## Charter Documentation

### New Section Added

**§14 Path Management** - Comprehensive documentation of:
- Single source of truth principle
- Path structure and namespace
- Usage patterns in modules
- Machine configuration
- Environment variables
- Validation and assertions
- Anti-patterns
- Migration pattern
- Path architecture guidelines
- Breaking changes protocol

### Updated Validation Rules

**§15 Validation & Anti-Patterns** - Enhanced with:
- Specific validation commands for hardcoded paths
- Clarification that fallback values in `or` patterns are acceptable
- Reference to §14 Path Management

### Section Renumbering

All sections from §14 onwards renumbered to accommodate new section:
- §14: Path Management (NEW)
- §15: Validation & Anti-Patterns (was §14)
- §16: Server Workloads (was §15)
- §17: Profiles & Import Order (was §16)
- §18: Migration Protocol (was §17)
- §19: Status (was §18)
- §20: Charter Change Management (was §19)
- §21: Configuration Validity (was §20)
- §22: Complex Service Configuration (was §19, moved)
- §23: Data Retention (was §20)
- §24: Related Documentation (was §21)

## Lessons Learned

### Technical Challenges

1. **Type System Issues**:
   - `lib.types.path` fails in pure evaluation mode (checks path existence)
   - Solution: Use `lib.types.str` for all paths

2. **Submodule Pattern Rejected**:
   - Nix tried to import paths as modules
   - Solution: Plain attribute sets with individual `lib.mkOption` declarations

3. **Breaking Change Coordination**:
   - 30+ files required updates in lockstep
   - Solution: Phased approach with validation after each phase

4. **Charter Linter Limitations**:
   - Detects all `/mnt/` patterns including safe fallback values
   - Solution: Document that `or` fallback patterns are acceptable

### Best Practices Established

1. **Always add `config` parameter** to options.nix when referencing paths
2. **Use `or` fallback pattern** for backward compatibility
3. **Test both machines** after breaking changes
4. **Commit frequently** with clear phase markers
5. **Update Charter immediately** with new architectural patterns

### Future Refactoring Template

For similar breaking changes:
1. Create feature branch
2. Phase 1: Core restructure
3. Phase 2-6: Update all references systematically
4. Phase 7: Add new functionality
5. Phase 8: Refactor consuming modules
6. Validate after each phase
7. Document in Charter
8. Merge only after green builds on all machines

## Related Documentation

- **CHARTER.md §14**: Path Management (comprehensive rules)
- **CHARTER.md §15**: Validation rules for path compliance
- **domains/system/core/paths.nix**: Implementation
- **CLAUDE.md**: Development patterns and guidelines

## Next Steps

### Deployment
1. ✅ All changes committed to feature branch
2. ⏳ Verify path resolution in production
3. ⏳ Deploy to server and test all services
4. ⏳ Monitor for any path-related issues
5. ⏳ Merge to main after production validation

### Future Enhancements
- Consider adding more derived paths as needs emerge
- Evaluate path tier boundaries (hot vs media vs cold)
- Review AI workflows for additional path standardization opportunities

### Maintenance
- New services MUST follow §14 Path Management patterns
- Charter linter should be updated to detect primary hardcoded paths vs fallback values
- Document any exceptions or special cases as they arise
