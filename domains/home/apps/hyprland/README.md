# hyprland

## Purpose
Configures the Hyprland Wayland window manager as the desktop session: full `wayland.windowManager.hyprland` settings (keybinds, window rules, monitors/input, autostart, theming from the palette), companion packages (wofi, hyprshot, swaybg, cliphist, hyprsome, etc.), and a monitor-hotplug listener user service that restarts waybar. Enabling it force-enables waybar and swaync (mkForce) and asserts kitty and yazi are enabled.

## Boundaries
- ✅ Manages: HM lane via `hwc.home.apps.hyprland.enable`; system lane via `hwc.system.apps.hyprland.enable` in `sys.nix` (helper scripts as system packages, mkDefault audio/bluetooth).
- ❌ Does not manage: waybar/swaync/kitty/yazi config (their own app modules), the greeter/login path (`domains/system`), the palette itself (`domains/home/theme`), or GPU launch scripts (`gpu-launch` comes from elsewhere).

## Structure
- `index.nix` — HM options + implementation: packages, hyprland settings merge, monitor-listener service, cross-lane and dependency assertions.
- `sys.nix` — system-lane options; exposes helper scripts via `environment.systemPackages`.
- `parts/behavior.nix` — keybinds (SUPER-based, conditional todui/dt/gsr binds), mouse binds, window rules.
- `parts/hardware.nix` — monitor layout (eDP-1 + DP-1), workspace→monitor mapping, input/touchpad/per-device settings.
- `parts/scripts.nix` — helper script bins: smart-move, workspace-overview, monitor-toggle, keybinds-viewer, refinery-intake, etc.
- `parts/session.nix` — exec-once autostart list (swaybg wallpaper, cliphist, workspace-pinned apps) and cursor env vars.
- `parts/theme.nix` — palette→Hyprland colors, gaps/borders/blur/shadow, animations, dwindle, misc.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
- 2026-07-06: `parts/behavior.nix` — SUPER+SHIFT+B keybind repointed `gpu-launch librewolf-hwc` → `gpu-launch firefox-hwc` (part of the repo-wide librewolf → firefox migration).
