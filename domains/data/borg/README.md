# domains/data/borg/

## Purpose

Borg deduplicating encrypted backup service. Provides block-level deduplication, client-side encryption (repokey-blake2), automatic pruning with configurable retention, and pre/post backup hooks for database dumps.

## Boundaries

- **Manages**: Borg backup jobs, repository integrity checks, CLI wrapper scripts, retention pruning
- **Does NOT manage**: rsync/cloud backups (→ `domains/data/backup/`), backup source directories

## Structure

```
domains/data/borg/
├── index.nix          # Options, Borg job config, integrity checks, CLI tools
├── README.md          # This file
└── parts/
    └── scripts.nix    # Additional helper scripts
```

## Namespace

`hwc.data.borg.*`

## Configuration

```nix
hwc.data.borg = {
  enable = true;

  repo.path = "/mnt/backup/borg";

  sources = [ "/home" "/var/lib/data" ];
  excludePatterns = [ "/nix" ".cache" "node_modules" "__pycache__" ];

  encryption = {
    mode = "repokey-blake2";
    passphraseSecret = "borg-passphrase";   # agenix secret name
  };

  compression = "auto,zstd";

  schedule = {
    frequency = "daily";
    timeOfDay = "03:00";
    randomDelay = "1h";
  };

  retention = {
    daily = 7;
    weekly = 4;
    monthly = 6;
    yearly = 0;
  };

  monitoring.enable = true;
  notifications.onFailure = true;
};
```

## CLI Tools

| Command | Description |
|---------|-------------|
| `borg-hwc` | Wrapper with passphrase pre-loaded (`borg-hwc list`, `borg-hwc info`, etc.) |
| `borg-list` | Show recent archives and repository info |
| `borg-restore <archive> <target> [path]` | Restore files from an archive |
| `borg-backup-now` | Trigger manual backup immediately |

## Dependencies

- **agenix secret**: `borg-passphrase` (repository encryption passphrase)
- **Alerts** (optional): failure notifications via `hwc-service-failure-notifier`

## Systemd Units

- `borgbackup-job-hwc-backup.service` / timer — scheduled Borg backup (TimeoutStartSec=4h)
- `borg-check.service` / `borg-check.timer` — weekly repository integrity check (TimeoutStartSec=6h)
- `borg-health-check.service` / timer — daily backup health check with ntfy notifications

## Changelog

- 2026-03-25: Created README per Law 12
- 2026-03-27: Added TimeoutStartSec to backup (4h) and check (6h) services; added daily health check with ntfy notifications (timer, service failed, stale backup, stuck process, ZFS pool, SMART checks)
