# NixOS Configuration Charter v3

**Owner:** Eric  
**Scope:** /etc/nixos - all machines, modules, profiles, and supporting files  
**Goal:** Maintainable, predictable, and scalable NixOS configuration through modular architecture  

## Core Philosophy

We build a declarative system where:
- **Modules** define capabilities (what CAN be configured)
- **Profiles** set sensible defaults (what SHOULD be enabled together)  
- **Machines** specify reality (what IS actually deployed)

## Architecture Principles

### 1. Hierarchical Composition
```
lib → modules → profiles → machines
```
- Each layer depends only on layers to its left
- No circular dependencies
- Clear separation of concerns

### 2. Module Categories

```
modules/
├── system/          # Core infrastructure (paths, storage, networking, gpu)
├── services/        # System services organized by theme
│   ├── media/       # jellyfin.nix, immich.nix, sonarr.nix
│   ├── monitoring/  # prometheus.nix, grafana.nix
│   ├── network/     # caddy.nix, vpn.nix
│   ├── ai/          # ollama.nix, ai-bible.nix
│   └── utility/     # ntfy.nix, databases split into individual files
├── programs/        # User applications (CLI tools, editors)
└── home/           # Desktop environment components
```

### 3. Toggle Architecture
- **Modules** define toggles via `options.hwc.*`
- **Profiles** set default toggle values
- **Machines** override for hardware reality
- **Example:** `enableGpu` defined in module, enabled in profile, overridden in machine

### 4. Path Management
- All paths flow from `config.hwc.paths.*`
- Storage paths are nullable (not all machines have all tiers)
- No hardcoded `/mnt/*` or `/var/*` paths in modules
- Services validate path existence before use

### 5. Machine Structure
Each machine is a directory containing:
- `config.nix` - System configuration (imports profiles)
- `home.nix` - User environment (if not headless)
- `hardware.nix` - Hardware-specific configuration

## File Standards

### File Template
All modules must follow this standardized format:

```nix
# nixos-hwc/modules/category/service-name.nix
#
# Service Name
# Brief description of what this service provides
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.* (modules/system/paths.nix)
#   Upstream: config.hwc.gpu.type (modules/system/gpu.nix) [optional]
#
# USED BY:
#   Downstream: profiles/profile-name.nix (enables this service)
#   Downstream: machines/machine-name/config.nix (may override)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile-name.nix: ../modules/category/service-name.nix
#
# USAGE:
#   hwc.category.serviceName.enable = true;
#   hwc.category.serviceName.option = value;
#
# VALIDATION:
#   - List required dependencies and assertions

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.category.serviceName;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.category.serviceName = {
    # Options definition
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Implementation with assertions for validation
  };
}
```

### Naming Conventions

**Files:**
- Kebab-case: `arr-stack.nix`, `gpu-nvidia.nix`
- One service per file: No `jellyfin-gpu.nix`, use `jellyfin.nix` with `enableGpu`

**Namespaces:**
- `hwc.system.*` - System-level settings
- `hwc.services.*` - Service configurations  
- `hwc.programs.*` - User program settings
- `hwc.home.*` - Desktop environment
- `hwc.paths.*` - Path definitions
- `hwc.gpu.*` - GPU configuration

## Operating Rules

### For Modules
- **File Headers:** All modules must include purpose, dependencies, usage examples, and import requirements
- **Options** defined at top, `config` after
- **Config** wrapped in `mkIf cfg.enable`
- **Paths:** Use `config.hwc.paths.*` for all paths
- **Validation:** Check nullable paths and dependencies before use with assertions
- **Single Responsibility:** One service per module
- **Comments:** Use section headers (`#====`) for visual organization

### For Profiles
- Import modules, set toggles only
- No service implementation
- No conditional logic beyond `enable = true`
- Composable (media + monitoring = both enabled)
- Move all configuration details to modules via options

### For Machines
- Import profiles + minimal overrides
- Specify hardware reality (GPU type, storage paths)
- No service logic - only hardware-specific settings

### File Modification Protocol
⚠️ **CRITICAL:** Modifying file names or dependencies requires updating all upstream imports

**Before renaming or moving files:**
1. Search codebase for all imports of the file
2. Update all `import` statements in profiles and machines
3. Update all documentation references
4. Test build after each change
5. Commit changes atomically

**Example Impact Chain:**
```
modules/services/jellyfin.nix → profiles/media.nix → machines/server/config.nix
```
Renaming `jellyfin.nix` breaks the entire chain unless all imports are updated.

## Migration Principles

### No Breaking Changes
- Changes are toggleable
- Old behavior preserved until explicitly migrated
- Deprecation warnings before removal

### Incremental Progress
- One service at a time
- Test after each change
- Rollback always possible

## Build/Test Workflow

```bash
# Development
sudo nixos-rebuild build --flake .#machine-name  # Compile only
sudo nixos-rebuild test --flake .#machine-name   # Apply until reboot
sudo nixos-rebuild switch --flake .#machine-name # Persist

# Validation
journalctl -p 4 -b | grep -E 'hwc|error|warn'   # Check logs
systemctl --failed                               # Check services

# Commit
grebuild "message"                                # Git commit + switch
```

## Success Metrics

### Code Quality
- No duplicate service definitions
- Zero hardcoded paths outside `modules/system/paths.nix`
- `alejandra` formatting clean
- `statix` no warnings
- `deadnix` <5 unused items
- All modules have complete headers with dependency tracking

### System Quality
- Build time <2 minutes
- All services start successfully
- No errors in journal
- All assertions pass

## Anti-Patterns to Avoid

❌ **Service Variants as Separate Files**
```nix
# WRONG
modules/services/media/jellyfin.nix
modules/services/media/jellyfin-gpu.nix
```

❌ **Hardcoded Paths Outside Path Module**
```nix
# WRONG
dataDir = "/mnt/hot/jellyfin";
```

❌ **Logic in Profiles**
```nix
# WRONG - profiles/media.nix
config = mkIf (config.hostname == "server") { ... }
```

❌ **Missing Dependencies Check**
```nix
# WRONG - No validation of required paths/hardware
config = lib.mkIf cfg.enable {
  # Uses paths.storage.hot without checking if it exists
};
```

❌ **Incomplete File Headers**
```nix
# WRONG - Missing dependency tracking
# modules/services/jellyfin.nix
# Jellyfin service
```

## Correct Patterns

✅ **Single Module with Toggles**
```nix
# RIGHT - modules/services/media/jellyfin.nix
options.hwc.services.jellyfin = {
  enable = mkEnableOption "Jellyfin";
  enableGpu = mkEnableOption "GPU acceleration";
};
```

✅ **Dynamic Paths with Validation**
```nix
# RIGHT
dataDir = "${config.hwc.paths.storage.hot}/jellyfin";

# With validation
assertions = [
  {
    assertion = config.hwc.paths.storage.hot != null;
    message = "Jellyfin requires hot storage path to be configured";
  }
];
```

✅ **Pure Profiles**
```nix
# RIGHT - profiles/media.nix
hwc.services.jellyfin.enable = true;
hwc.services.jellyfin.enableGpu = true;
```

✅ **Themed Service Organization**
```nix
# RIGHT - Organized by domain, one service per file
modules/services/media/jellyfin.nix
modules/services/media/immich.nix
profiles/media.nix  # Groups them
```

✅ **Complete File Headers**
```nix
# RIGHT - Full dependency tracking and usage documentation
# DEPENDENCIES: Lists all upstream requirements
# USED BY: Lists all downstream consumers  
# IMPORTS REQUIRED IN: Exact import paths needed
```

## Path Management Structure

Centralized path definitions with organized categories:

```nix
# modules/system/paths.nix
options.hwc.paths = {
  storage = {
    hot = mkOption { ... };      # Fast storage tier
    cold = mkOption { ... };     # Slow/backup storage
    media = mkOption { ... };    # Media library storage
  };
  
  state = {
    services = mkOption { default = "/var/lib/hwc/services"; };
    user = mkOption { default = "/var/lib/hwc/user"; };
  };
  
  cache = {
    system = mkOption { default = "/var/cache/hwc"; };
    media = mkOption { default = "/var/cache/hwc/media"; };
  };
};
```

## Glossary

- **Module:** Defines configuration options and implementation
- **Profile:** Bundle of modules with default settings
- **Machine:** Specific hardware running profiles
- **Toggle:** Boolean option to enable/disable features
- **Shim:** Deprecated redirect to new location
- **mkIf:** Conditional configuration application
- **mkDefault:** Overridable default value
- **mkForce:** Non-overridable value
- **Assertion:** Validation check that prevents invalid configurations

## Charter Versioning

- **v1:** Original monolithic structure
- **v2:** Initial modular architecture (2024-01)
- **v3:** Themed organization with dependency tracking (2024-01)

Future versions require RFC and migration plan.

---

**This charter supersedes all previous versions. When in doubt, favor simplicity and maintainability over cleverness.**

