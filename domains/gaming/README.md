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
│   └── index.nix       # Options + implementation (options.nix folded in)
└── webdav/             # dufs WebDAV server for save sync
    └── index.nix       # Options + implementation (options.nix folded in)
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

- 2026-03-04: Namespace migration hwc.server.native.{retroarch,webdav} → hwc.gaming.*
- 2026-03-04: Created gaming domain, moved retroarch and webdav from domains/server/native/
- 2026-07-06: retroarch & webdav — `options.nix` folded back into each `index.nix` (options + implementation now co-located); the separate `options.nix` files were deleted. Also part of the `domains/server/` deletion sweep and the hwc.paths hardcoded-path refactor (retroarch romsDir/systemDir). Structure block corrected. No option or behaviour change.
