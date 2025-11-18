---
name: Module Migrate
description: Automated workflow to migrate existing nixos-hwc modules to Charter v6.0 compliance by refactoring structure, namespace, and validation
---

# Module Migrate Workflow

This skill provides **automated migration** of existing modules to Charter v6.0 compliance.

## What This Skill Does

When you have a non-compliant module, this skill:

1. ✅ Analyzes current structure
2. ✅ Extracts options → creates `options.nix`
3. ✅ Fixes namespace to match folder structure
4. ✅ Separates sys.nix if HM app has system code
5. ✅ Adds validation section with assertions
6. ✅ Moves to correct domain if misplaced
7. ✅ Updates profile imports
8. ✅ Validates build succeeds

**Token savings**: ~85% - automated pattern-based refactoring.

## Usage

Say: **"Migrate module [path] to charter compliance"**

Examples:
- "Migrate module domains/home/apps/firefox to charter compliance"
- "Fix charter violations in domains/server/containers/postgres"
- "Refactor domains/system/services/backup for charter v6.0"

## Migration Workflow

### Step 1: Analyze Current Structure

```bash
# Identify what exists
MODULE_PATH="$1"  # e.g., domains/home/apps/firefox

ls -la "$MODULE_PATH"
# Check for:
# - options.nix (exists?)
# - index.nix (exists?)
# - sys.nix (needed?)
# - Proper namespace?
```

**Read current files**:
- `index.nix` - find option definitions and implementations
- `options.nix` - check if exists and namespace is correct

### Step 2: Extract Options

If options defined in `index.nix` instead of `options.nix`:

```bash
# Find option definitions
rg "options\.hwc\." "$MODULE_PATH/index.nix"

# Extract to separate file
```

**Before** (non-compliant):
```nix
# domains/home/apps/firefox/index.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.home.apps.firefox;
in {
  # ❌ Options defined here instead of options.nix
  options.hwc.home.apps.firefox = {
    enable = lib.mkEnableOption "Firefox browser";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.firefox;
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      package = cfg.package;
    };
  };
}
```

**After** (compliant):
```nix
# domains/home/apps/firefox/options.nix
{ lib, pkgs, ... }: {
  options.hwc.home.apps.firefox = {
    enable = lib.mkEnableOption "Firefox browser";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.firefox;
      description = "Firefox package to use";
    };
  };
}

# domains/home/apps/firefox/index.nix
{ lib, config, ... }:
let
  cfg = config.hwc.home.apps.firefox;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      package = cfg.package;
    };
  };
}
```

### Step 3: Fix Namespace

Verify namespace matches folder structure exactly.

**Before** (wrong namespace):
```nix
# File: domains/home/apps/firefox/options.nix
options.hwc.home.firefox = { ... };  # ❌ Missing 'apps'
```

**After** (correct namespace):
```nix
# File: domains/home/apps/firefox/options.nix
options.hwc.home.apps.firefox = { ... };  # ✅ Matches folder path
```

**Pattern**:
```
domains/<domain>/<category>/<name>/ → hwc.<domain>.<category>.<name>.*
```

### Step 4: Separate System Lane Code

If HM module has system-lane code, extract to `sys.nix`:

**Before** (violation):
```nix
# domains/home/apps/kitty/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.kitty;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # HM config (correct)
    programs.kitty = {
      enable = true;
      settings = { ... };
    };

    # ❌ System config in HM module!
    environment.systemPackages = [ pkgs.kitty-themes ];
  };
}
```

**After** (compliant):
```nix
# domains/home/apps/kitty/index.nix
{ config, lib, ... }:
let
  cfg = config.hwc.home.apps.kitty;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # ✅ Only HM config here
    programs.kitty = {
      enable = true;
      settings = { ... };
    };
  };
}

# domains/home/apps/kitty/sys.nix (NEW)
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.kitty;
in {
  config = lib.mkIf cfg.enable {
    # ✅ System-lane code
    environment.systemPackages = [ pkgs.kitty-themes ];
  };
}
```

**Update profile imports**:
```nix
# profiles/system.nix
imports = [
  # ... existing imports ...
  ../domains/home/apps/kitty/sys.nix  # Add this
];
```

### Step 5: Add Validation Section

If module has dependencies but no validation:

**Before**:
```nix
# domains/home/apps/waybar/index.nix
{ config, lib, ... }:
let
  cfg = config.hwc.home.apps.waybar;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    programs.waybar = {
      enable = true;
      # ... waybar needs hyprland but no check!
    };
  };
}
```

**After**:
```nix
{ config, lib, ... }:
let
  cfg = config.hwc.home.apps.waybar;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    programs.waybar = {
      enable = true;
      # ...
    };

    # VALIDATION
    assertions = [{
      assertion = !cfg.enable || config.hwc.home.apps.hyprland.enable;
      message = "waybar requires hyprland to be enabled";
    }];
  };
}
```

### Step 6: Move to Correct Domain

If module is in wrong domain:

**Example**: Firefox in system domain instead of home

```bash
# Wrong location
domains/system/apps/firefox/

# Move to correct location
git mv domains/system/apps/firefox domains/home/apps/firefox

# Update namespace if needed
sed -i 's/hwc\.system\.apps\.firefox/hwc.home.apps.firefox/g' \
  domains/home/apps/firefox/options.nix \
  domains/home/apps/firefox/index.nix

# Update profile imports
# In profiles/system.nix - remove old import
# In profiles/home.nix - add new import
```

### Step 7: Update Profile Imports

Ensure module imported in correct profile section:

**profiles/home.nix**:
```nix
{
  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================

  imports = [
    # ... existing imports ...
    ../domains/home/apps/firefox  # Add if not present
  ];

  # Default enabled
  hwc.home.apps.firefox.enable = lib.mkDefault true;
}
```

If sys.nix exists, add to **profiles/system.nix**:
```nix
imports = [
  # ... existing imports ...
  ../domains/home/apps/firefox/sys.nix  # If exists
];
```

### Step 8: Validate Build

```bash
# Dry build to check for errors
nixos-rebuild dry-build --flake .#laptop

# If successful, build and test
nixos-rebuild build --flake .#laptop

# Deploy if all checks pass
nixos-rebuild switch --flake .#laptop
```

## Common Migration Patterns

### Pattern 1: Ad-hoc Options → Separate File

```bash
# Extract all option definitions from index.nix
grep -A 20 "options\.hwc\." domains/home/apps/firefox/index.nix > /tmp/options.txt

# Create options.nix with extracted content
# Remove from index.nix
# Add imports = [ ./options.nix ]; to index.nix
```

### Pattern 2: Wrong Namespace

```bash
# Find current namespace
CURRENT_NS=$(rg "options\.hwc\." domains/home/apps/firefox/options.nix | head -1)

# Determine correct namespace from path
# domains/home/apps/firefox → hwc.home.apps.firefox

# Replace
sed -i 's/hwc\.home\.firefox/hwc.home.apps.firefox/g' \
  domains/home/apps/firefox/options.nix \
  domains/home/apps/firefox/index.nix
```

### Pattern 3: Mixed Domain Code

```bash
# Find system code in HM module
rg "systemd\.services|environment\.systemPackages" domains/home/apps/kitty/index.nix

# If found, extract to sys.nix:
# 1. Copy the system code
# 2. Create sys.nix with same config structure
# 3. Remove from index.nix
# 4. Add sys.nix import to profiles/system.nix
```

### Pattern 4: No Validation

```bash
# Find modules with enable but no assertions
find domains/ -name "index.nix" | while read file; do
  if grep -q "mkEnableOption" "$(dirname $file)/options.nix" 2>/dev/null; then
    if ! grep -q "assertions" "$file"; then
      echo "Missing validation: $file"
    fi
  fi
done

# Add VALIDATION section to each
```

## Checklist for Migration

Before marking module as migrated:

- [ ] `options.nix` exists in module directory
- [ ] All options declared in `options.nix`, not `index.nix`
- [ ] Namespace matches folder structure exactly
- [ ] `index.nix` imports `options.nix` at top
- [ ] System-lane code moved to `sys.nix` (if applicable)
- [ ] `sys.nix` imported in `profiles/system.nix` (if applicable)
- [ ] Module in correct domain (home/system/server/infrastructure)
- [ ] IMPLEMENTATION section in `index.nix`
- [ ] VALIDATION section with assertions (if dependencies)
- [ ] Imported in appropriate profile OPTIONAL section
- [ ] Build succeeds: `nixos-rebuild dry-build`
- [ ] Charter check passes (no violations)

## Batch Migration

To migrate multiple modules:

```bash
#!/bin/bash
# Batch migration script

MODULES=(
  "domains/home/apps/firefox"
  "domains/home/apps/kitty"
  "domains/server/containers/postgres"
)

for module in "${MODULES[@]}"; do
  echo "Migrating $module..."

  # Run migration workflow for each
  # (Invoke module-migrate skill)

  # Validate
  if nixos-rebuild dry-build --flake .#laptop 2>&1 | grep -q "error:"; then
    echo "❌ Migration failed for $module"
    exit 1
  fi

  echo "✅ Migrated $module"
done

echo "All modules migrated successfully!"
```

## Rollback Strategy

If migration breaks the build:

```bash
# Stash changes
git stash

# Verify old version builds
nixos-rebuild dry-build --flake .#laptop

# Re-apply changes incrementally
git stash pop

# Fix issues one at a time
# Use nixos-build-doctor skill to diagnose errors
```

## Testing After Migration

```bash
# 1. Build check
nixos-rebuild dry-build --flake .#laptop

# 2. Charter compliance check
# (Invoke charter-check skill)

# 3. Functional test
nixos-rebuild switch --flake .#laptop

# 4. Verify module still works
# Test the application/service
```

## Common Errors During Migration

### "Option does not exist"
**Cause**: Namespace changed but not updated everywhere
**Fix**: Search for old namespace and replace:
```bash
rg "hwc\.home\.firefox\." --type nix | grep -v "hwc.home.apps.firefox"
# Replace all instances
```

### "Attribute missing"
**Cause**: Moved module between domains, forgot to update imports
**Fix**: Update all profile imports

### "Infinite recursion"
**Cause**: Circular import created during migration
**Fix**: Check import chain, remove circular reference

### "Assertion failed"
**Cause**: Added assertion but dependency not enabled
**Fix**: Enable dependency or use `lib.mkDefault` to auto-enable

## Remember

Migration is **refactoring, not rewriting**:
- ✅ Preserve all functionality
- ✅ Keep same behavior
- ✅ Maintain feature parity
- ✅ Only reorganize structure

**Never** change functionality during migration!

Test thoroughly after each module migration.
Use charter-check and build-doctor skills for validation.

Migrations should be **safe, incremental, and reversible**!
