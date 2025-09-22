
# HWC Architecture Charter

**Owner**: Eric
**Scope**: `nixos-hwc/` — all machines, modules, profiles, HM, and supporting files
**Goal**: Deterministic, maintainable, scalable, and reproducible NixOS via strict domain separation, explicit APIs, and predictable patterns.

---

## 0) Preserve-First Doctrine

* **Refactor = reorganize, not rewrite**.
* 100% feature parity during migrations.
* Wrappers/adapters allowed only as temporary bridges (tracked & removed).
* Never switch on red builds.

---

## 1) Core Layering & Flow

**NixOS system flow**
`flake.nix` → `machines/<host>/config.nix` → `profiles/*` → `modules/{system,infrastructure,server}/`

**Home Manager flow**
`machines/<host>/home.nix` → `modules/home/`

**Rules**

* Modules **implement** capabilities behind `options.nix`.
* Profiles **orchestrate imports & toggles only**.
* Machines **declare hardware facts** and activate HM.
* **No cycles**: dependency direction is always downward.
* Home Manager lives at machine level, not profile level.

---

## 2) Domains & Responsibilities

| Domain             | Purpose                          | Location                  | Must Contain                                                       | Must Not Contain                             |
| ------------------ | -------------------------------- | ------------------------- | ------------------------------------------------------------------ | -------------------------------------------- |
| **Infrastructure** | Hardware mgmt + system tools     | `modules/infrastructure/` | GPU, power, udev, virtualization, system binaries                  | HM configs                                   |
| **System**         | Core OS + accounts + OS services | `modules/system/`         | users, sudo, networking, security, secrets, paths, system packages | HM configs                                   |
| **Server**         | Host-provided workloads          | `modules/server/`         | containers, reverse proxy, databases, media stacks, monitoring     | HM configs                                   |
| **Home**           | User environment (HM)            | `modules/home/`           | `programs.*`, `home.*`, DE/WM configs, shells                      | systemd.services, environment.systemPackages |
| **Profiles**       | Orchestration                    | `profiles/`               | system imports, toggles                                            | HM activation (except hm.nix), implementation |
| **Machines**       | Hardware facts + HM activation   | `machines/<host>/`        | `config.nix`, `home.nix`, storage, GPU type                        | Shared logic, profile-like orchestration     |

**Key Principle**

* User accounts → `modules/system/users/eric.nix`
* User env → `modules/home/` imported by `machines/<host>/home.nix`

---

## 3) Unit Anatomy

Every **unit** (app, tool, or workload) MUST include:

* `index.nix` → aggregator, defines imports, always declares options.
* `options.nix` → mandatory, API definition (consumed by both `sys.nix` and `index.nix`).
* `sys.nix` → system-lane implementation, co-located but imported only by system profiles.
* `parts/**` → pure functions, no options, no side-effects.

**Rule**: `options.nix` always exists. Options are never defined ad hoc in `sys.nix` or `index.nix`.

---

## 4) Lane Purity

* **Lanes never import each other's `index.nix`**.
* Co-located `sys.nix` belongs to the **system lane**, even when inside `modules/home/apps/<unit>`.
* **Examples of valid sys.nix content**:
  - `modules/home/apps/kitty/sys.nix` → `environment.systemPackages = [ pkgs.kitty-themes ];`
  - `modules/home/apps/firefox/sys.nix` → `programs.firefox.policies = { ... };`
  - This is system-lane code imported by system profiles, **not HM boundary violations**.
* Profiles decide which lane's files to import.

---

## 5) Aggregators

* Aggregators are always named **`index.nix`**.
* Unit aggregators = `modules/home/apps/waybar/index.nix`.
* Domain aggregators = `modules/home/index.nix`, `modules/server/index.nix`.
* Profiles may import domain aggregators and unit indices.

---

## 6) Home Manager Boundary

* **HM activation is machine-specific, never in profiles.**
* **Exception**: `profiles/hm.nix` may contain HM activation as the single centralized HM profile
* Example (`machines/laptop/home.nix`):

```nix
{ config, pkgs, lib, ... }: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.eric = {
      imports = [
        ../../modules/home/apps/hyprland
        ../../modules/home/apps/waybar
        ../../modules/home/apps/kitty
      ];
      home.stateVersion = "24.05";
    };
  };
}
```

---

## 7) Structural Rules

* **Structural files** = all `.nix` sources under `modules/`, `profiles/`, `machines/` and `flake.{nix,lock}`.
* Never apply automated regex rewrites to structural files.
* Generated artifacts (systemd units, container manifests) are not structural.

---

## 8) Theming

* Palettes (`modules/home/theme/palettes/*.nix`) define tokens.
* Adapters (`modules/home/theme/adapters/*.nix`) transform palettes to app configs.
* No hardcoded colors in app configs.

---

## 9) Helpers & Parts

* `parts/**` and `_shared/**` MUST be pure helpers:

  * No options
  * No side effects
  * No direct system mutation

---

## 10) File Standards

* Files/dirs: `kebab-case.nix`
* Options: camelCase (e.g. `hwc.system.users.enable`)
* Scripts: `domain-purpose` (e.g. `waybar-gpu-status`)
* All modules include: **OPTIONS / IMPLEMENTATION / VALIDATION** sections

---

## 11) Enforcement Rules

* Functional purity per domain.
* Single source of truth.
* No multiple writers to same path.
* Profiles orchestrate only, machines declare only.

---

## 12) Validation & Anti-Patterns

**Searches (must be empty):**

```bash
rg "writeScriptBin" modules/home/
rg "systemd\.services" modules/home/
rg "environment\.systemPackages" modules/home/
rg "home-manager" profiles/ --exclude profiles/hm.nix
rg "/mnt/" modules/
```

**Hard blockers**

* HM activation in profiles (except profiles/hm.nix)
* NixOS modules in HM
* HM modules in system/server
* User creation outside `modules/system/users/`
* Mixed-domain modules (e.g., `users.users` + `programs.zsh`)

---

## 13) Server Workloads

* Reverse proxy authority is central in `server/containers/caddy/`.
* When host-level Caddy aggregator is enabled, containerized proxy units MUST be disabled.
* Per-unit container state defaults to `/opt/<category>/<unit>:/config`. Override only for ephemeral workloads, host storage policy, or multiple instances.

---

## 14) Profiles & Import Order

* Profiles MUST import `options.nix` before any lane implementations.
* Example:

```nix
imports = [
  ../modules/system/index.nix
  ../modules/server/index.nix
] ++ (gatherSys ../modules/home/apps);
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
* Phase 2 (Module standardization): 🔄 in progress.
* Phase 3 (Validation & optimization): ⏳ pending.

---

## 17) Charter Change Management

* Version bump on any normative change.
* PRs require non-author review.
* Linter (`tools/hwc-lint.sh`) updated in same PR.
* Include “Impact & Migration” notes for breaking changes.

---

