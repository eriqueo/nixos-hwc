# Path Abstraction System

**Source**: Extracted from Charter v8.0 Section 14
**Related Law**: Charter v9.0 Law 3 (Path Abstraction Contract)
**Implementation**: `domains/system/core/paths.nix`

## Overview

The HWC path abstraction system provides a universal, declarative API for filesystem paths across all domains. All paths are defined centrally in `paths.nix` and referenced via `config.hwc.paths.*` throughout the configuration.

**Core Rule**: No hardcoded filesystem paths in domain modules. All paths must go through the abstraction layer.

---

## Core Principles

1. **Single Source of Truth**: `domains/system/core/paths.nix` is the canonical location for all filesystem path definitions
2. **Auto-Detection**: System auto-detects primary user and provides home-relative defaults
3. **Machine-Specific Overrides**: Machines override paths in `machines/<host>/config.nix`
4. **Fail-Fast**: Invalid paths fail at build time, not runtime
5. **Never Null**: All paths have sensible defaults (no nullable storage tiers)

---

## Auto-Detection System

The path system automatically detects the primary user and home directory:

```nix
# Auto-detect primary user (prefers "eric", falls back to first normal user)
primaryUser =
  if config.users ? users && config.users.users ? eric
  then "eric"
  else if config.users ? users
  then
    let
      nonSystemUsers = lib.filter (name:
        let u = config.users.users.${name};
        in u.isNormalUser or false
      ) (lib.attrNames config.users.users);
    in
      if nonSystemUsers != []
      then lib.head nonSystemUsers
      else "user"
  else "user";

# Auto-detect home directory
detectedHome =
  if config.users ? users && config.users.users ? ${primaryUser}
  then config.users.users.${primaryUser}.home
  else "/home/${primaryUser}";
```

---

## Complete Path Schema

### Storage Tiers (Home-Relative Defaults)

All storage tiers default to `${detectedHome}/storage/*` for portability:

```nix
hwc.paths = {
  # Hot Tier (SSD/Fast Storage)
  hot.root = "${detectedHome}/storage/hot";
  hot.downloads.root = "${hot.root}/downloads";
  hot.downloads.music = "${hot.downloads.root}/music";
  hot.downloads.torrents = "${hot.downloads.root}/torrents";
  hot.surveillance = "${hot.root}/surveillance";
  hot.processing = "${hot.root}/processing";

  # Media Tier (HDD/Bulk Storage)
  media.root = "${detectedHome}/storage/media";
  media.music = "${media.root}/music";
  media.movies = "${media.root}/movies";
  media.tv = "${media.root}/tv";
  media.books = "${media.root}/books";
  media.surveillance = "${media.root}/surveillance";

  # Archive Tier (Cold Storage)
  cold = "${detectedHome}/storage/archive";

  # Backup Destination
  backup = "${detectedHome}/storage/backup";

  # Photo Storage (Immich)
  photos = "${detectedHome}/storage/photos";

  # System Paths (Always Available)
  state = "/var/lib/hwc";        # Service persistent data
  cache = "/var/cache/hwc";      # Temporary cache
  logs = "/var/log/hwc";         # Service logs
  temp = "/tmp/hwc";             # Temporary processing

  # User Paths (PARA Structure)
  user.home = detectedHome;
  user.inbox = "${detectedHome}/000_inbox";
  user.work = "${detectedHome}/100_hwc";
  user.personal = "${detectedHome}/200_personal";
  user.tech = "${detectedHome}/300_tech";
  user.media = "${detectedHome}/500_media";
  user.vaults = "${detectedHome}/900_vaults";

  # Application Roots
  business.root = "/opt/business";
  ai.root = "/opt/ai";
  arr.downloads = "/opt/downloads";
  networking.root = "/opt/networking";
  networking.pihole = "${networking.root}/pihole";
  networking.ntfy = "${networking.root}/ntfy";
};
```

---

## Machine-Specific Overrides

Machines override paths when they have dedicated storage mounts:

### Server Example (Dedicated Storage)

```nix
# machines/server/config.nix
{
  hwc.paths = {
    # Override defaults with dedicated mounts
    hot.root = "/mnt/hot";
    media.root = "/mnt/media";
    backup = "/mnt/backup";
    photos = "/mnt/photos";

    # Derived paths automatically update
    # hot.downloads.root becomes "/mnt/hot/downloads"
    # media.music becomes "/mnt/media/music"
  };
}
```

### Laptop Example (Home-Relative Storage)

```nix
# machines/laptop/config.nix
{
  # No overrides needed - uses home-relative defaults
  # Everything under ${detectedHome}/storage/*

  # Can still override specific paths if needed:
  hwc.paths.cold = "/external/archive";
}
```

---

## Usage Patterns

### In Container Modules

```nix
# ✓ CORRECT
virtualisation.oci-containers.containers.jellyfin = {
  volumes = [
    "${config.hwc.paths.media.movies}:/movies:ro"
    "${config.hwc.paths.media.tv}:/tv:ro"
    "${config.hwc.paths.media.music}:/music:ro"
  ];
};

# ✗ VIOLATION (Law 3)
virtualisation.oci-containers.containers.jellyfin = {
  volumes = [
    "/mnt/media/movies:/movies:ro"  # Hardcoded path!
  ];
};
```

### In Service Modules

```nix
# ✓ CORRECT
systemd.services.my-service = {
  serviceConfig = {
    StateDirectory = "hwc/my-service";  # Creates /var/lib/hwc/my-service
    CacheDirectory = "hwc/my-service";  # Creates /var/cache/hwc/my-service
  };

  environment = {
    DATA_DIR = config.hwc.paths.media.root;
    BACKUP_DIR = config.hwc.paths.backup;
  };
};

# ✗ VIOLATION (Law 3)
systemd.services.my-service = {
  environment = {
    DATA_DIR = "/mnt/media";  # Hardcoded path!
  };
};
```

### In Home Manager Modules

```nix
# ✓ CORRECT
programs.mpv.config = {
  screenshot-directory = config.hwc.paths.user.media;
};

# ✗ VIOLATION (Law 3)
programs.mpv.config = {
  screenshot-directory = "/home/eric/media";  # Hardcoded path!
};
```

---

## Validation

### Mechanical Checks

These searches identify path abstraction violations:

```bash
# Hardcoded /mnt/ or /home/ paths (excluding paths.nix and docs)
rg '="/mnt/|="/home/' domains --glob '!paths.nix' --glob '!*.md'

# Should return empty (all paths use hwc.paths.* abstraction)
```

### Build-Time Validation

Assertions in `paths.nix` validate path correctness:

```nix
config.assertions = [
  {
    assertion = lib.hasPrefix "/" cfg.hot.root;
    message = "hwc.paths.hot.root must be an absolute path";
  }
  {
    assertion = lib.hasPrefix "/" cfg.media.root;
    message = "hwc.paths.media.root must be an absolute path";
  }
  # ... more assertions
];
```

---

## Environment Variables

The path system exports environment variables for shell scripts:

```bash
# Available in all shells
$HWC_HOT_STORAGE     # ${hwc.paths.hot.root}
$HWC_MEDIA_STORAGE   # ${hwc.paths.media.root}
$HWC_COLD_STORAGE    # ${hwc.paths.cold}
$HWC_BACKUP_STORAGE  # ${hwc.paths.backup}
$HWC_USER_HOME       # ${hwc.paths.user.home}
```

Usage in scripts:

```bash
#!/usr/bin/env bash
# Backup script example

SOURCE="${HWC_MEDIA_STORAGE}/important-data"
DEST="${HWC_BACKUP_STORAGE}/$(date +%Y%m%d)"

rsync -av "$SOURCE" "$DEST"
```

---

## Migration from Hardcoded Paths

When refactoring modules with hardcoded paths:

1. **Identify hardcoded paths**: Use `rg '="/mnt/|="/home/'` to find violations
2. **Map to path schema**: Determine which `hwc.paths.*` option matches the semantic purpose
3. **Replace with abstraction**: Use `config.hwc.paths.*` instead of string literal
4. **Verify**: Run `nix flake check` to ensure no evaluation errors
5. **Test on both laptop and server**: Ensure defaults work on home-relative and dedicated storage

### Example Migration

```nix
# BEFORE (hardcoded)
volumes = [
  "/mnt/media/music:/music:ro"
  "/mnt/hot/downloads:/downloads:rw"
];

# AFTER (abstracted)
volumes = [
  "${config.hwc.paths.media.music}:/music:ro"
  "${config.hwc.paths.hot.downloads.root}:/downloads:rw"
];
```

---

## Benefits

1. **Portability**: Config works on any machine with any username
2. **Flexibility**: Override paths per-machine without touching domain modules
3. **Consistency**: All modules use same paths, no conflicts
4. **Debuggability**: Single source of truth for path definitions
5. **Fail-Fast**: Invalid paths caught at build time, not runtime
6. **Documentation**: Path schema documents storage architecture

---

## See Also

- **Charter v9.0 Law 3**: Path Abstraction Contract
- **Implementation**: `domains/system/core/paths.nix`
- **Domain Usage**: Check domain READMEs for domain-specific path patterns
