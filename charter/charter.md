# CHARTER v7 — Structure, Naming, and Scopes (HM + System)

> **Purpose**  
> One mental model for *both* Home‑Manager (HM) and System scopes that’s explicit, greppable, and hard to mess up. This charter standardizes **names**, **locations**, **imports**, and **debug lanes** so changes are drop‑in and traceable.

---

## 0) Big picture (read me first)

- **Two profiles = two lanes**
  - `profiles/hm.nix` → HM/user scope only
  - `profiles/sys.nix` → System scope only
- **Auto‑aggregation everywhere** with `index.nix` so new units are “drop in”
- **Co‑location**: if a system bit exists *because* of a unit, it lives next to that unit in `sys.nix`
- **Platform‑wide** system stays under `modules/system/*`
- **Shared plumbing** (virtualization, container networking, hardening) stays under `modules/infrastructure/*`
- **Theme pipeline**: One palette → many adapters → apps consume tokens. (Matches our existing README.)

---

## 1) Roles & vocabulary (function over domain)

- **Unit**: a feature directory you can enable/disable as a whole (e.g., `modules/home/apps/waybar/` or `modules/services/jellyfin/`).
- **Namespace**: a top‑level subtree under `modules/` — `home/`, `system/`, `infrastructure/`, `services/`.
- **Profile**: a top‑level collector a machine imports (our “lanes”).

---

## 2) Standard file names (applies to units *and* namespaces)

| File             | Role (what it does) | Notes |
|---               |---                   |---|
| `index.nix`      | **Public entry** & auto‑aggregator | Always the file a parent imports. |
| `sys.nix`        | **Unit‑scoped system add‑ons**     | systemd user/root units, udev, groups, firewall, `environment.systemPackages` required *by this unit*. |
| `options.nix`    | **Typed knobs & defaults**         | Your `features.<unit>.*` (bools, ints, enums, strings). |
| `parts/`         | **Leaf impls**                     | `pkgs.nix`, `ui.nix`, `behavior.nix`, `session.nix`, `scripts.nix`. Keep small and focused. |

**Scope rules**
- If it configures the **user**, it goes in `index.nix` / `parts/*` (HM lane).
- If it configures the **system because this unit exists**, it goes in `sys.nix` next to that unit.
- If it configures the **platform regardless of units**, it belongs under `modules/system/*`.

---

## 3) Canonical directory layout

```
modules/
  home/
    index.nix                 # aggregates apps/, environment/, core/, theme/
    apps/
      index.nix               # auto-imports *.nix and */index.nix
      kitty.nix               # simple single-file unit
      alacritty.nix
      waybar/
        index.nix
        options.nix
        sys.nix               # unit-scoped system helpers (only if needed)
        parts/{pkgs.nix,ui.nix,behavior.nix,session.nix,scripts.nix}
      hyprland/
        index.nix
        options.nix
        sys.nix
        parts/...
    environment/
      index.nix
      development.nix         # HM tool bundles (fd, rg, jq, etc.)
      productivity.nix
      shell.nix
    core/
      index.nix               # HM glue (input, login manager, etc.)
      input.nix
      login-manager.nix
    theme/
      index.nix               # adapters + palette tokens exposed to apps
      options.nix
      parts/
        adapters/{gtk.nix,waybar-css.nix,hyprland.nix}
        palettes/{deep-nord.nix,gruv.nix}

  system/
    index.nix                 # platform-wide system scope
    filesystem.nix
    networking.nix
    printing.nix
    paths.nix
    secrets.nix
    security/sudo.nix
    users/*.nix
    gpu/*

  infrastructure/
    index.nix                 # cross-cutting plumbing for many units
    virtualization.nix
    container-networking.nix
    hardening.nix
    # If a sub-item here needs host system bits, co-locate a sibling sys.nix

  services/
    # later; each service should be its own unit folder
    name/
      index.nix
      sys.nix
      parts/...
```

**Mental model**  
- **Unit‑scoped system** → `that-unit/sys.nix`.  
- **Platform‑wide system** → `modules/system/*`.  
- **Shared plumbing** → `modules/infrastructure/*`.

---

## 4) Profiles = lanes (debug starting points)

- `profiles/hm.nix` imports **only** HM aggregators (usually just `modules/home/index.nix`).
- `profiles/sys.nix` imports **platform system first** (`modules/system/index.nix`), then **unit `sys.nix`** discovered under `modules/home/apps`, `modules/services`, `modules/infrastructure`.

> If `environment.systemPackages`/systemd is acting up, start at `profiles/sys.nix`.  
> If per‑user configs misbehave, start at `profiles/hm.nix`.

**Ordering rule**: platform‑wide system first, then unit `sys.nix` so unit overrides can win.

---

## 5) Auto‑aggregation snippets (copy/paste)

### Flat folder mixing `*.nix` and `*/index.nix`
```nix
{ lib, ... }:
let
  dir   = builtins.readDir ./.;
  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "index.nix") dir;
  subds = lib.filterAttrs (_: t: t == "directory") dir;

  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
  subIndex  =
    lib.pipe (lib.attrNames subds) [
      (ns: lib.filter (n: builtins.pathExists (./. + "/${n}/index.nix")) ns)
      (ns: lib.map (n: ./. + "/${n}/index.nix") ns)
    ];
in { imports = filePaths ++ subIndex; }
```

### Gather `sys.nix` from child dirs (used in `profiles/sys.nix`)
```nix
let gatherSys = dirPath:
  let
    entries = builtins.readDir dirPath;
    subdirs = lib.attrNames (lib.filterAttrs (_: t: t == "directory") entries);
  in lib.filter builtins.pathExists (map (n: dirPath + "/${n}/sys.nix") subdirs);
in
{
  imports =
    [ ../modules/system/index.nix ]  # platform system first
    ++ (gatherSys ../modules/home/apps)
    ++ (gatherSys ../modules/services)
    ++ (gatherSys ../modules/infrastructure);
}
```

---

## 6) Options & overrides (consistent API)

- All unit options live under **`features.<unit>.*`**. Examples:
  - `features.waybar.enable`, `features.waybar.fontSize`, `features.hyprland.enable`
- Profiles can set *defaults* via `lib.mkDefault` so machines can override.
- Machines can override any `features.*` or `theme.*` value directly.

**Do not** hard‑enable heavy features in profiles with `=` unless the profile *is* that feature.

---

## 7) Theme pipeline (how to switch or tweak)

**Where things live**
- Palette tokens: `modules/home/theme/parts/palettes/*.nix`
- Adapters: `modules/home/theme/parts/adapters/*.nix` (GTK, Waybar CSS, Hyprland, etc.)
- App consumption: each app’s `parts/ui.nix` reads tokens and renders settings/CSS.

**Switch theme globally**
1. Set palette in `modules/home/theme/options.nix` default (or per‑machine override `theme.palette = "deep-nord";`).  
2. Rebuild. All adapters and apps update together.

**Change Waybar font size**
- Set `features.waybar.fontSize` per machine (e.g., in `machines/laptop/config.nix`).
- `modules/home/apps/waybar/parts/ui.nix` must read that option and set both `settings` and `style` accordingly.

> The “one palette → adapters → apps” flow is our source of truth and matches the existing README semantics.  

---

## 8) Where to add/tweak things (practical recipes)

### A) Add a simple HM app (e.g., Alacritty)
1) Create `modules/home/apps/alacritty.nix`:
```nix
{ ... }: {
  programs.alacritty = {
    enable = true;
    settings.window.opacity = 0.96;
  };
}
```
2) Done. `apps/index.nix` auto‑imports it; `profiles/hm.nix` already imports `modules/home/index.nix`.

### B) Add an HM unit with options + system helpers (e.g., Waybar)
```
modules/home/apps/waybar/
  index.nix
  options.nix
  sys.nix           # only if waybar needs host packages/services
  parts/{pkgs.nix,ui.nix,behavior.nix,session.nix,scripts.nix}
```
- `index.nix` imports `options.nix` + `parts/*`.
- `sys.nix` adds `environment.systemPackages`, user services, udev, etc., *required by Waybar*.
- Everything is auto‑picked by `apps/index.nix` (HM) and `profiles/sys.nix` (system).

### C) Add a platform‑wide system feature (e.g., Printing)
1) Edit/create `modules/system/printing.nix`.  
2) Done. `modules/system/index.nix` and `profiles/sys.nix` pick it up.

### D) Add a dev tool for *your user* (fd, rg, jq)
- Put it in `modules/home/environment/development.nix` under `home.packages`.  
- Avoid duplicating the same tool in `environment.systemPackages` unless a systemd unit requires it.

### E) Toggle features per machine
`machines/imac/config.nix`:
```nix
{
  imports = [
    ./hardware.nix
    ../../profiles/hm.nix
    ../../profiles/sys.nix
  ];

  features = {
    hyprland.enable = false;     # lighter hardware
    waybar = {
      enable  = true;
      battery = false;
      sensors = false;
      fontSize = 10;
    };
  };

  theme.palette = "deep-nord";
}
```

### F) Where to debug
- HM issues → open `profiles/hm.nix` → follow to relevant unit’s `index.nix`.
- System issues (`environment.systemPackages`, systemd) → open `profiles/sys.nix` → either platform `modules/system/*` or the unit’s `sys.nix`.

---

## 9) Guardrails (lint yourself before you wreck yourself)

- **No dual install**: a tool must be in either `home.packages` (user) **or** `environment.systemPackages` (system), not both.
- **Profiles never import leaves**: profiles import only `index.nix` or `sys.nix`, never `parts/*`.
- **Networking split**: host networking in `modules/system/networking.nix`; container bridges in `modules/infrastructure/container-networking.nix`.
- **GPU split**: host stack in `modules/system/gpu/*`; container runtime tweaks in `infrastructure/*` or in a specific service’s unit if truly specific.

**Quick checks (ripgrep)**  
```sh
rg -n "sys\.nix" profiles/hm.nix                          # should be empty
rg -n "modules/home/.+/(parts|ui\.nix|behavior\.nix)" profiles  # should be empty
# Compare dual-scope packages:
rg -n "home\.packages" modules | cut -d: -f1 | sort -u
rg -n "environment\.systemPackages" modules | cut -d: -f1 | sort -u
```

---

## 10) Implementation plan (safe migration, minimal churn)

1) **Add aggregators**  
   - `modules/home/index.nix` (imports `apps/`, `environment/`, `core/`, `theme/`)  
   - `modules/home/apps/index.nix` (auto‑imports `*.nix` and `*/index.nix`)  
   - `modules/system/index.nix` (aggregate platform files + subdir `index.nix`)
2) **Create two profiles**  
   - `profiles/hm.nix` → imports `modules/home/index.nix` only  
   - `profiles/sys.nix` → imports `modules/system/index.nix` and gathers `*/sys.nix` from `modules/home/apps`, `modules/infrastructure`, and `modules/services`
3) **Move a few files for clarity** (do in small commits)  
   - `infrastructure/gpu.nix` → `system/gpu/*.nix` (host GPU)  
   - `infrastructure/networking.nix` → merge into `system/networking.nix` (host)  
   - `infrastructure/printing.nix` → `system/printing.nix`  
   - `infrastructure/user-hardware-access.nix` → `system/user-hardware-access.nix`  
   - Remove `infrastructure/waybar-hardware-tools.nix` (superseded by `apps/waybar/sys.nix`)
4) **Smoke test** (build‑only)  
   ```sh
   sudo nixos-rebuild build --flake .#laptop
   ```
5) **Switch** (host by host)  
   ```sh
   sudo nixos-rebuild switch --flake .#laptop
   ```
6) **Lock in**: add the ripgrep lints to `operations/validation/` and run before PRs/commits.

---

## 11) Theme note (source of truth)

This charter intentionally matches our existing theme README: one palette drives adapters (GTK, Waybar, Hyprland) which feed apps. Change a palette once, rebuild, everything follows.
