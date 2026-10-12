# domains/home/apps/courier

## Purpose
courier is our iPhone messages app. It is a client of tetherd (`apps/tether`), which reaches the phone over
Bluetooth. The app lives at `github:eriqueo/courier` (`~/600_apps/courier`). This module runs its service, hands
it the HWC palette, and wires the desktop.

## Boundaries
- ✅ manages:
  - the `courier` user service
  - the generated palette CSS (`hwc.nix` → CSS variables)
  - the loopback port option
  - the read-only window class
- ❌ does not:
  - the Bluetooth daemon or pairing → `apps/tether`
  - the hotkey and window rule → `apps/hyprland/parts/behavior.nix`
  - app behaviour, protocol handling or tests → the courier repo

## Structure

| Path | Purpose |
|---|---|
| `index.nix` | `hwc.home.apps.courier.{enable,port,windowClass}`. Runs `courier serve` as a user service after `tetherd.service`, with `COURIER_THEME` pointing at CSS generated from `config.hwc.home.theme.colors`. Asserts `apps.tether` and `apps.chromium` are enabled. |

The window is `chromium-hwc --app=http://courier.localhost:<port>`. Chromium ignores `--class` on Wayland and takes
the app_id from the host, so the class is `chrome-courier.localhost__-Default` (measured 2026-10-12).

## Changelog
- 2026-10-12: New. Slice 1, a read-only window over tetherd. Enabled on hwc-laptop. SUPER+U toggles the window.
