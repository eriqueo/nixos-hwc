Got it. Here’s a single, crystal-clear Charter v5 that folds in v4 and the updates we agreed on (parts-based UI, global theming, auth safety, .zshenv ownership, refactor rules). It’s written to be unambiguous and immediately actionable.

# NixOS Configuration Charter v5 (Unified, Preserve-First)

Owner: Eric
Scope: `nixos-hwc/` for all machines, modules, profiles, HM, and supporting files
Goal: Preserve a working system while moving to a maintainable, predictable, scalable layout. No functionality loss during refactors—ever. (v4 basis + v5 clarifications.)&#x20;

---

## 0) Preserve-First Doctrine (non-negotiable)

**Refactor means reorganize, not rewrite.**

* 100% feature preservation from the working source (old `/etc/nixos` or monoliths).
* Naming that UIs call must not drift unless adapters/wrappers are provided and later removed on a scheduled cleanup step.
* We migrate in **small PRs with explicit parity checks** before any `switch`.

**Success is measured by:**

* System builds in **build-only** mode.
* Parity checks pass (bindings, tools, bars, services).
* Only then we `switch`. Rollback available.

---

## 1) Layering Model (unchanged)

```
lib → modules → profiles → machines
```

* **Modules** implement capabilities, hidden behind options.
* **Profiles** orchestrate imports + toggles only (no logic).
* **Machines** describe hardware reality + deltas (no shared logic).

Dependency direction is strictly leftward.

---

## 2) Domains & Responsibilities (tightened)

| Domain             | Purpose                      | Lives Under               | Must Contain                                                                  | Must Not Contain                               |
| ------------------ | ---------------------------- | ------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------- |
| **Infrastructure** | Hardware + low-level control | `modules/infrastructure/` | device helpers, udev, kernel toggles, **executable tools** (`writeScriptBin`) | UI config, HM files                            |
| **System**         | Core OS                      | `modules/system/`         | users, security, networking, filesystem, boot, **sudo policy**, **agenix**    | hardware drivers, UI                           |
| **Services**       | Daemons/containers           | `modules/services/`       | service orchestration, timers                                                 | drivers, HM UI, hardware scripts               |
| **Home**           | User environment (HM)        | `modules/home/`           | Hyprland, Waybar, shell/apps configuration, **UI “parts”**                    | **No executables**, no systemd system services |

Hard rule: **Executables live only in Infrastructure.** Home is pure configuration.

---

## 3) Naming & File Standards

* Files/dirs: `kebab-case.nix` (e.g., `hyprland-tools.nix`), directories `kebab-case/`.
* Options: `camelCase` under a namespaced tree (e.g., `hwc.system.users.enable`).
* Executables: `service-purpose` (e.g., `waybar-gpu-status`, `hyprland-workspace-overview`).
* One service = one module file per domain.

**Module template (required):**

```nix
# nixos-hwc/modules/<domain>/<name>.nix
{ config, lib, pkgs, ... }:
let cfg = config.hwc.<domain>.<name>;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.<domain>.<name> = {
    enable = lib.mkEnableOption "…";
    # …
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    assertions = [ /* … */ ];
    # implementation…
  };
}
```

---

## 4) Home-Manager Boundary & File Ownership

* HM is imported **once** in profiles:

  ```nix
  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = { nixosConfig = config; };
    users.eric.imports = [ /* home modules here */ ];
    backupFileExtension = "hm-bak";  # required
  };
  ```
* **.zshenv ownership:** HM owns it. Content must be **guarded**:

  ```nix
  home.file.".zshenv".text = ''
    HM_VARS="/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
    [ -r "$HM_VARS" ] && . "$HM_VARS"
  '';
  ```
* Exactly **one writer per path**. If HM manages `~/.zshenv`, nothing else does.

---

## 5) Users & Auth Safety (new in v5)

* **All user accounts and sudo** live in **System** domain (`modules/system/users.nix`, `modules/system/security/sudo.nix`).
* **Agenix integration** and service ordering live in **System** (`modules/system/secrets.nix`).
* **Emergency access** is a **machine-level** toggle for migrations only:

  ```nix
  # machines/<host>/config.nix
  hwc.system.users.emergencyEnable = true;  # disable after validation
  ```
* `users.mutableUsers = false` by default.
* Assertions prevent lockout (secret must exist OR emergency enabled).

---

## 6) Parts/Adapters/Tools Pattern (clarified vocabulary)

* **Parts** (Home/UI): pure Nix fragments of UI configuration. No execs.
* **Adapters** (Home/UI): transform **global palette** → app-specific settings (e.g., CSS vars, Hyprland colors). No execs.
* **Tools** (Infrastructure): **executable** helpers the UI calls (canonical names).

This vocabulary prevents domain confusion.

---

## 7) Global Theming (new, standardized)

**Goal:** universal palette → adapters → apps.

```
modules/home/theme/
├─ palettes/
│  └─ deep-nord.nix        # pure tokens (bg, fg, warn, crit, accent, …)
└─ adapters/
   ├─ waybar-css.nix       # palette → CSS :root vars + base styles
   └─ hyprland.nix         # palette → hyprland settings (colors/decoration)
```

Example usage in Waybar:

```nix
# modules/home/waybar/theme-deep-nord.nix
{ }:
let palette = import ../theme/palettes/deep-nord.nix {};
in  import ../theme/adapters/waybar-css.nix { inherit palette; }
```

Adapters are **UI-only**; they never shell out.

---

## 8) Waybar (v5 pattern)

**Home (UI)**

```
modules/home/waybar/
├─ default.nix       # programs.waybar.*; composes parts/*.nix and theme
└─ parts/
   ├─ gpu.nix        # creates "custom/gpu" block → exec = "waybar-gpu-status"
   ├─ net.nix        # … other blocks …
   └─ layout.nix     # bar layout / modules order
```

* Parts are **just Nix attrsets** that extend `programs.waybar.settings.*`.
* **No `writeScriptBin`** in Home.
* **Theme** is pulled via adapter (CSS vars).

**Infrastructure (Tools)**

```
modules/infrastructure/waybar-hardware-tools.nix
```

* Ships **executables** with **canonical names** (`waybar-…`) via `environment.systemPackages`.

**Transitional wrappers:** allowed only during migration, tracked, and removed in a scheduled “Wrapper Cleanup” PR.

---

## 9) Hyprland (v5 pattern)

**Home (UI)**

```
modules/home/hyprland/
├─ default.nix         # single entry, merges all parts into settings
└─ parts/
   ├─ keybindings.nix  # all keybinds (pure data)
   ├─ monitors.nix     # outputs + workspace assignment
   ├─ windowrules.nix  # windowrulev2 list
   ├─ input.nix        # touchpad/keyboard
   ├─ autostart.nix    # exec-once (calls canonical tools if needed)
   └─ theming.nix      # imports theme adapter for colors/decoration
```

**Infrastructure (Tools)**

```
modules/infrastructure/hyprland-tools.nix
```

* Ships **canonical** executables (`hyprland-workspace-overview`, `hyprland-monitor-toggle`, …).
* Provides **systemd user units** using correct HM/NixOS schema:

  ```nix
  systemd.user.services.hyprland-system-health-checker = {
    description = "System health monitoring service";
    wantedBy    = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "…" ''exec /run/current-system/sw/bin/hyprland-system-health-checker''}";
    };
  };
  systemd.user.timers.hyprland-system-health-checker = {
    description = "Run system health checker every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*:0/10"; Persistent = true; };
  };
  ```

---

## 10) Profiles & Wiring (strict)

Example (workstation):

```nix
# profiles/workstation.nix
{
  imports = [
    ../modules/infrastructure/gpu.nix
    ../modules/infrastructure/waybar-hardware-tools.nix
    ../modules/infrastructure/hyprland-tools.nix
    ../modules/system/users.nix
    ../modules/system/security/sudo.nix
    ../modules/system/secrets.nix
  ];

  # Infrastructure toggles
  hwc.infrastructure.waybarHardwareTools.enable = true;
  hwc.infrastructure.hyprlandTools.enable       = true;

  # System toggles
  hwc.system.users = {
    enable = true;
    user = "eric";
    passwordSecret = "user-initial-password";
    emergencyEnable = false; # machine can override to true if needed
  };
  hwc.system.security.sudo = { enable = true; wheelNeedsPassword = false; };
  hwc.system.secrets       = { enable = true; ensureSecretsExist = true; };

  # Home-Manager
  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-bak";
    extraSpecialArgs = { nixosConfig = config; };
    users.eric.imports = [
      ../modules/home/waybar/default.nix
      ../modules/home/hyprland/default.nix
      ../modules/home/shell.nix
      ../modules/home/cli.nix
    ];
  };
}
```

---

## 11) Migration Protocol (repeatable)

**Discovery → Classification → Relocation → Interface → Validation**

1. **Discovery**: list source features (e.g., keybindings count, waybar blocks, scripts).
2. **Classification**: mark each as **Part** (UI), **Adapter** (theme), or **Tool** (exec).
3. **Relocation**: move: Parts/Adapters → Home; Tools → Infrastructure.
4. **Interface**: ensure UI references **canonical tool names** (no path drift).
5. **Validation**:

   * Commit new files (flakes only see committed content).
   * Build-only: `nixos-rebuild build --flake .#<host> --show-trace`.
   * Run smoke scripts (keybind count, `command -v` checks).
   * Only then: `nixos-rebuild switch`.
   * Rollback ready via bootloader generations.

**Never** `switch` on red (build errors, missing secrets, HM file conflicts).

---

## 12) Validation Gates & Checklists

**Pre-build checks**

* `rg "writeScriptBin" modules/home/` → must be **empty**.
* `rg "systemd\.services" modules/home/` → must be **empty**.
* `rg "/mnt/" modules/` → zero hardcoded paths.
* For flakes: `git add -A && git status` → no untracked required files.

**Waybar gates**

* All expected blocks present; all `exec` use `waybar-*` tools.
* Theme CSS compiles from adapter; CSS vars present (`--bg`, `--fg`, `--warn`, `--crit`).

**Hyprland gates**

* Keybindings count matches prior working count.
* Monitors match (e.g., `eDP-1 …`, `DP-1 …`).
* Rules list matches.
* Autostart calls **canonical** tools.

**System/Auth gates**

* `hwc.system.users.emergencyEnable` set **true** only for migration on the machine file; disabled after confirmation.
* HM `.zshenv` is guarded and unique.
* `sudo` policy as intended (e.g., `wheelNeedsPassword = false` if that’s the policy).

---

## 13) Anti-patterns (hard block)

* Any executable in `modules/home/**` (use Infrastructure).
* Multiple writers to the same file/path (e.g., `.zshenv` from HM **and** elsewhere).
* Profiles that contain implementation logic.
* UI modules calling non-canonical or host-specific binary names.
* Theme hardcoded colors in apps (must go through palette → adapter).

---

## 14) Example: Quick “Add a Themed App” Flow

1. Add adapter `modules/home/theme/adapters/<app>.nix` (palette → app settings).
2. Import adapter from the app’s HM module to fill colors.
3. If app needs helpers, add canonical tools in `modules/infrastructure/<app>-tools.nix`.
4. Wire toggles in profile; validate; build; switch.

---

## 15) Example: Shell & CLI

* `modules/home/shell.nix`: aliases, functions, prompt, HM-owned `.zshenv` (guarded).
* `modules/home/cli.nix`: CLI packages & configs (eza, bat, fzf, zoxide, tmux, micro).
* **Never** define users or sudo here.

---

### Final word

* **Parts** make UI tweakable and safe.
* **Adapters** make theming universal.
* **Tools** keep power where it belongs—in Infrastructure.
* **System** owns auth and sudo with safety rails.
* **Profiles** orchestrate; **Machines** describe reality.
* **Preserve-First** means we don’t lose features while getting clean structure.

This v5 replaces ambiguity with exact terms and examples so there’s no room for drift or misinterpretation.
