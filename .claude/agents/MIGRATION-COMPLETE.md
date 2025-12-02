# Migration Complete: Single-Source Script Organization

## Summary

Successfully migrated all scripts to `workspace/scripts/` and eliminated sprawl. All scripts now live in ONE location with standardized dependency verification.

## What Was Done

### 1. Extracted journal-errors ✅
- **From:** `domains/home/environment/shell/parts/journal-errors.nix` (Nix derivation)
- **To:** `workspace/scripts/monitoring/journal-errors.sh` (bash script)
- **Added:** Standardized dependency verification
- **Status:** Executable, ready to use

### 2. Consolidated grebuild ✅
- **Had two versions:**
  - `parts/grebuild.nix` (395 lines, older)
  - `workspace/scripts/development/grebuild.sh` (457 lines, newer)
- **Kept:** workspace version (more recent, more features)
- **Added:** Standardized dependency verification
- **Status:** Executable, ready to use

### 3. Standardized list-services ✅
- **Location:** `workspace/scripts/development/list-services.sh`
- **Added:** Standardized header and dependency verification
- **Status:** Executable, ready to use

### 4. Updated Shell Module ✅
- **Removed:** Nix script imports from `index.nix`
- **Removed:** Script enable options from `options.nix`
- **Added:** Shell functions for all daily drivers in `index.nix`
- **Kept:** All aliases in `options.nix` (unchanged)

### 5. Cleaned Up Sprawl ✅
- **Deleted:** `domains/home/environment/shell/parts/grebuild.nix`
- **Deleted:** `domains/home/environment/shell/parts/journal-errors.nix`
- **Deleted:** `domains/home/environment/shell/parts/` (empty directory)

### 6. Created Standards ✅
- **Created:** `workspace/scripts/DEPENDENCY-TEMPLATE.md`
- **Purpose:** Standardized pattern for all future scripts

## Final Structure

### Clean Architecture ✅

```
workspace/scripts/
├── development/
│   ├── grebuild.sh              ← Consolidated (was in parts/)
│   ├── list-services.sh         ← Standardized
│   ├── charter-lint.sh
│   └── (19 other dev scripts)
│
├── monitoring/
│   ├── journal-errors.sh        ← Migrated from parts/
│   ├── caddy-health-check.sh
│   ├── disk-space-monitor.sh
│   ├── gpu-monitor.sh
│   └── (3 other monitoring scripts)
│
├── automation/
│   ├── media-orchestrator.py
│   ├── qbt-finished.sh
│   └── sab-finished.py
│
├── maintenance/
│   └── (future scripts)
│
├── utils/
│   └── network/
│       └── (network diagnostic scripts)
│
├── README.md                    ← Documentation
└── DEPENDENCY-TEMPLATE.md       ← Standards

domains/home/environment/shell/
├── index.nix                    ← Functions only
└── options.nix                  ← Aliases only
```

### No More Sprawl ✅

**Before:**
```
parts/grebuild.nix (395 lines)                      ← Nix derivation
parts/journal-errors.nix (99 lines)                 ← Nix derivation
workspace/scripts/development/grebuild.sh (457 lines) ← Duplicate, ignored

= Scripts in MULTIPLE places, duplication, confusion
```

**After:**
```
workspace/scripts/development/grebuild.sh           ← Single source
workspace/scripts/monitoring/journal-errors.sh      ← Single source

= Scripts in ONE place, no duplication, clean
```

## Standardized Dependency Verification

### Pattern Applied

All daily driver scripts now follow this pattern:

```bash
#!/usr/bin/env bash
# script-name - Brief description
#
# Usage: script-name [args]
#
# Dependencies: tool1, tool2, tool3 (standard on NixOS)
# Location: workspace/scripts/category/script-name.sh
# Invoked by: Shell function in domains/home/environment/shell/index.nix

set -euo pipefail

#==============================================================================
# DEPENDENCY VERIFICATION
#==============================================================================
# Standard tools - should always exist on NixOS, but verify for robustness

REQUIRED_COMMANDS=(tool1 tool2 tool3)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' not found" >&2
    echo "This should not happen on a standard NixOS system." >&2
    exit 127
  fi
done

#==============================================================================
# CONFIGURATION
#==============================================================================

# Config here...

#==============================================================================
# MAIN LOGIC
#==============================================================================

# Script logic here...
```

### Scripts Standardized

1. ✅ **grebuild.sh** - Verifies: git, nixos-rebuild, sudo, curl, systemctl
2. ✅ **journal-errors.sh** - Verifies: journalctl, awk, sed, grep, wc, sort, uniq, tail
3. ✅ **list-services.sh** - Verifies: systemctl, podman, awk, grep

### Benefits

- **Robust:** Scripts fail fast if dependencies missing
- **Documented:** Clear what each script needs
- **Portable:** Can export to other machines
- **Standardized:** Consistent pattern across all scripts
- **Exit code 127:** Standard "command not found" error

## Shell Module Configuration

### index.nix (Updated) ✅

**Removed:**
```nix
let
  grebuildScript = import ./parts/grebuild.nix { inherit pkgs; };
  journalErrorsScript = import ./parts/journal-errors.nix { inherit pkgs; };
in
{
  home.packages = [ grebuildScript journalErrorsScript ];
}
```

**Added:**
```nix
programs.zsh = {
  initContent = ''
    # Daily driver script functions
    grebuild() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/grebuild.sh "$@"
    }
    
    journal-errors() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/journal-errors.sh "$@"
    }
    
    list-services() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/list-services.sh "$@"
    }
    
    charter-lint() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/charter-lint.sh "$@"
    }
    
    caddy-health() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/caddy-health-check.sh "$@"
    }
  '';
};
```

### options.nix (Simplified) ✅

**Removed:**
```nix
scripts = {
  grebuild = lib.mkOption { ... };
  journalErrors = lib.mkOption { ... };
};
```

**Replaced with:**
```nix
# Scripts are now defined as shell functions in index.nix
# No need for enable options - they're always available
```

**Kept (unchanged):**
```nix
aliases = {
  "rebuild" = "grebuild";
  "errors" = "journal-errors";
  "services" = "list-services";
  "ss" = "list-services";
  "lint" = "charter-lint";
  "caddy" = "caddy-health";
  "health" = "caddy-health";
};
```

## How to Test

### 1. Rebuild
```bash
cd ~/.nixos
grebuild "refactor: consolidate scripts to workspace, eliminate sprawl"
```

### 2. Test Commands
```bash
# All commands should work
grebuild "test message"
rebuild "test message"     # via alias

journal-errors
errors                     # via alias
errors-hour                # via alias

list-services
services                   # via alias
ss                         # via alias

charter-lint domains/
lint domains/              # via alias

caddy-health
caddy                      # via alias
health                     # via alias
```

### 3. Verify Scripts
```bash
# Check scripts exist
ls -lh workspace/scripts/development/grebuild.sh
ls -lh workspace/scripts/monitoring/journal-errors.sh
ls -lh workspace/scripts/development/list-services.sh

# Check they're executable
file workspace/scripts/development/grebuild.sh
file workspace/scripts/monitoring/journal-errors.sh

# Check old files are gone
ls domains/home/environment/shell/parts/  # Should error (directory deleted)
```

### 4. Test Dependency Verification
```bash
# Scripts should verify dependencies on startup
bash workspace/scripts/development/grebuild.sh --help
bash workspace/scripts/monitoring/journal-errors.sh
bash workspace/scripts/development/list-services.sh
```

## Benefits Achieved

### ✅ No Sprawl
- All scripts in ONE location (`workspace/scripts/`)
- No duplication between `parts/` and `workspace/`
- No confusion about which version is used

### ✅ Charter Compliant
- Module defines invocation, not implementation
- Scripts are implementation details
- Clean separation of concerns

### ✅ Easy Maintenance
- Edit scripts directly in `workspace/scripts/`
- No rebuild required for script changes
- Version control tracks actual scripts

### ✅ Standardized
- Consistent header format
- Consistent dependency verification
- Consistent error handling (exit 127)

### ✅ Robust
- Scripts verify dependencies
- Fail fast with clear error messages
- Portable to other machines

### ✅ Dual-Use
- Same scripts work with AI agents
- Same scripts work from terminal
- Single source of truth

## Files Changed

### Created ✅
- `workspace/scripts/monitoring/journal-errors.sh` (extracted from Nix)
- `workspace/scripts/DEPENDENCY-TEMPLATE.md` (standards)

### Modified ✅
- `workspace/scripts/development/grebuild.sh` (added dependency verification)
- `workspace/scripts/development/list-services.sh` (added standardized header)
- `domains/home/environment/shell/index.nix` (removed imports, added functions)
- `domains/home/environment/shell/options.nix` (removed script options)

### Deleted ✅
- `domains/home/environment/shell/parts/grebuild.nix`
- `domains/home/environment/shell/parts/journal-errors.nix`
- `domains/home/environment/shell/parts/` (directory)

## Next Steps

### Immediate
1. ✅ Migration complete
2. ⏳ Test rebuild
3. ⏳ Verify all commands work
4. ⏳ Commit changes

### Future
1. **Apply pattern to other scripts** - Add standardized headers to remaining scripts
2. **Create agents** - Build Claude agents that use these scripts
3. **Add skills** - Create skills for common workflows
4. **More commands** - Add `disk-check`, `system-health`, etc.

## Commit Message

```bash
grebuild "refactor: consolidate scripts to workspace, eliminate sprawl

- Migrate journal-errors from Nix derivation to workspace script
- Consolidate grebuild (removed duplicate Nix version)
- Add standardized dependency verification to all daily drivers
- Update shell module to use functions instead of Nix imports
- Delete parts/ directory (no longer needed)
- Create DEPENDENCY-TEMPLATE.md for future scripts

Benefits:
- All scripts in ONE location (workspace/scripts/)
- No sprawl, no duplication
- Charter compliant architecture
- Standardized dependency verification
- Easy to maintain and update

Scripts affected: grebuild, journal-errors, list-services
"
```

## Summary

**Before:** Scripts scattered in `parts/` and `workspace/`, duplication, Nix complexity
**After:** All scripts in `workspace/scripts/`, standardized, clean, simple

**Result:** Single-source organization with robust dependency verification and no sprawl.

✅ **Migration complete and ready to test!**
