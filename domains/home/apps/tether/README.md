# domains/home/apps/tether

iMessage and SMS from the iPhone on a NixOS laptop over Bluetooth, with no Mac,
cloud or Apple login. The phone exposes messages to a paired "car kit" (MAP),
contacts (PBAP) and notifications (ANCS over LE); Tether speaks those through
BlueZ. Upstream: https://github.com/zackb/tether (MIT), pinned as the `tether`
flake input. Project record: `agent/imessage-linux/` on the tracker hub.

## Structure

| Path | Purpose |
|---|---|
| `index.nix` | HM half: `hwc.home.apps.tether.enable` runs `tetherd` as a user service bound to the graphical session and installs the CLI, TUI and GTK client. Takes the package from the system half through osConfig; one producer. |
| `sys.nix` | System half: `hwc.system.apps.tether.{enable,adapters,wifi.enable,extensions}` imports the upstream NixOS module and turns on BlueZ's experimental bearer API and the per-adapter Class-of-Device oneshot (`tether-btclass@hciN`). Builds the package from the input with this repo's nixpkgs. Asserts `hwc.system.hardware.bluetooth.enable`. |

Limits shared by every Mac-free route: no attachments, reactions, typing
indicators or read receipts; SMS and iMessage look the same on the wire; only
messages seen while connected. Never a sole channel for important messages.

## Changelog
- 2026-10-11: New. Enabled on hwc-laptop (system and HM halves). Messages need no
  phone app; the Wi-Fi half for the companion app stays off.
