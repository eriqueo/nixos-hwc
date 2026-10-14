# domains/home/apps/tether

iMessage and SMS from the iPhone on a NixOS laptop over Bluetooth, with no Mac,
cloud or Apple login. The phone exposes messages to a paired "car kit" (MAP),
contacts (PBAP) and notifications (ANCS over LE); Tether speaks those through
BlueZ. Upstream: https://github.com/zackb/tether (MIT), pinned as the `tether`
flake input. Project record: `agent/imessage-linux/` on the tracker hub.

## Structure

| Path | Purpose |
|---|---|
| `index.nix` | HM half: `hwc.home.apps.tether.{enable,settings}` runs `tetherd` as a user service bound to the graphical session and installs the CLI, TUI and GTK client. Takes the package from the system half as the `tetherPackage` special arg, which the flake passes to both HM lanes (standalone `hms` has no osConfig); one producer. `settings` keys are merged into tetherd's own `bluetooth.json` by an `ExecStartPre` (tetherd writes that file too, so Nix never owns it). |
| `sys.nix` | System half: `hwc.system.apps.tether.{enable,adapters,wifi.enable,extensions}` imports the upstream NixOS module and turns on BlueZ's experimental bearer API and the per-adapter Class-of-Device oneshot (`tether-btclass@hciN`). Builds the package from the input with this repo's nixpkgs. Asserts `hwc.system.hardware.bluetooth.enable`. Applies `patches/`. |
| `patches/message-popups.patch` | Adds `message_popups_enabled` to tetherd's `bluetooth.json` (default true): off stops tetherd's popup for new messages only, so courier can own message alerts while other phone notifications keep popping up (`desktop_popups_enabled` silences both). Also adds `backfill` to the `bt_message` event, so clients can skip the catch-up after a reconnect as tetherd's own popup does. Upstream candidate. |

Limits shared by every Mac-free route: no attachments, reactions, typing
indicators or read receipts; SMS and iMessage look the same on the wire; only
messages seen while connected. Never a sole channel for important messages.

## Changelog
- 2026-10-14: `patches/message-popups.patch`: `message_popups_enabled` setting and a `backfill`
  flag on `bt_message` events. courier's alerts turn the setting off (apps/courier).
- 2026-10-13: The package now reaches HM through the flake's `tetherPackage` special arg.
  It used to come through osConfig, which standalone `hms` lacks, so every `hms` removed
  our `tetherd` unit and the package's own unit ran instead, without our settings.
- 2026-10-13: `settings` option, merged into `bluetooth.json` before each start. hwc-laptop
  turns on `group_messages_enabled`: MAP has no group identity, so without it a group
  member's messages sat in their one-to-one thread and a reply went to them alone.
  tetherd now builds group threads from the phone's notifications (new messages only).
- 2026-10-11: New. Enabled on hwc-laptop (system and HM halves). Messages need no
  phone app; the Wi-Fi half for the companion app stays off.
