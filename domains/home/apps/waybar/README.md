# waybar

## Purpose
Configures the Waybar status bar for Hyprland: module layout, palette-driven
HWC CSS, generated helper scripts (network, GPU, lid-sleep, weather, etc.), and a
hardened systemd user service that waits for Hyprland IPC before launching.

## Boundaries
- ✅ `hwc.home.apps.waybar.{enable,powerHub.enable}`; settings from behavior part (conditional power/ollama/dt/recording widgets via options/osConfig/peer modules), `style.css`, script bins on PATH, systemd unit override (`waybar-launch`, Restart=always)
- ✅ System-lane assertions in `sys.nix` (`hwc.system.apps.waybar.enable`): requires audio, bluetooth, networking
- ❌ Does not provide gpu-toggle/gpu-launch (infrastructure GPU module) or the acpid lid handler (`machines/laptop/config.nix`); requires swaync enabled (asserted)

## Structure
- `index.nix` — options, packages, programs.waybar, systemd service, assertions
- `sys.nix` — system-lane option + hardware/network assertions
- `parts/behavior.nix` — module layout and per-widget settings, including daemon-driven dictation status and a tooltip shortcut derived from Hyprland's binding record
- `parts/behavior.nix` includes app-gated Authenticator, Proton Pass and Bitwarden buttons; the Proton buttons use the Hyprland toggle.
- `parts/appearance.nix` — HWC-branded CSS mapped onto shared theme tokens
- The laptop power hub uses paired home/system flags; dictation remains driven by the daemon.
- `parts/packages.nix` — waybar + module dependency packages
- `parts/scripts.nix` — writeShellScriptBin helpers including `waybar-launch` and the structured `hwc-power-status` telemetry producer

## Changelog
- 2026-09-26: Replaced Authenticator text with an icon and added Proton Pass and Bitwarden buttons. Credential app buttons only appear when their app is enabled.
- 2026-09-07: Replaced the static microphone with versioned daemon status; shortcut text comes from the Hyprland binding, right-click cancels, and middle-click acknowledges the result.
- 2026-09-07: added a clickable dictation microphone on both bar layouts when whisper dictation is enabled; hover shows the configured shortcut and click starts/stops the existing recorder.
- 2026-09-02: Both output configs now request the 37 px height already imposed
  by the shared GTK CSS, eliminating ignored 32/36 px requests without changing
  the rendered bar size.
- 2026-09-02: Waybar now consumes the active HWC theme palette; opaque powerline section seams and selector structure are preserved, and CSS comments describe palette semantics rather than Gruvbox-specific hues.
- 2026-08-28: Replaced the single-sample power tooltip with `hwc-power-status`, the one structured telemetry producer for CLI and Waybar consumers. Battery draw/runtime use a bounded five-sample median; the tooltip adds brightness and the live charge ceiling without polling NVIDIA tools.
- 2026-08-28: Added the laptop-only power hub: native TLP profile selection, brightness presets, explicit AC-gated lid policy, wrapped-launch GPU policy, and passive sysfs battery/dGPU telemetry. Its home/system enable flags follow the existing dual-lane handshake so standalone `hms` and integrated NixOS evaluation agree. Removed the unreachable power-profile widget, blind lid toggle, and superseded standalone GPU/lid widgets after live parity verification.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
