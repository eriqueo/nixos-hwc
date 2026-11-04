# domains/gaming/

## Purpose

Gaming services including retro emulation (RetroArch) and WebDAV-based save sync.

## Boundaries

- **Manages**: RetroArch installation and cores, Sunshine game streaming, WebDAV server (dufs) for RetroArch save sync
- **Does NOT manage**: GPU drivers (→ `domains/system/`), ROMs/content files (user-managed), firewall (→ machine config)

## Structure

`retroarch/stream-session.py` discovers only exact Sunshine virtual-device names and vendor/product IDs. Both legacy passthrough and current libvirtualhid identities map to keyboard/relative mouse roles; duplicates fail and physical/absolute devices stay excluded.

`retroarch/stream-session.py` compiles its fixed controller-output patterns once at module load; controller selection and session lifecycle stay unchanged.

`index.nix` also owns the optional shared Steam/Proton-GE runtime. GPU drivers
and each user’s Steam credentials/library remain outside this capability.
`steam.gpuOffload` runs Steam and its games on the NVIDIA dGPU of a PRIME
laptop by adding the GPU domain's `offloadProfile` to Steam's FHS profile.

`switch-stream/` owns the laptop's Switch streaming session and a repeatable
Batocera client installer. `index.nix` owns Nix options, packages, the Sunshine
catalog and the graphical-session user unit. `stream.py` owns startup, selective
Eden input settings, private pairing migration, client provisioning and backup.
`test_stream.py` exercises these production entry points. This uses Hyprland's
`HWC-GAME` output at 1080p60 and workspace 99, with a separate Pulse server so
streaming does not change the laptop's normal audio default. Sunshine captures
with wlroots and encodes with Intel VAAPI; Eden uses Vulkan. Streamed keyboard
and mouse input are disabled. Native dialogs stay on the streaming output.
The game launcher cycles X11 logical focus on each return to the library, since
Eden can remain inactive in Qt while X11 still names its main window as focused.
This restores D-pad navigation after stopping a game. It preserves valid
dialog/other-app focus and never activates the laptop's physical desktop window.
When closing a dialog leaves X11 focus on an unowned root window, the helper
restores library focus even without a game-title transition.

The Pi stays on Batocera. Its native `switch_stream` service restores the HDMI
PCM bridge, 1080p60 TV mode and Bluetooth connectability at boot. The Bluetooth
agent guard applies only to the exercised factory source, skips a native fix,
and refuses unknown versions. Separate **Ports** launchers select the laptop
without replacing the existing hwc-home Moonlight host or its game entries.
Client settings disable controller mouse mode and swap Nintendo face buttons.
The stream uses 720p60, HEVC, 10 Mbps, and no performance overlay.

After the laptop's normal system activation:

1. Restore private pairing state to `~/.local/share/hwc-switch-stream/`, or run
   `hwc-switch-stream migrate <private-existing-sunshine-directory>` once. Its
   `state.json`, `key.pem`, and `cert.pem` retain pairing; a conflicting identity
   fails before replacement. Credentials are copied only when present.
2. Run `hwc-switch-stream pi-setup` to install the native Pi service and Ports
   launchers over root SSH. Existing Bluetooth bonds and Moonlight host records
   stay private and in place. On a replacement Pi, restore those private records
   from backup or pair the controller and Moonlight again.
3. Start the host with `hwc-switch-stream start` after saving and closing Eden.
   At subsequent graphical logins, the user unit starts automatically. A live
   trial/game blocks takeover; a runtime defer marker permits safe installation
   during play and disappears on reboot. The explicit start command clears it.
4. On the Pi, select **Ports → Switch - lets-go-pikachu** or **Switch - library**.
   The laptop must be awake, logged in to Hyprland, with the dump mount present.

Eden settings merge before each managed game launch while Eden is stopped.
The launcher also generates native `HWC SN30 Pro P1` and `HWC SN30 Pro P2`
input profiles on separate streamed device ports. Select these in a game's
Input Profiles settings when it needs Pro Controllers or two players. The
game's native custom configuration retains that choice; Pikachu's global
handheld configuration stays intact. `hwc-switch-stream profiles` refreshes
only these profiles and is safe while the emulator is open.
Handheld input uses slot 8; disconnected slot 0 retains the same bindings for
native meta shortcuts. **Home + Start** pauses/resumes. **L + Start + Select**
stops emulation after confirmation and returns to the controller-navigable
library. Save in the game first. Text entry uses Eden's controller keyboard.
The launch lock rejects a second emulator before configuration or save effects.

Private pairing, keys and saves are **CRITICAL**, retained indefinitely outside
Nix/Git. `hwc-switch-stream backup` writes private laptop and Pi snapshots on the
existing backup mount, keeping latest and previous copies. Run it after saving
and closing the game for a stable save snapshot. The laptop archive contains
`sunshine/`, `eden-config/`, `eden-keys/`, and `eden-saves/`; restore them to the
state path above, `~/.config/eden/`, `~/.local/share/eden/keys/`, and
`~/.local/share/eden/nand/user/` respectively, while apps are stopped.
The Pi archive is relative to `/userdata/system/`. ROMs and firmware are
user-managed and are not included. Runtime sockets/status files are replaceable;
console logs use systemd's bounded journal or Batocera syslog. One private
pre-change INI copy is retained per edited configuration. No continuous backup
schedule is installed by this module.

The optional headless Sunshine service owns its display, audio and input bridge.
It reuses the existing private Katamari pairing and save directory, binds to the
machine's Tailscale address, and derives direct game launchers from the machine's
`sunshine.games` catalog alongside Desktop and RetroArch. PS2 uses the existing
PCSX2 saves; GameCube uses a separate persistent Dolphin user directory.
Controller profiles retain keyboard input and add streamed SDL gamepads. Nero
images are converted into a bounded, rebuildable cache without changing sources.
Multi-disc GameCube games use runtime playlists for automatic disc changes, with
explicit Disc 2 launchers retained. Each emulator has a bounded runtime boot log.

`retroarch.tv.enable` adds a separate, automatically logged-in X11/Openbox TV
session. Pegasus presents Movies (Jellyfin Desktop in TV mode) and Games from
the same catalog used by Sunshine, with explicit file membership for each
collection, declared after the game metadata to prevent implicit membership.
`tv.audioSink` selects HDMI for local apps
while retaining the Pi's separate virtual display and audio session.
A host-wide nonblocking game lock rejects concurrent emulator launches
before shared save/cache effects. TV profiles live below RetroArch's backed-up
data directory; generated catalog files rebuild from Nix. Bluetooth controllers
need an actual adapter; ordinary display cables do not supply TV-remote input.
The Sunshine unit waits for its configured address and RTSP listener before
reporting ready, with bounded startup and visible failure rather than a loop.

```
domains/gaming/
├── index.nix           # Domain aggregator
├── retroarch/          # RetroArch emulator + Sunshine streaming
│   ├── index.nix       # Options, dependencies and managed streaming service
│   ├── stream-session.py # Supervised display/audio/input and game launcher
│   └── test_session.py # Startup and shared-save ownership regressions
├── switch-stream/      # Laptop Switch streaming and native Batocera setup
│   ├── index.nix       # Options, dependencies, catalog and user service
│   ├── stream.py       # Host/client setup, launch, input and private backup
│   └── test_stream.py  # Production entry-point regressions
└── webdav/             # dufs WebDAV server for save sync
    └── index.nix       # Options + implementation
```

## Configuration

```nix
hwc.gaming.retroarch = {
  enable = true;
  dataDir = "/mnt/media/retroarch";
  cores = { snes9x = true; mgba = true; };
  sunshine.enable = true;
  gpu.enable = true;
};

hwc.gaming.webdav = {
  enable = true;
  auth.usernameFile = config.age.secrets.webdav-username.path;
  auth.passwordFile = config.age.secrets.webdav-password.path;
};
```

## Changelog

- 2026-11-02: Accept current Sunshine libvirtualhid identities in readiness and the Xvfb input bridge, using one guarded discovery path.

- 2026-11-02: Hoist RetroArch controller-output patterns without changing session controls.
- 2026-11-02: Recover library navigation when modal closure leaves focus on the X11 root window; retain focus in owned app/dialog windows.
- 2026-11-02: Generate distinct Pro Controller profiles for players 1 and 2 without changing Pikachu's handheld settings.
- 2026-11-02: Detect game-to-library transitions and restore Qt activation even when the X11 focus ID remains valid.
- 2026-11-02: Restore lost library focus throughout an Eden session after stopping emulation; retain dialog and laptop desktop focus.
- 2026-11-02: Declare laptop Switch streaming, handheld controls, private audio/display, native Pi HDMI/Bluetooth startup, separate client launchers, pairing migration and bounded private snapshots.
- 2026-10-27: Declare game metadata before explicit Movies/Games file filters to prevent Pegasus implicit cross-membership.
- 2026-10-27: Add the optional native Movies/Games TV session, preserve Pi streaming, serialize shared-save game launches, and wait for actual Sunshine listener readiness.
- 2026-10-25: Add `steam.gpuOffload` (PRIME dGPU for Steam and its games);
  enabled on XPS only, other hosts' Steam derivation is unchanged.
- 2026-10-25: Add the isolated XPS household desktop wiring; preserve existing
  host defaults and use the owning login, gaming and credential capabilities.
- 2026-10-20: Add a typed server game catalog, direct PS2/GameCube streaming, controller profiles and Nero image conversion; retain pairing and existing saves.
- 2026-10-20: Manage the home streaming desktop at boot with Nix-owned dependencies; preserve existing pairing and saves instead of relying on expired pilot store paths.
- 2026-09-26: Machine reference follows machines/home; gaming settings are unchanged.

- 2026-07-11: webdav — `User = lib.mkForce "eric"` per the native-services Architecture Law (was bare; no-op today, verified by before/after eval).
- 2026-03-24 (`d9f3f46a`): Law 3 — retroarch `romsDir`/`systemDir` defaults now derive from `config.hwc.paths.media.retroarch.{roms,system}` instead of hardcoded `/mnt/media/retroarch/{roms,system}` (this domain's slice of the repo-wide hwc.paths refactor).
- 2026-03-12 (`f4352f34`): Options consolidation — `retroarch/options.nix` and `webdav/options.nix` deleted; their option declarations inlined into each module's `index.nix` (calls re-qualified as `lib.mkOption`/`lib.types.*`, declarations otherwise unchanged). Commit message says only "options move"; broader intent not stated.
- 2026-03-05 (`8bb19a51`): Header-comment path fixes in `webdav/{index,options}.nix` (`domains/server/native/webdav/...` → `domains/gaming/webdav/...`), this domain's slice of the repo-wide `domains/server/` deletion. Comments only, no behavior change.
- 2026-03-04: Namespace migration hwc.server.native.{retroarch,webdav} → hwc.gaming.*
- 2026-03-04: Created gaming domain, moved retroarch and webdav from domains/server/native/
