NixOS Configuration Charter v6 (Unified, System.nix Era)

Owner: Eric
Scope: nixos-hwc/ — all machines, modules, profiles, HM, and supporting files
Goal: Maintainable, predictable, scalable, and reproducible NixOS through strict domain separation, repeatable patterns, and feature-preserving migration.

0) Preserve-First Doctrine

Refactor = reorganize, not rewrite.

100% feature parity during migrations.

Wrappers/adapters allowed only as temporary bridges (tracked and removed later).

Never switch on red builds.

1) Core Layering & Architecture Flow

**NixOS System:**  
`flake.nix` → `machines/<host>/config.nix` → `profiles/base.nix` → `modules/{system,infrastructure,services}/`

**Home Manager:**  
`machines/<host>/config.nix` → `machines/<host>/home.nix` → `modules/home/`

## Rules:
- Modules implement capabilities behind options
- Profiles orchestrate NixOS system imports/toggles only  
- Machines define hardware facts AND Home Manager activation
- Strict dependency direction (no cycles)
- Home Manager lives at machine level, not profile level

2) Domains & Responsibilities

| Domain | Purpose | Location | Must Contain | Must Not Contain |
|--------|---------|----------|--------------|------------------|
| Infrastructure | Hardware mgmt + system tools | `modules/infrastructure/` | GPU, power, udev, kernel toggles, system binaries | Home Manager configs |
| System | Core OS + user accounts | `modules/system/` | users, sudo, networking, security, secrets, paths, system packages | Home Manager configs |
| Services | Daemons & orchestration | `modules/services/` | containers, media/db/web stacks, monitoring | Home Manager configs |
| Home | User environment (Home Manager) | `modules/home/` | programs.*, home.*, WM/DE configs, shell configs | environment.systemPackages, systemd.services |
| Profiles | NixOS orchestration only | `profiles/` | System imports + toggles, no HM activation | Home Manager activation, implementation details |
| Machines | Hardware facts + HM activation | `machines/<host>/` | GPU type, storage, config.nix + home.nix | Shared logic, profile-like orchestration |

**Key Principle**: User account creation (`users.users.eric`) goes in `modules/system/users/eric.nix`. User environment configuration (`programs.zsh`, `home.packages`) goes in `modules/home/` imported by `machines/<host>/home.nix`.
3) Universal 5-File Pattern (System.nix + Parts)

For apps like Hyprland:

behavior.nix — binds, rules, commands

hardware.nix — monitors, input devices

session.nix — startup, lifecycle

appearance.nix — theming, decoration, animations

system.nix — NixOS module exporting options.hwc.infrastructure.* + config (system-wide tools, binaries)

Rules:

Parts export flat config objects, directly mergable.

system.nix follows full NixOS module template (options + config).

Co-location allowed: system.nix lives alongside app parts.

Merge pattern: (behavior // { "$mod" = "SUPER"; }) to flatten attributes.

4) Parts / Adapters / Tools Vocabulary

Parts (Home/UI): Nix attrsets extending program config.

Adapters (Home/UI): palette → app-specific theme transforms.

Tools (Infrastructure): binaries via environment.systemPackages.

This prevents domain confusion and ensures single source of truth.

5) Home-Manager Boundary

**CRYSTAL CLEAR RULE: Home Manager activation is MACHINE-SPECIFIC, not profile-based.**

## Machine-Specific Home Manager (machines/<host>/home.nix):
```nix
{ config, lib, pkgs, ... }: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.eric = { config, pkgs, ... }: {
      imports = [
        # Only Home Manager modules (programs.*, home.*, etc.)
        ../../modules/home/environment/shell.nix
        ../../modules/home/apps/hyprland
        ../../modules/home/apps/waybar
        ../../modules/home/apps/kitty.nix
      ];
      home.stateVersion = "24.05";
    };
  };
}
```

## System-Level User Configuration (modules/system/users/eric.nix):
- User account creation: `users.users.eric = { ... }`
- System packages: `environment.systemPackages = [ ... ]` 
- System services: `systemd.services.*`
- Imported by: `profiles/base.nix`

**Domain Separation Law**: 
- NixOS modules → `modules/system/`, `modules/infrastructure/`, `modules/services/`
- Home Manager modules → `modules/home/`
- Never mix `environment.systemPackages` with `home.packages` in same module


.zshenv is HM-owned, with guarded content:

home.file.".zshenv".text = ''
  HM_VARS="/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
  [ -r "$HM_VARS" ] && . "$HM_VARS"
'';


One writer per path.

6) Global Theming
modules/home/theme/
├─ palettes/deep-nord.nix
└─ adapters/
   ├─ waybar-css.nix
   └─ hyprland.nix


Palette = tokens (fg/bg/accent/etc).

Adapter = transforms palette → app settings.

No hardcoded colors in app configs.

7) File Standards

Files/dirs: kebab-case.nix

Options: camelCase (hwc.system.users.enable)

Scripts: domain-purpose (waybar-gpu-status)

Required headers/sections in all modules: OPTIONS / IMPLEMENTATION / VALIDATION

8) Enforcement Rules

Functional purity per domain.

Single source of truth.

Dependency direction only downward.

Interface segregation (toggle high-level, hide details).

No multiple writers to same file.

9) Validation & Anti-Patterns

**Search Commands (must be empty):**
```bash
rg "writeScriptBin" modules/home/              # Scripts belong in infrastructure
rg "systemd\.services" modules/home/           # Services belong in system/services
rg "environment\.systemPackages" modules/home/ # System packages belong in system
rg "home-manager" profiles/                    # HM activation belongs in machines
rg "/mnt/" modules/                            # No hardcoded mount paths
```

**Hard Blockers:**
- Home Manager activation in profiles (move to `machines/<host>/home.nix`)
- NixOS modules (`environment.systemPackages`) in Home Manager context
- Home Manager modules (`programs.*`, `home.*`) in system modules
- User account creation outside `modules/system/users/`
- Profiles with implementation logic (must only orchestrate imports)
- Mixed domain modules (e.g., both `users.users.eric` and `programs.zsh` in same file)

10) Migration Protocol

Discovery → list features & counts.

Classification → Part / Adapter / Tool.

Relocation → Parts/Adapters → Home, Tools → Infrastructure.

Interface → canonical tool names only.

Validation → build-only → smoke tests → switch.

11) Profiles & Machines

Profiles = additive orchestration only.

Machines = hardware facts only.

Example workstation profile enables GPU infra + Hyprland home + System auth.

12) Migration Status

✅ **Phase 1 (Domain Separation)**: COMPLETE
- User account creation moved to `modules/system/users/eric.nix` 
- Home Manager activation moved to `machines/laptop/home.nix`
- Crystal clear boundary: NixOS modules vs Home Manager modules
- Session variables working: `/etc/profiles/per-user/eric/etc/profile.d/hm-session-vars.sh`

🔄 **Phase 2 (Module Standardization)**: IN PROGRESS
- Apply 5-file pattern to remaining apps (Waybar, Betterbird, etc.)
- Standardize all modules with OPTIONS/IMPLEMENTATION/VALIDATION sections
- Clean up any remaining mixed-domain modules

⏳ **Phase 3 (Validation & Optimization)**: PENDING
- Run all validation commands ensure zero violations
- Performance optimization and build time improvements
- Documentation and retrospective

✅ This v6 is forward-compatible: you can use it for Hyprland now, then apply the same 5-file pattern to other apps (Waybar, Neovim, Betterbird).
