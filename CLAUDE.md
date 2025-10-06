
# HWC Architecture Charter

**Owner**: Eric
**Scope**: `nixos-hwc/` — all machines, domains, profiles, HM, and supporting files
**Goal**: Deterministic, maintainable, scalable, and reproducible NixOS via strict domain separation, explicit APIs, predictable patterns, and user-centric organization.

---

## 0) Preserve-First Doctrine

* **Refactor = reorganize, not rewrite**.
* 100% feature parity during migrations.
* Wrappers/adapters allowed only as temporary bridges (tracked & removed).
* Never switch on red builds.

---

## 1) Core Architectural Concepts

### **Domains**
- **Definition**: A folder of modules organized around a common interaction boundary (how they talk to the system), where each module handles one logical concern and follows the namespace pattern of its folder path
- **Purpose**: Clear separation of concerns based on system interaction boundaries
- **Location**: `domains/` folder
- **Namespace Rule**: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`
- **Debugging**: Direct folder-to-namespace mapping for immediate error traceability

### **Modules**
- **Definition**: A single logical concern that provides one place to configure all aspects of that concern
- **Purpose**: "One place per concern" - all hyprland config, all user config, etc. lives in one logical location
- **Example**: `domains/home/apps/firefox/` contains everything firefox-related

### **Profiles**
- **Definition**: Domain-specific feature menus that aggregate modules to serve machine composition purposes
- **Structure**: Two clear sections per profile:
  - **BASE**: Required imports/options for domain functionality (won't boot/breaks without)
  - **OPTIONAL FEATURES**: Sensible defaults that can be overridden per machine
- **Types**: `system.nix`, `home.nix`, `infrastructure.nix`, `server.nix`
- **Machine Composition**: Machines import combination of domain profiles needed

### **Profile Pattern**
Each domain profile follows this structure:
```nix
# profiles/system.nix
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality  
  #==========================================================================
  # Essential imports, users, permissions, secrets, networking
  
  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  # Development tools, media packages, security levels, etc.
}
```

**Base Determination**: Anything required for basic machine operation - boot, management, permissions, authentication.

---

## 2) Core Layering & Flow

**NixOS system flow**
`flake.nix` → `machines/<host>/config.nix` → `profiles/*` → `domains/{system,infrastructure,server}/`

**Home Manager flow**
`machines/<host>/home.nix` → `domains/home/`

**Machine Composition Flow**
```
profiles/system.nix → domains/system/*
profiles/home.nix → domains/home/*
profiles/infrastructure.nix → domains/infrastructure/*
profiles/server.nix → domains/server/*
         ↓
machines/laptop/config.nix imports needed profiles
```

**Rules**

* Modules **implement** capabilities behind `options.nix`.
* Profiles **provide domain feature menus with base/optional structure**.
* Machines **declare hardware facts and import needed domain profiles**.
* **No cycles**: dependency direction is always downward.
* Home Manager lives at machine level, not profile level.

---

## 3) Domain Boundaries & Responsibilities

| Domain             | Purpose                          | Location                  | Must Contain                                                       | Must Not Contain                             |
| ------------------ | -------------------------------- | ------------------------- | ------------------------------------------------------------------ | -------------------------------------------- |
| **Infrastructure** | Hardware mgmt + cross-domain orchestration | `domains/infrastructure/` | GPU, power, udev, virtualization, filesystem structure             | HM configs                                   |
| **System**         | Core OS + accounts + OS services | `domains/system/`         | users, sudo, networking, security, secrets, paths, system packages | HM configs                                   |
| **Server**         | Host-provided workloads          | `domains/server/`         | containers, reverse proxy, databases, media stacks, monitoring     | HM configs                                   |
| **Home**           | User environment (HM)            | `domains/home/`           | `programs.*`, `home.*`, DE/WM configs, shells                      | systemd.services, environment.systemPackages |
| **Profiles**       | Domain feature menus             | `profiles/`               | domain imports, base/optional toggles                              | HM activation (except hm.nix), implementation |
| **Machines**       | Hardware facts + profile composition | `machines/<host>/`        | `config.nix`, `home.nix`, storage, GPU type                        | Shared logic, profile-like orchestration     |

**Key Principles**

* User accounts → `domains/system/users/eric.nix`
* User env → `domains/home/` imported by `machines/<host>/home.nix`
* Cross-domain orchestrators → `domains/infrastructure/` (filesystem structure, etc.)
* Namespace follows folder structure: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`

---

## 4) Unit Anatomy

Every **module** (app, tool, or workload) MUST include:

* `index.nix` → aggregator, imports options.nix, implements functionality
* `options.nix` → mandatory, API definition following folder→namespace pattern
* `sys.nix` → system-lane implementation, co-located but imported only by system profiles
* `parts/**` → pure functions, no options, no side-effects

**Rules**
* `options.nix` always exists - options never defined ad hoc in other files
* Namespace matches folder structure: `domains/home/apps/firefox/options.nix` defines `hwc.home.apps.firefox.*`
* One logical concern per module directory

---

## 5) Lane Purity

* **Lanes never import each other's `index.nix`**.
* Co-located `sys.nix` belongs to the **system lane**, even when inside `domains/home/apps/<unit>`.
* **Examples of valid sys.nix content**:
  - `domains/home/apps/kitty/sys.nix` → `environment.systemPackages = [ pkgs.kitty-themes ];`
  - `domains/home/apps/firefox/sys.nix` → `programs.firefox.policies = { ... };`
  - This is system-lane code imported by system profiles, **not HM boundary violations**.
* Profiles decide which lane's files to import.

---

## 6) Aggregators

* Aggregators are always named **`index.nix`**.
* Module aggregators = `domains/home/apps/waybar/index.nix`.
* Domain aggregators = `domains/home/index.nix`, `domains/server/index.nix`.
* Profiles may import domain aggregators and individual module indices.

---

## 7) Home Manager Boundary

* **HM activation is machine-specific, never in profiles.**
* **Exception**: `profiles/home.nix` serves as the Home Manager domain feature menu
* Example (`machines/laptop/home.nix`):

```nix
{ config, pkgs, lib, ... }: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.eric = {
      imports = [
        ../../domains/home/apps/hyprland
        ../../domains/home/apps/waybar
        ../../domains/home/apps/kitty
      ];
      home.stateVersion = "24.05";
    };
  };
}
```

---

## 8) Structural Rules

* **Structural files** = all `.nix` sources under `domains/`, `profiles/`, `machines/` and `flake.{nix,lock}`.
* Never apply automated regex rewrites to structural files.
* Generated artifacts (systemd units, container manifests) are not structural.

---

## 9) Theming

* Palettes (`domains/home/theme/palettes/*.nix`) define tokens.
* Adapters (`domains/home/theme/adapters/*.nix`) transform palettes to app configs.
* No hardcoded colors in app configs.

---

## 10) Helpers & Parts

* `parts/**` and `_shared/**` MUST be pure helpers:

  * No options
  * No side effects
  * No direct system mutation

---

## 11) File Standards

* Files/dirs: `kebab-case.nix`
* Options: camelCase following folder structure (e.g. `hwc.home.apps.firefox.enable`)
* Scripts: `domain-purpose` (e.g. `waybar-gpu-status`)
* All modules include: **OPTIONS / IMPLEMENTATION / VALIDATION** sections
* Namespace matches folder: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`

---

## 12) Enforcement Rules

* Functional purity per domain.
* Single source of truth.
* No multiple writers to same path.
* Profiles provide feature menus, machines compose profiles.
* One logical concern per module directory.
* Namespace follows folder structure for debugging.

---

## 13) Validation & Anti-Patterns

**Searches (must be empty):**

```bash
rg "writeScriptBin" domains/home/
rg "systemd\.services" domains/home/
rg "environment\.systemPackages" domains/home/
rg "home-manager" profiles/ --exclude profiles/home.nix
rg "/mnt/" domains/
```

**Hard blockers**

* HM activation in profiles (except profiles/home.nix domain menu)
* NixOS modules in HM
* HM modules in system/server
* User creation outside `domains/system/users/`
* Mixed-domain modules (e.g., `users.users` + `programs.zsh`)
* Options defined outside `options.nix` files
* Namespace not matching folder structure

---

## 13) Server Workloads

* Reverse proxy authority is central in `domains/server/containers/caddy/`.
* When host-level Caddy aggregator is enabled, containerized proxy units MUST be disabled.
* Per-unit container state defaults to `/opt/<category>/<unit>:/config`. Override only for ephemeral workloads, host storage policy, or multiple instances.

---

## 14) Profiles & Import Order

* Profiles MUST import `options.nix` before any lane implementations.
* Example:

```nix
imports = [
  ../domains/system/index.nix
  ../domains/server/index.nix
] ++ (gatherSys ../domains/home/apps);
```

---

## 15) Migration Protocol

1. **Discovery** → list features.
2. **Classification** → Part / Adapter / Tool.
3. **Relocation** → Parts & adapters → Home, Tools → Infra.
4. **Interface** → canonical tool names only.
5. **Validation** → build-only → smoke → switch.

---

## 16) Status

* Phase 1 (Domain separation): ✅ complete.
* Phase 2 (Domain/Profile architecture): 🔄 in progress.
* Phase 3 (Namespace alignment): ⏳ pending.
* Phase 4 (Validation & optimization): ⏳ pending.

---

## 17) Charter Change Management

* Version bump on any normative change.
* PRs require non-author review.
* Linter (`tools/hwc-lint.sh`) updated in same PR.
* Include "Impact & Migration" notes for breaking changes.

---

## 18) Configuration Validity & Dependency Assertions

* **Mandatory Validation Section**: Every `index.nix` with `enable` toggle MUST include `# VALIDATION` section after `# IMPLEMENTATION`.
* **Assertion Requirement**: Modules MUST assert all runtime dependencies (system services, binaries, configuration reads).
* **Assertion Template**: `{ assertion = !enabled || config.hwc.dep.enable; message = "X requires Y"; }`
* **Sub-Toggle Policy**: Sub-toggles default to master state unless overridden. Dependents assert specific sub-toggle, not master.
* **Linting**: Charter linter verifies assertion presence and cross-domain dependency coverage.
* **Fail-Fast Principle**: Invalid configurations MUST fail at build time, never at runtime.
* **Examples**: See `domains/home/apps/waybar/index.nix`, `domains/home/apps/hyprland/index.nix` for reference patterns.

---

**Charter Version**: v6.0 - Configuration Validity & Dependency Assertions

---

