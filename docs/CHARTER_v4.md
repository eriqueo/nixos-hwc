# NixOS Configuration Charter v4 (Unified)

**Owner:** Eric
**Scope:** `/etc/nixos` — all machines, modules, profiles, and supporting files
**Goal:** A maintainable, predictable, scalable NixOS setup through strict domain separation, clean interfaces, and repeatable patterns.

## 1) Core Model

```
lib → modules → profiles → machines
```

* Layers depend only leftward (no cycles). Profiles orchestrate choices; modules implement; machines declare reality. 

## 2) Domains & Responsibilities

**Functional domain decides file location—never "where you found the code."** 

| Domain         | Purpose                          | Lives Under               | Must Contain                                     | Must Not Contain                   |
| -------------- | -------------------------------- | ------------------------- | ------------------------------------------------ | ---------------------------------- |
| Infrastructure | Hardware mgmt, drivers, power    | `modules/infrastructure/` | `hardware.*`, device control scripts, udev rules | UI, app services, user prefs       |
| System         | Core OS functions                | `modules/system/`         | networking, users, security, filesystem, boot    | hardware drivers, services, UI     |
| Services       | Application/daemon orchestration | `modules/services/`       | containers, web/db/media, daemons                | drivers, UI, core OS               |
| Home           | User environment (HM)            | `modules/home/`           | DE/WM (Hyprland), Waybar, shell/apps             | hardware control, system services  |
| Profiles       | Orchestration                    | `profiles/`               | imports + toggles; no implementation             | logic, service details             |
| Machines       | Hardware reality                 | `machines/<host>/`        | host overrides (paths, GPU type)                 | shared service logic               |

**Dependency direction:** profiles → (infrastructure | system | services | home). Modules never assume enablement; they react to toggles via `mkIf`. 

## 3) Folder Layout (canonical)

```
modules/
├─ infrastructure/      # gpu.nix, power.nix, bluetooth.nix, waybar-helpers.nix (hardware scripts)
├─ system/              # users.nix, networking.nix, paths.nix, security/*.nix
├─ services/
│  ├─ media/            # jellyfin.nix, immich.nix, *arr, downloaders
│  ├─ monitoring/       # prometheus.nix, grafana.nix
│  ├─ ai/               # ollama.nix, ai-bible.nix
│  └─ network/          # caddy.nix, vpn.nix
└─ home/
   ├─ waybar/           # default.nix, widgets/*.nix (UI config only)
   ├─ hyprland.nix
   └─ apps/*.nix
```

Nested, themed services are the standard. One service per file. 

## 4) Toggle & Interface Architecture

* **Modules** define `options.hwc.*` (capabilities). **Profiles** set toggles. **Machines** override for hardware reality. 
* Interfaces expose intent (e.g., `hwc.infrastructure.gpu.controls.toggle = true;`), not implementation details (script names/paths). 
* Modules implement under `config = mkIf cfg.enable { … }`. 

## 5) Home-Manager Boundary (uniform rule)

**In profiles:**

* Import HM once and list all HM modules under `home-manager.users.<user>.imports = [ … ]`. Do not import HM modules at NixOS top level.
* Pass NixOS facts down with `home-manager.extraSpecialArgs = { nixosConfig = config; };` so HM can read `nixosConfig.hwc.*` without defining system options.

This keeps UI in Home while system/hardware remains in NixOS, preserving dependency flow (profiles → home and profiles → infrastructure). 

## 6) Waybar Pattern (replicable to any HM UI)

**Goal:** keep *all* Waybar UI config in one place, but move *hardware logic* to Infrastructure.

* **Home (UI):** `modules/home/waybar/`

  * `default.nix` — Waybar settings/layout (only `programs.waybar.*`). Imports all tools.
  * `tools/*.nix` — small UI configuration tools (e.g., assembling `"custom/gpu"` block) that call binaries. **No `writeScriptBin`, no `nvidia-smi` here.**
* **Infrastructure (hardware scripts):** provide binaries like `waybar-gpu-status`, `waybar-gpu-toggle` via `environment.systemPackages`. Waybar simply invokes them. 

> Anti-pattern to avoid: hardware scripts (e.g., GPU toggle, brightnessctl, `nvidia-smi`) inside Waybar/HM. That violates functional purity and single-source rules. 

**🔑 Key Clarifications:**
- **Tools are simple**: No complex option systems. Tools just export waybar config blocks.
- **One place for waybar**: All waybar configuration stays in `modules/home/waybar/` for easy maintenance.
- **Infrastructure provides binaries**: Tools call `waybar-gpu-status`, infrastructure provides it via `environment.systemPackages`.

**Profile wiring example (workstation):**

```nix
# Enable infrastructure capabilities
hwc.infrastructure.waybarGpuTools.enable = true;
hwc.infrastructure.waybarSystemTools.enable = true;

# Enable UI that consumes them (simple import, no complex options)
home-manager.users.eric = {
  imports = [ ../modules/home/waybar/default.nix ];
};
```

This respects domain purity and correct dependency direction. 

## 7) File & Code Standards (Enforced)

### 7.1 Naming Conventions
* **Files**: `kebab-case.nix` (gpu-monitoring.nix, media-server.nix)
* **Options**: `camelCase` (`hwc.services.mediaServer.enable`)
* **Scripts**: `domain-purpose` (`gpu-toggle`, `waybar-gpu-status`)
* **Directories**: `kebab-case/` (ai-services/, not aiServices/)

### 7.2 Module File Structure (Required Template)
Every .nix file must follow this exact header and section format:

```nix
# nixos-hwc/modules/domain/service.nix
#
# SERVICE TITLE - Brief Purpose
# Detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.gpu.accel (modules/infrastructure/gpu.nix)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.services.service.enable)
#   - other modules that consume this capability
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/domain/service.nix
#
# USAGE:
#   hwc.services.service.enable = true;
#   hwc.services.service.option = "value";

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.domain.service;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.domain.service = {
    enable = lib.mkEnableOption "Service description";
    # ... specific options with descriptions
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured  
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Validation first
    assertions = [ ... ];
    
    # Core implementation
    # ... systemd, packages, etc.
  };
}
```

### 7.3 Section Headers (Required)
Use these exact comment blocks to structure all modules:
```nix
#============================================================================
# OPTIONS - What can be configured
#============================================================================

#============================================================================  
# IMPLEMENTATION - What actually gets configured
#============================================================================

#============================================================================
# VALIDATION - Assertions and checks
#============================================================================
```

## 8) Paths & Validation

* All service paths come from `config.hwc.paths.*`; validate nullable storage tiers and assert requirements up front. No hardcoded `/mnt/*` anywhere. 
* Add assertions for required paths/hardware (don't silently assume). 

## 9) Enforcement Rules (hard)

1. **Functional Purity:** each module contains only its domain's functionality. (E.g., GPU control scripts only in Infrastructure.) 
2. **Single Source of Truth:** one implementation location per capability. No duplicates across domains.
3. **Dependency Direction:** profiles enable; modules implement conditionally; modules don't hard-enable system features. 
4. **Interface Segregation:** expose high-level toggles; hide scripts/paths inside modules. 

## 10) Migration Method (Principles)

**Discovery → Classification → Relocation → Interface → Validation**

1. **Find violations**: `rg "writeScriptBin" modules/home/`
2. **Classify by function**: Hardware control → infrastructure/
3. **Move to correct domain**: Preserve functionality, change location  
4. **Create clean interfaces**: Export capabilities, not implementations
5. **Validate**: Build succeeds, no circular deps

**Success Metrics**: Zero cross-domain violations, single source per capability

## 11) Profiles & Machines (strict conduct)

* **Profiles:** import modules; set toggles; never embed logic or service details. Composable: `workstation + media + monitoring`. 
* **Machines:** only hardware facts & overrides (GPU type, storage tiers, hostnames); no shared logic. 

## 12) Charter Anti-Patterns (blockers)

* UI modules with hardware scripts (`writeScriptBin` + `nvidia-smi`) → must move to Infrastructure. 
* Hardware modules containing service orchestration (e.g., containers in `gpu.nix`) → must move to Services; GPU module should only expose container options to consume. 
* Machine-specific values hardcoded in shared modules → move to `machines/*`. 

## 13) Basic Validation

Simple commands to catch common violations:
* `rg "writeScriptBin" modules/home/` - hardware scripts in UI
* `rg "hardware\." modules/services/` - hardware config in services
* `rg "systemd\.services" modules/home/` - system services in UI
* `rg "/mnt/" modules/` - hardcoded paths

Basic validation script template (expand as needed):
```bash
#!/usr/bin/env bash
echo "Checking for cross-domain violations..."
violations=0

# Check for hardware scripts in home
if rg -q "writeScriptBin" modules/home/; then
  echo "❌ Hardware scripts found in modules/home/"
  violations=$((violations + 1))
fi

# Add more checks as needed
if [ $violations -eq 0 ]; then
  echo "✅ No violations found"
else
  echo "❌ Found $violations violations"
  exit 1
fi
```

## 14) Domain Communication Principles

* **Read-Only Exports**: Infrastructure exposes `config.hwc.infrastructure.gpu.accel = "cuda"` 
* **No Direct Calls**: Services read capabilities, never call hardware directly
* **Home-Manager Bridge**: `nixosConfig.hwc.*` provides read-only system state
* **Dependency Flow**: profiles → infrastructure → services → home (never reverse)

## 15) Profile Standards

* **Purpose**: Orchestration only - imports + toggles, zero implementation
* **Composition**: Must be additive (`base + workstation + media`)
* **Structure**: Group related imports, then group related toggles
* **Naming**: Capability-based (`workstation.nix`, `media-server.nix`)

### Profile Template:
```nix
# profiles/capability.nix - Brief description
{ lib, ... }: {
  imports = [
    # Infrastructure capabilities
    ../modules/infrastructure/gpu.nix
    # Services  
    ../modules/services/media/jellyfin.nix
    # Home environment (via HM)
  ];

  # Infrastructure toggles
  hwc.infrastructure.gpu.enable = true;
  
  # Service orchestration  
  hwc.services.mediaServer.enable = true;
  
  # Home-Manager activation
  home-manager.users.eric.imports = [
    ../modules/home/waybar/default.nix
  ];
}
```

---

## Appendix A — Service Pattern Standard

**Rule**: One service = one Home UI module + one Infrastructure tools module. No `modules/home/<service>/tools/` for executables; Home owns config files only.

**Structure**:
- **Home UI Module**: `modules/home/<service>/default.nix` - Complete UI configuration, calls canonical binaries
- **Infrastructure Tools Module**: `modules/infrastructure/<service>-tools.nix` - All hardware/system tools with canonical `<service>-*` naming
- **Profiles**: Import both modules, enable via `hwc.home.<service>.enable` and `hwc.infrastructure.<service>Tools.enable`

**Example (Waybar)**:
```nix
# modules/home/waybar/default.nix
programs.waybar.settings.mainBar."custom/gpu" = {
  exec = "waybar-gpu-status";           # canonical name
  on-click = "waybar-gpu-toggle";       # canonical name
};

# modules/infrastructure/waybar-hardware-tools.nix  
environment.systemPackages = [
  (writeShellScriptBin "waybar-gpu-status" ''...'')
  (writeShellScriptBin "waybar-gpu-toggle" ''...'')
];

# profiles/workstation.nix
hwc.infrastructure.waybarHardwareTools.enable = true;
home-manager.users.eric.imports = [ ../modules/home/waybar/default.nix ];
```

**Benefits**: Single source of truth per service, clean domain separation, predictable naming, easy maintenance.

---

## Appendix B — "Waybar Pack" (legacy reference)

**Goal:** all Waybar config in one obvious spot, with clean boundaries.

```
modules/home/waybar/
├── default.nix          # programs.waybar.*, imports tools/*.nix
└── tools/
    ├── gpu.nix          # builds "custom/gpu" block that calls binaries:
    └── net.nix          # builds "custom/net" block, etc.
```

Example tool (UI only):

```nix
# modules/home/waybar/tools/gpu.nix
{ lib, ... }: {
  # Simple waybar config block - no complex options needed
  programs.waybar.settings.mainBar."custom/gpu" = {
    format = "{}";
    exec = "waybar-gpu-status";    # provided by infrastructure
    on-click = "waybar-gpu-toggle";
    return-type = "json";
    interval = 5;
  };
}
```

**❌ Wrong Tool Pattern (overly complex):**
```nix
# DON'T DO THIS - tools should be simple
options.hwc.home.waybar.tools.gpu = {
  enable = lib.mkEnableOption "GPU tool";
  intervalSeconds = lib.mkOption { ... };
};
config = lib.mkIf cfg.enable { ... };
```

**✅ Right Tool Pattern (simple):**
```nix  
# DO THIS - just export waybar config
{ lib, ... }: {
  programs.waybar.settings.mainBar."custom/gpu" = { ... };
}
```

> The binaries (`waybar-gpu-status`, `waybar-gpu-toggle`) are exported by Infrastructure (e.g., `modules/infrastructure/waybar-gpu-tools.nix`) via `environment.systemPackages`. HM never ships hardware scripts.