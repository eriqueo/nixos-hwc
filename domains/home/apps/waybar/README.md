# waybar

## Purpose
Configures the Waybar status bar for Hyprland: module layout, Gruvbox-Material
CSS, generated helper scripts (network, passive power/GPU status, AC-gated
lid policy, weather, etc.), and a
hardened systemd user service that waits for Hyprland IPC before launching.

## Boundaries
- ✅ `hwc.home.apps.waybar.{enable,powerHub.enable}`; settings from behavior part (conditional power/ollama/dt/recording widgets via options/osConfig/peer modules), `style.css`, script bins on PATH, systemd unit override (`waybar-launch`, Restart=always)
- ✅ System-lane assertions in `sys.nix` (`hwc.system.apps.waybar.enable`): requires audio, bluetooth, networking
- ❌ Does not provide gpu-toggle/gpu-launch (infrastructure GPU module) or the acpid lid handler (`machines/laptop/config.nix`); requires swaync enabled (asserted)

## Structure
- `index.nix` — options, packages, programs.waybar, systemd service, assertions
- `sys.nix` — system-lane option + hardware/network assertions
- `parts/behavior.nix` — module layout and per-widget settings; laptop power hub visibility is owned by the home-lane option and cross-checked against its system-lane dependency
- `parts/appearance.nix` — curated Gruvbox-Material CSS (palette feed is backlog)
- `parts/packages.nix` — waybar + module dependency packages
- `parts/scripts.nix` — writeShellScriptBin helpers including `waybar-launch` and the structured `hwc-power-status` telemetry producer

## Changelog
- 2026-08-28: Replaced the single-sample power tooltip with `hwc-power-status`, the one structured telemetry producer for CLI and Waybar consumers. Battery draw/runtime use a bounded five-sample median; the tooltip adds brightness and the live charge ceiling without polling NVIDIA tools.
- 2026-08-28: Added the laptop-only power hub: native TLP profile selection, brightness presets, explicit AC-gated lid policy, wrapped-launch GPU policy, and passive sysfs battery/dGPU telemetry. Its home/system enable flags follow the existing dual-lane handshake so standalone `hms` and integrated NixOS evaluation agree. Removed the unreachable power-profile widget, blind lid toggle, and superseded standalone GPU/lid widgets after live parity verification.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
