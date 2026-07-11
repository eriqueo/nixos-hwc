# domains/gaming/

## Purpose

Gaming services including retro emulation (RetroArch) and WebDAV-based save sync.

## Boundaries

- **Manages**: RetroArch installation and cores, Sunshine game streaming, WebDAV server (dufs) for RetroArch save sync
- **Does NOT manage**: GPU drivers (→ `domains/system/`), ROMs/content files (user-managed), firewall (→ machine config)

## Structure

```
domains/gaming/
├── index.nix           # Domain aggregator
├── retroarch/          # RetroArch emulator + Sunshine streaming
│   └── index.nix       # Options + implementation
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

- 2026-03-24 (`d9f3f46a`): Law 3 — retroarch `romsDir`/`systemDir` defaults now derive from `config.hwc.paths.media.retroarch.{roms,system}` instead of hardcoded `/mnt/media/retroarch/{roms,system}` (this domain's slice of the repo-wide hwc.paths refactor).
- 2026-03-12 (`f4352f34`): Options consolidation — `retroarch/options.nix` and `webdav/options.nix` deleted; their option declarations inlined into each module's `index.nix` (calls re-qualified as `lib.mkOption`/`lib.types.*`, declarations otherwise unchanged). Commit message says only "options move"; broader intent not stated.
- 2026-03-05 (`8bb19a51`): Header-comment path fixes in `webdav/{index,options}.nix` (`domains/server/native/webdav/...` → `domains/gaming/webdav/...`), this domain's slice of the repo-wide `domains/server/` deletion. Comments only, no behavior change.
- 2026-03-04: Namespace migration hwc.server.native.{retroarch,webdav} → hwc.gaming.*
- 2026-03-04: Created gaming domain, moved retroarch and webdav from domains/server/native/
