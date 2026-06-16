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
│   ├── index.nix
│   └── options.nix
└── webdav/             # dufs WebDAV server for save sync
    ├── index.nix
    └── options.nix
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

- 2026-06-16: Mechanical sweep — `d9f3f46a` Law 3 path replacement across
  11 modules (hwc.paths abstractions); `f4352f34` options-move pass; `8bb19a51`
  retires `domains/server/` (predecessor namespace for these modules).
- 2026-03-04: Namespace migration hwc.server.native.{retroarch,webdav} → hwc.gaming.*
- 2026-03-04: Created gaming domain, moved retroarch and webdav from domains/server/native/
