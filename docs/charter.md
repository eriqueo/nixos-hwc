NixOS Configuration Charter v2
Owner: Eric
Scope: /etc/nixos - all machines, modules, profiles, and supporting files
Goal: Maintainable, predictable, and scalable NixOS configuration through modular architecture
Core Philosophy
We build a declarative system where:

Modules define capabilities (what CAN be configured)
Profiles set sensible defaults (what SHOULD be enabled together)
Machines specify reality (what IS actually deployed)

Architecture Principles
1. Hierarchical Composition
lib → modules → profiles → machines

Each layer depends only on layers to its left
No circular dependencies
Clear separation of concerns

2. Module Categories

modules/system/ - Core infrastructure (paths, storage, networking, gpu)
modules/services/ - System services (containers, daemons)
modules/programs/ - User applications (CLI tools, editors)
modules/desktop/ - Desktop environment components

3. Toggle Architecture

Modules define toggles via options.hwc.*
Profiles set default toggle values
Machines override for hardware reality
Example: enableGpu defined in module, enabled in profile, overridden in machine

4. Path Management

All paths flow from config.hwc.paths.*
Storage paths are nullable (not all machines have all tiers)
No hardcoded /mnt/* or /var/* paths in modules
Services check path existence before use

5. Machine Structure
Each machine is a directory containing:

config.nix - System configuration (imports profiles)
home.nix - User environment (if not headless)
hardware.nix - Hardware-specific configuration

Naming Conventions
Files

Kebab-case: arr-stack.nix, gpu-nvidia.nix
One service per file: No jellyfin-gpu.nix, use jellyfin.nix with enableGpu

Namespaces

hwc.system.* - System-level settings
hwc.services.* - Service configurations
hwc.programs.* - User program settings
hwc.desktop.* - Desktop environment
hwc.paths.* - Path definitions
hwc.gpu.* - GPU configuration

Operating Rules
For Modules

Options defined at top, config after
Config wrapped in mkIf cfg.enable
Use config.hwc.paths.* for all paths
Check nullable paths before use
Single responsibility per module

For Profiles

Import modules, set toggles only
No service implementation
No conditional logic beyond enable = true
Composable (media + monitoring = both enabled)

For Machines

Import profiles + minimal overrides
Specify hardware reality (GPU type, storage paths)
Target: <50 lines
No service logic

Migration Principles
No Breaking Changes

Changes are toggleable
Old behavior preserved until explicitly migrated
Deprecation warnings before removal

Incremental Progress

One service at a time
Test after each change
Rollback always possible

Build/Test Workflow
bash# Development
sudo nixos-rebuild build --flake .#machine-name  # Compile only
sudo nixos-rebuild test --flake .#machine-name   # Apply until reboot
sudo nixos-rebuild switch --flake .#machine-name # Persist

# Validation
journalctl -p 4 -b | grep -E 'hwc|error|warn'   # Check logs
systemctl --failed                               # Check services

# Commit
grebuild "message"                                # Git commit + switch
Success Metrics
Code Quality

No duplicate service definitions
Zero hardcoded paths
alejandra formatting clean
statix no warnings
deadnix <5 unused items

System Quality

Build time <2 minutes
All services start successfully
No errors in journal
Machine configs <50 lines

Anti-Patterns to Avoid
❌ Service Variants as Separate Files
nix# WRONG
modules/services/jellyfin.nix
modules/services/jellyfin-gpu.nix
❌ Hardcoded Paths
nix# WRONG
dataDir = "/mnt/hot/jellyfin";
❌ Logic in Profiles
nix# WRONG - profiles/media.nix
config = mkIf (config.hostname == "server") { ... }
❌ Nested Service Directories
nix# WRONG
modules/services/media/jellyfin.nix
modules/services/media/plex.nix
Correct Patterns
✅ Single Module with Toggles
nix# RIGHT - modules/services/jellyfin.nix
options.hwc.services.jellyfin = {
  enable = mkEnableOption "Jellyfin";
  enableGpu = mkEnableOption "GPU acceleration";
};
✅ Dynamic Paths
nix# RIGHT
dataDir = "${config.hwc.paths.hot}/jellyfin";
✅ Pure Profiles
nix# RIGHT - profiles/media.nix
hwc.services.jellyfin.enable = true;
hwc.services.jellyfin.enableGpu = true;
✅ Flat Service Structure
nix# RIGHT
modules/services/jellyfin.nix
modules/services/plex.nix
profiles/media.nix  # Groups them
Glossary

Module: Defines configuration options and implementation
Profile: Bundle of modules with default settings
Machine: Specific hardware running profiles
Toggle: Boolean option to enable/disable features
Shim: Deprecated redirect to new location
mkIf: Conditional configuration application
mkDefault: Overridable default value
mkForce: Non-overridable value

Charter Versioning

v1: Original monolithic structure
v2: Current modular architecture (2024-01)
Future versions require RFC and migration plan


This charter supersedes all previous versions. When in doubt, favor simplicity and maintainability over cleverness.
