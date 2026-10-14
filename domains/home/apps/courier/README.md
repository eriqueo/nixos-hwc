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
  - the hotkey → `apps/hyprland/parts/behavior.nix` (the window tiles; no float rule)
  - app behaviour, protocol handling or tests → the courier repo

## Structure

| Path | Purpose |
|---|---|
| `index.nix` | `hwc.home.apps.courier.{enable,port,windowClass,alerts.enable}`. Runs `courier serve` as a user service after `tetherd.service`, with `COURIER_THEME` pointing at CSS generated from `config.hwc.home.theme.colors`. With `alerts.enable` (default) it pins notify-send and wl-copy, passes a show-window script (`hyprland-app-toggle --show`), and sets tether's `message_popups_enabled = false` so courier is the one producer of message alerts. Asserts `apps.tether` and `apps.chromium` are enabled. |

The window is `chromium-hwc --app=http://courier.localhost:<port>`. Chromium ignores `--class` on Wayland and takes
the app_id from the host, so the class is `chrome-courier.localhost__-Default` (measured 2026-10-12).

## Changelog
- 2026-10-14: courier 1f38d0c, slice 4: desktop alerts for new messages (Open, Mark read, Copy code for one-time codes; hide per conversation; at most 3 per 30 s, then a summary; quiet for the conversation on screen). New `alerts.enable` option turns tetherd's message popup off; its other popups stay.
- 2026-10-13: courier a2da8ef: group threads (with tether's `group_messages_enabled`) are tagged "group" and name each sender. A reply tetherd cannot route is refused with its reason.
- 2026-10-12: courier d7130f7, slice 3: opening a conversation in a focused window marks it read on the phone; mark unread; Waybar `custom/courier` badge (see apps/waybar).
- 2026-10-12: courier 9a4146e, slice 2: reply and New Message with contact search. Sends are at most once (no retries; a reused id is refused).
- 2026-10-12: courier 20674d5 fixes a blank screen on opening a conversation. The window now tiles: the float rule was removed at Eric's request.
- 2026-10-12: New. Slice 1, a read-only window over tetherd. Enabled on hwc-laptop. SUPER+U toggles the window.
