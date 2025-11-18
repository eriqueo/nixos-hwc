---
name: NixOS Charter Compliance
description: Reviews code for Charter v6.0 compliance in nixos-hwc, validates domain boundaries, namespace patterns, and architectural rules using targeted searches
---

# NixOS Charter Compliance

You are an expert at **reviewing code for Charter v6.0 compliance** in the nixos-hwc repository.

## Charter Rules (Internalized)

### Core Architectural Principles

1. **Namespace→Folder Mapping**: `domains/<domain>/<category>/<name>/ → hwc.<domain>.<category>.<name>.*`
2. **Options-First**: All options declared in `options.nix`, never ad-hoc
3. **Domain Separation**: Clear boundaries between system/home/infrastructure/server/secrets
4. **Lane Purity**: System and HM lanes never cross-import
5. **One Concern Per Module**: Each directory handles exactly one logical thing
6. **Profile Structure**: BASE (required) and OPTIONAL (defaults) sections
7. **Validation Required**: Modules with dependencies must have assertions

### Domain Boundaries

| Domain | Can Contain | Cannot Contain |
|--------|-------------|----------------|
| **home** | `programs.*`, `home.*`, HM `services.*` | `systemd.services`, `environment.systemPackages`, `users.*` |
| **system** | `users.*`, `environment.*`, `systemd.services` | HM options (`programs.*`, `home.*`) |
| **server** | Containers, native services, databases | HM configs |
| **infrastructure** | GPU, power, virtualization, hardware | HM configs, secret declarations |
| **secrets** | Age declarations, permissions | Secret values (only .age files) |

## Compliance Checks

### 1. Namespace Alignment

**Rule**: Folder structure MUST match option namespace exactly.

**Check**:
```bash
# For each module, verify namespace matches folder
# Example: domains/home/apps/firefox/options.nix

# Should define: hwc.home.apps.firefox.*
# NOT: hwc.home.firefox.* (missing 'apps')
# NOT: hwc.firefox.* (missing 'home.apps')

# Search pattern
rg "options\.hwc\." domains/home/apps/firefox/options.nix

# Expected: options.hwc.home.apps.firefox
```

**Violation Example**:
```nix
# ❌ Wrong - namespace doesn't match folder
# File: domains/home/apps/firefox/options.nix
options.hwc.home.firefox = { ... };  # Missing 'apps'

# ✅ Right
options.hwc.home.apps.firefox = { ... };
```

### 2. Domain Boundary Violations

**Rule**: Domains must respect boundaries. No HM in system, no system in HM.

**Checks**:
```bash
# HM in system domain (VIOLATION)
rg "programs\." domains/system/ --type nix
rg "home\." domains/system/ --type nix
rg "services\.(.*) = \{" domains/system/ --type nix | grep -v systemd

# System in home domain (VIOLATION - except sys.nix)
rg "systemd\.services" domains/home/ --type nix | grep -v sys.nix
rg "environment\.systemPackages" domains/home/ --type nix | grep -v sys.nix

# Home Manager activation in profiles (VIOLATION - except profiles/home.nix)
rg "home-manager" profiles/ --type nix | grep -v profiles/home.nix
```

**Violation Example**:
```nix
# ❌ Wrong - HM option in system domain
# File: domains/system/apps/firefox/index.nix
programs.firefox.enable = true;  # This is HM!

# ✅ Right - Move to domains/home/apps/firefox/
```

### 3. Options.nix Mandatory

**Rule**: Every module MUST have `options.nix` defining its API.

**Check**:
```bash
# Find all module directories
find domains/ -type d -mindepth 3 -maxdepth 4

# For each, verify options.nix exists
# Example: domains/home/apps/firefox/
ls domains/home/apps/firefox/options.nix

# Verify it's imported in index.nix
rg 'imports.*\[\s*.*\.\/options\.nix' domains/home/apps/firefox/index.nix
```

**Violation Example**:
```nix
# ❌ Wrong - options defined in index.nix
# File: domains/home/apps/firefox/index.nix
{ lib, ... }: {
  options.hwc.home.apps.firefox.enable = lib.mkEnableOption "Firefox";
  config = { ... };
}

# ✅ Right - options in separate file
# File: domains/home/apps/firefox/options.nix
{ lib, ... }: {
  options.hwc.home.apps.firefox.enable = lib.mkEnableOption "Firefox";
}

# File: domains/home/apps/firefox/index.nix
{ lib, config, ... }: {
  imports = [ ./options.nix ];
  config = { ... };
}
```

### 4. Lane Purity

**Rule**: Lanes never import each other's `index.nix`.

**Exception**: `sys.nix` files ARE system-lane code, even when co-located in `domains/home/`.

**Check**:
```bash
# Home lane importing system lane index (VIOLATION)
rg 'imports.*domains/system/.*/index\.nix' domains/home/ --type nix

# System lane importing home lane index (VIOLATION)
rg 'imports.*domains/home/.*/index\.nix' domains/system/ --type nix

# Valid: sys.nix imported by system profile
rg 'imports.*domains/home/.*/sys\.nix' profiles/system.nix
```

**Correct Pattern**:
```nix
# ✅ System profile importing HM sys.nix files
# File: profiles/system.nix
imports = [
  ../domains/home/apps/kitty/sys.nix  # Valid - system lane code
  ../domains/system/packages
];
```

### 5. Validation Sections

**Rule**: Modules with `enable` toggle and dependencies MUST have assertions.

**Check**:
```bash
# Find modules with enable option
rg "enable = lib\.mkEnableOption" domains/ -l

# For each, check if it has validation section
# Look for "# VALIDATION" comment and assertions

# Example check
cat domains/home/apps/waybar/index.nix | rg -A 10 "# VALIDATION"
```

**Violation Example**:
```nix
# ❌ Wrong - no validation for dependency
# File: domains/home/apps/waybar/index.nix
{ config, lib, ... }:
let cfg = config.hwc.home.apps.waybar;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # Waybar needs Hyprland but no assertion!
    programs.waybar = { ... };
  };
}

# ✅ Right - includes validation
{ config, lib, ... }:
let cfg = config.hwc.home.apps.waybar;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    programs.waybar = { ... };

    # VALIDATION
    assertions = [{
      assertion = !cfg.enable || config.hwc.home.apps.hyprland.enable;
      message = "waybar requires hyprland to be enabled";
    }];
  };
}
```

### 6. Profile Structure

**Rule**: Profiles must have clear BASE and OPTIONAL sections.

**Check**:
```bash
# Verify profiles have section headers
rg "# BASE|# OPTIONAL" profiles/

# Each profile should have both sections clearly marked
cat profiles/system.nix | rg "^  #.*BASE|^  #.*OPTIONAL"
```

**Correct Pattern**:
```nix
# ✅ profiles/system.nix
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  imports = [
    ../domains/system/core
    ../domains/system/users
  ];

  # Essential settings
  hwc.system.core.enable = true;

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  imports = [
    ../domains/system/packages
  ];

  # Override per machine as needed
  hwc.system.packages.development.enable = lib.mkDefault true;
}
```

### 7. Hardcoded Values (Anti-Pattern)

**Rule**: No hardcoded colors (use theme system), no hardcoded paths, no hardcoded secrets.

**Checks**:
```bash
# Hardcoded colors (VIOLATION - should use theme)
rg '#[0-9a-fA-F]{6}' domains/home/apps/ --type nix

# Hardcoded /mnt paths (VIOLATION - should be configurable)
rg '"/mnt/' domains/ --type nix

# Hardcoded secrets (VIOLATION - use agenix)
rg 'password.*=.*"[^/]' domains/ --type nix | grep -v agenix
```

### 8. Single Source of Truth

**Rule**: No multiple writers to same path. Each option should be set in exactly one place.

**Check**:
```bash
# Find duplicate option assignments
# Example: home.stateVersion set in multiple places
rg 'home\.stateVersion' --type nix

# Should only be in machine-specific home.nix
```

## Quick Compliance Scan

Run all anti-pattern searches:

```bash
#!/bin/bash
# Charter compliance quick scan

echo "=== Domain Boundary Violations ==="
echo "HM in system domain:"
rg "programs\.|^[[:space:]]*home\." domains/system/ --type nix | head -5

echo -e "\nSystem in home domain (excluding sys.nix):"
rg "systemd\.services|environment\.systemPackages" domains/home/ --type nix | grep -v sys.nix | head -5

echo -e "\n=== Missing options.nix ==="
find domains/ -type d -mindepth 3 -maxdepth 4 | while read dir; do
  if [ ! -f "$dir/options.nix" ] && [ ! -f "$dir/index.nix" ]; then
    continue  # Not a module
  fi
  if [ ! -f "$dir/options.nix" ]; then
    echo "Missing: $dir/options.nix"
  fi
done

echo -e "\n=== Namespace Alignment Issues ==="
# Would need per-file checks - manual review

echo -e "\n=== Hardcoded Colors ==="
rg '#[0-9a-fA-F]{6}' domains/home/apps/ --type nix | head -5

echo -e "\n=== Hardcoded Secrets ==="
rg 'password.*=.*"[^/].*"' domains/ --type nix | grep -v agenix | head -5

echo -e "\nScan complete. Review above for violations."
```

## Your Review Process

When asked to review code for charter compliance:

### 1. Identify Scope

Ask:
- Specific module? (`domains/home/apps/firefox`)
- Entire domain? (`domains/home/`)
- All changes in recent commit?
- Whole repository audit?

### 2. Run Targeted Checks

Based on scope, run relevant anti-pattern searches from above.

**Don't** read every file - use `rg` searches to find violations!

### 3. Report Violations

For each violation found:
- **Location**: File:line
- **Violation**: Which rule broken
- **Impact**: Why it matters
- **Fix**: How to correct it

### 4. Suggest Refactor

If needed, provide step-by-step refactor plan:
1. Move code to correct domain
2. Update namespace to match folder
3. Add options.nix if missing
4. Add validation section
5. Update profile imports

## Common Violations & Fixes

### Wrong Namespace
```bash
# Find
rg "options\.hwc\." domains/home/apps/firefox/

# Fix
# Update to match folder: hwc.home.apps.firefox.*
```

### Domain Violation
```bash
# Find
rg "programs\." domains/system/

# Fix
# Move to domains/home/
```

### Missing Options File
```bash
# Find
ls domains/home/apps/firefox/options.nix || echo "Missing!"

# Fix
# Create options.nix with proper namespace
```

### Missing Validation
```bash
# Find modules without assertions
rg "enable = lib\.mkEnableOption" domains/home/apps/waybar/ -l | \
  xargs -I {} sh -c 'rg "assertions" {} || echo "Missing: {}"'

# Fix
# Add # VALIDATION section with assertions
```

## Token-Saving Strategy

**Use targeted searches, not full file reads!**

- ✅ Use `rg` with patterns to find violations
- ✅ Read only files with violations
- ✅ Use grep -c to count, not show all
- ❌ Don't read every file
- ❌ Don't explore unnecessarily

## Remember

Charter compliance ensures:
- **Debuggability**: Namespace→folder mapping
- **Maintainability**: Clear domain boundaries
- **Reliability**: Validation catches errors at build time
- **Scalability**: Consistent patterns across codebase

Your job is to **enforce these patterns** and **guide fixes**, not just report violations!
