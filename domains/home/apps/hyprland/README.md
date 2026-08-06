# hyprland

## Purpose
Configures the Hyprland Wayland window manager as the desktop session: full `wayland.windowManager.hyprland` settings (keybinds, window rules, monitors/input, autostart, theming from the palette), companion packages (wofi, hyprshot, swaybg, cliphist, hyprsome, etc.), and a monitor-hotplug listener user service that restarts waybar. Enabling it force-enables waybar and swaync (mkForce) and asserts kitty and yazi are enabled.

## Boundaries
- ✅ Manages: HM lane via `hwc.home.apps.hyprland.enable`; system lane via `hwc.system.apps.hyprland.enable` in `sys.nix` (helper scripts as system packages, mkDefault audio/bluetooth).
- ❌ Does not manage: waybar/swaync/kitty/yazi config (their own app modules), the greeter/login path (`domains/system`), the palette itself (`domains/home/theme`), or GPU launch scripts (`gpu-launch` comes from elsewhere).

## Structure
- `index.nix` — HM options + implementation: packages, hyprland settings merge, submaps, monitor-listener service, cross-lane and dependency assertions. Threads `behavior.keybinds` → `theme`, `theme.card` → `session`.
- `sys.nix` — system-lane options; exposes helper scripts via `environment.systemPackages`.
- `parts/behavior.nix` — the keybind records (SUPER-based, conditional todui/dt/gsr binds), mouse binds, the `resize` submap, and window rules. Returns `{ settings, keybinds, submaps }`: `settings` is what Hyprland loads, `keybinds` is the same bindings as structured records for the legend.
- `parts/hardware.nix` — monitor layout (eDP-1 + DP-1), workspace→monitor mapping, input/touchpad/per-device settings.
- `parts/scripts.nix` — helper script bins: smart-move, workspace-overview, monitor-toggle, refinery-intake, etc.
- `parts/session.nix` — exec-once autostart list (swaybg wallpaper, cliphist, workspace-pinned apps), cursor env vars, and the `hyprland-keybinds-viewer` package.
- `parts/theme.nix` — palette→presentation. Returns `{ settings, card }`: Hyprland colors/gaps/blur/animations, plus the SUPER+? legend card painted from `behavior.keybinds`.

### Keybind legend (SUPER+?)
Every binding is declared **once** in `parts/behavior.nix`, as a record carrying both its Hyprland realization (`act`) and a human description (`desc`). The live `bind` list and the legend card are both derived from those records, so the legend cannot drift from the keys it documents — adding a binding makes it appear in both.

It is deliberately *not* read from `hyprctl binds -j`: that API emits malformed JSON in Hyprland 0.56.0 (keys and values misaligned — `"keycode": RETURN`, `"allow_input_capture": ,`), and carries no descriptions, so the best it could ever print is `exec hyprland-monitor-toggle`.

## Changelog
- 2026-08-06: SUPER+? keybind legend. `behavior.nix` restructured to return `{ settings, keybinds, submaps }` — bindings are now records carrying descriptions, with the live binds derived from them; `theme.nix` gained the `card` renderer (palette→ANSI, HWC which-key look) alongside its Hyprland colors; `session.nix` gained the viewer package in its previously-empty `packages`. Added the `resize` submap: `SUPER,R,submap,resize` had been live with **no `submap = resize` block defined anywhere**, so it entered an empty submap that swallowed every key and rebound no exit — a keyboard softlock until Hyprland restarted. Now has h/j/k/l + arrow resize (`binde`, repeats while held) and escape/return exits. Removed the dead `hyprland-keybinds-viewer` from `scripts.nix`. Bind parity verified against the live `hyprland.conf`: no binds lost.
- 2026-07-11: session.nix — removed stale commented-out screenshots-path fallback (superseded by `hwc.paths.screenshots`; Law 3 audit cleanup, no functional change).
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
