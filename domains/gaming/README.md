# domains/gaming/

## Purpose

Gaming services including retro emulation (RetroArch) and WebDAV-based save sync.

## Boundaries

- **Manages**: RetroArch installation and cores, Sunshine game streaming, WebDAV server (dufs) for RetroArch save sync
- **Does NOT manage**: GPU drivers (→ `domains/system/`), ROMs/content files (user-managed), firewall (→ machine config)

## Structure

`index.nix` also owns the optional shared Steam/Proton-GE runtime. GPU drivers
and each user’s Steam credentials/library remain outside this capability.
`steam.gpuOffload` runs Steam and its games on the NVIDIA dGPU of a PRIME
laptop by adding the GPU domain's `offloadProfile` to Steam's FHS profile.

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
the same catalog used by Sunshine. `tv.audioSink` selects HDMI for local apps
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
