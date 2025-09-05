NixOS Configuration Charter v6 (Unified, System.nix Era)

Owner: Eric
Scope: nixos-hwc/ — all machines, modules, profiles, HM, and supporting files
Goal: Maintainable, predictable, scalable, and reproducible NixOS through strict domain separation, repeatable patterns, and feature-preserving migration.

0) Preserve-First Doctrine

Refactor = reorganize, not rewrite.

100% feature parity during migrations.

Wrappers/adapters allowed only as temporary bridges (tracked and removed later).

Never switch on red builds.

1) Core Layering
lib → modules → profiles → machines


Modules implement capabilities behind options.

Profiles orchestrate imports/toggles only.

Machines describe hardware reality/deltas.

Strict leftward dependency (no cycles).

2) Domains & Responsibilities
Domain	Purpose	Location	Must Contain	Must Not Contain
Infrastructure	Hardware mgmt + system-wide tools	modules/infrastructure/	GPU, power, udev, kernel toggles, binaries for UI	UI configs, HM files
System	Core OS functions + auth/safety	modules/system/	users, sudo, networking, security, secrets, paths	hardware drivers, UI configs
Services	Daemons & orchestration	modules/services/	containers, media/db/web stacks, monitoring	hardware, UI configs
Home	User environment (HM)	modules/home/	WM/DE configs, apps, shell, parts/adapters, UI tools	systemd services, hardware drivers
Profiles	Orchestration layer	profiles/	imports + toggles, no logic	implementation details
Machines	Hardware facts	machines/<host>/	GPU type, storage tiers, overrides	shared logic
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

In profiles only:

home-manager = {
  useGlobalPkgs = true;
  backupFileExtension = "hm-bak";
  extraSpecialArgs = { nixosConfig = config; };
  users.eric.imports = [ ../modules/home/hyprland/default.nix ];
};


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

rg "writeScriptBin" modules/home/ → must be empty.

rg "systemd\.services" modules/home/ → must be empty.

rg "/mnt/" modules/ → must be empty.

Hard blockers:

Executables in modules/home/** (must move to Infrastructure).

Profiles with logic.

Old ghost configs (e.g. app-launcher).

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

Phase 1 (v4 compliance) nearly complete.

Phase 2 (Domain cleanup) begins once modules/home/eric.nix hardware refs are moved.

Phase 3 = validation + retrospective.

✅ This v6 is forward-compatible: you can use it for Hyprland now, then apply the same 5-file pattern to other apps (Waybar, Neovim, Betterbird).
