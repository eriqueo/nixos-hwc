# hyprland

## Purpose
Configures the Hyprland Wayland window manager as the desktop session: full `wayland.windowManager.hyprland` settings (keybinds, window rules, monitors/input, autostart, theming from the palette), companion packages (wofi, hyprshot, swaybg, cliphist, hyprsome, etc.), and a monitor-hotplug listener user service that restarts waybar. On NixOS hosts it also carries the system-owned EGL vendor selection into the lingering systemd user manager for subsequently started desktop services. Enabling it force-enables waybar and swaync (mkForce) and asserts kitty and yazi are enabled.

## Boundaries
- ✅ Manages: HM lane via `hwc.home.apps.hyprland.enable`; system lane via `hwc.system.apps.hyprland.enable` in `sys.nix` (helper scripts as system packages, mkDefault audio/bluetooth).
- ❌ Does not manage: waybar/swaync/kitty/yazi config (their own app modules), the greeter/login path (`domains/system`), the palette itself (`domains/home/theme`), or GPU launch scripts (`gpu-launch` comes from elsewhere).

## Structure
- The mail binding derives from `hwc.home.core.shell.aliases.aerc`, shared with Zellij and Workbench, with local `aerc` as its fallback.
- `index.nix` — HM options + implementation: packages, hyprland settings merge, submaps, monitor-listener service, NixOS session-variable bridge, cross-lane and dependency assertions. Threads `behavior.keybinds` → `theme`, `theme.card` → `session`.
- `index.nix` also provides `hyprland-app-toggle`, the shared window show/hide and graphical launch command for credential apps.
- `sys.nix` — system-lane options; exposes helper scripts via `environment.systemPackages`.
- `parts/behavior.nix` — the keybind records (SUPER-based, conditional todui/dt/gsr/dictation binds), mouse binds, the `resize` submap, and window rules. Returns settings, keybinds, submaps, the dictation toggle/cancel commands shared with Waybar, and the SUPER+W Workbench command shared with session autostart. `settings` is what Hyprland loads; `keybinds` supplies the legend.
- Floating windows are centered and limited to 80% of their current monitor's logical width and height. Small dialogs retain their requested size. Bluetooth starts at 40% width / 50% height; title-matched file pickers start at 50% / 60%. Hyprland supplies monitor dimensions and scale at runtime; no screen dimensions are copied into these rules.
- `parts/hardware.nix` — monitor layout (eDP-1 + DP-1), workspace→monitor mapping, input/touchpad/per-device settings.
- `parts/scripts.nix` — helper script bins: smart-move, workspace-overview, monitor-toggle, refinery-intake, etc.
- `parts/session.nix` — exec-once autostart list (swaybg wallpaper, cliphist, workspace-pinned Chromium, kitty and — when enabled — Workbench on 3), cursor env vars, and the `hyprland-keybinds-viewer` package.
- The session starts enabled Bitwarden and Proton Pass clients so their native Waybar tray icons exist after login. Bitwarden uses its native `--autostart` mode; Proton Pass follows its normal startup behavior.
- `parts/theme.nix` — palette→presentation. Returns `{ settings, card }`: Hyprland colors/gaps/blur/animations, plus the SUPER+? legend card painted from `behavior.keybinds`.

### Keybind legend (SUPER+?)
Every binding is declared **once** in `parts/behavior.nix`, as a record carrying both its Hyprland realization (`act`) and a human description (`desc`). The live `bind` list and the legend card are both derived from those records, so the legend cannot drift from the keys it documents — adding a binding makes it appear in both.

It is deliberately *not* read from `hyprctl binds -j`: that API emits malformed JSON in Hyprland 0.56.0 (keys and values misaligned — `"keycode": RETURN`, `"allow_input_capture": ,`), and carries no descriptions, so the best it could ever print is `exec hyprland-monitor-toggle`.

## Changelog
- 2026-09-30: Start enabled credential clients in the Hyprland session. Their native tray icons disappeared after reboot because installing the apps did not launch them; Authenticator's static Waybar button remained. Live registration changed from an empty tray to verified Bitwarden and Proton Pass items after one launch per app.
- 2026-09-30: Constrain floating windows with monitor-relative `max_size`; replace fixed file-picker dimensions and Blueman's unbounded saved geometry with monitor-relative starting sizes. A headless Hyprland replay reproduced the original overflow and passed 15 cases across 1920×1080, 2560×1600 and 1280×800 at scale 1.25, including small dialogs and tiled windows. Live `setprop` probing exposed a compositor crash, so subsequent sizing tests ran in isolation.
- 2026-09-28: Autostart Workbench on workspace 3 (only where `hwc.home.apps.workbench.enable`), using the SUPER+W command exported from `behavior.nix`. Removed the Proton Mail app (mail moves to aerc inside Workbench) and the explicit `xfconfd` launch (Thunar D-Bus-activates it).
- 2026-09-28: Removed the JobTread `--app` Chromium window from autostart. It ran unseen on workspace 4 for the whole session and shared the Default profile with SUPER+B Chromium; after 10 days of uptime it lost its `/tmp` singleton and a second browser opened over the same profile.
- 2026-09-26: Derive SUPER+E from the configured mail command, removing its stale home-server destination.
- 2026-09-26: Credential app launchers now use one Hyprland-owned toggle and show new windows on the current workspace. Removed the stale Proton Pass class rule and Authenticator workspace pin.
- 2026-09-16: Launch Workbench with the exact `hwc-workbench` window class and suppress activation requests for that class, preventing background aerc bells from switching workspaces while preserving the desktop-wide focus policy.
- 2026-09-12: Publish the system-owned EGL vendor selection through Home Manager's `environment.d` output so daemon-reload updates the lingering systemd user manager; subsequently started desktop services inherit the Mesa-only default without per-service copies.
- 2026-09-07: Routed dictation to the owned daemon client and added SUPER+SHIFT+ESCAPE cancellation.
- 2026-08-06: SUPER+? keybind legend. `behavior.nix` restructured to return `{ settings, keybinds, submaps }` — bindings are now records carrying descriptions, with the live binds derived from them; `theme.nix` gained the `card` renderer (palette→ANSI, HWC which-key look) alongside its Hyprland colors; `session.nix` gained the viewer package in its previously-empty `packages`. Added the `resize` submap: `SUPER,R,submap,resize` had been live with **no `submap = resize` block defined anywhere**, so it entered an empty submap that swallowed every key and rebound no exit — a keyboard softlock until Hyprland restarted. Now has h/j/k/l + arrow resize (`binde`, repeats while held) and escape/return exits. Removed the dead `hyprland-keybinds-viewer` from `scripts.nix`. Bind parity verified against the live `hyprland.conf`: no binds lost.
- 2026-07-11: session.nix — removed stale commented-out screenshots-path fallback (superseded by `hwc.paths.screenshots`; Law 3 audit cleanup, no functional change).
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
