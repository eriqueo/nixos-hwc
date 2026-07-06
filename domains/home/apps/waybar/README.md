# waybar

## Purpose
Configures the Waybar status bar for Hyprland: module layout, Gruvbox-Material
CSS, generated helper scripts (network, GPU, lid-sleep, weather, etc.), and a
hardened systemd user service that waits for Hyprland IPC before launching.

## Boundaries
- ✅ `hwc.home.apps.waybar.enable`; settings from behavior part (conditional ollama/dt/recording widgets via osConfig/peer modules), `style.css`, script bins on PATH, systemd unit override (`waybar-launch`, Restart=always)
- ✅ System-lane assertions in `sys.nix` (`hwc.system.apps.waybar.enable`): requires audio, bluetooth, networking
- ❌ Does not provide gpu-toggle/gpu-launch (infrastructure GPU module) or the acpid lid handler (`machines/laptop/config.nix`); requires swaync enabled (asserted)

## Structure
- `index.nix` — options, packages, programs.waybar, systemd service, assertions
- `sys.nix` — system-lane option + hardware/network assertions
- `parts/behavior.nix` — module layout and per-widget settings
- `parts/appearance.nix` — curated Gruvbox-Material CSS (palette feed is backlog)
- `parts/packages.nix` — waybar + module dependency packages
- `parts/scripts.nix` — writeShellScriptBin helpers incl. waybar-launch

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
