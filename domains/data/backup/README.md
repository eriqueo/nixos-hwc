# domains/data/backup/

## Purpose

System-wide backup service supporting local backups (external drives, NAS, DAS), cloud backups (Proton Drive via rclone), and automated server backup scripts for containers, databases, and system configuration.

## Boundaries

- **Manages**: rsync local backups, rclone cloud sync, server backup scripts, scheduling, notifications, encryption options, database consistency hooks
- **Does NOT manage**: Borg deduplicating backups (→ `domains/data/borg/`), database services (→ `domains/data/databases/`)

## Structure

```
domains/data/backup/
├── index.nix                      # Option definitions + base packages
├── README.md                      # This file
└── parts/
    ├── local-backup.nix           # rsync-based local backups with rotation
    ├── cloud-backup.nix           # Proton Drive / rclone cloud sync
    ├── backup-scheduler.nix       # systemd timers and scheduling
    ├── backup-utils.nix           # CLI tools (backup-status, backup-verify, etc.)
    ├── database-hooks.nix         # Pre-backup database dump hooks (PostgreSQL, Redis)
    └── server-backup-scripts.nix  # Container, database, and system backup scripts
```

## Namespace

`hwc.data.backup.*`

## Configuration

```nix
hwc.data.backup = {
  enable = true;

  local = {
    enable = true;
    mountPoint = "/mnt/backup";
    useRsync = true;
    sources = [ "/home" "/etc/nixos" ];
    keepDaily = 5; keepWeekly = 2; keepMonthly = 3;
    minSpaceGB = 10;
  };

  cloud = {
    enable = true;
    provider = "proton-drive";
    remotePath = "Backups";
    syncMode = "sync";
  };

  schedule = {
    enable = true;
    frequency = "daily";
    timeOfDay = "02:00";
    randomDelay = "1h";
    onlyOnAC = true;
  };

  notifications = {
    enable = true;
    onFailure = true;
    ntfy = { enable = true; onFailure = true; };
  };

  database.postgres.enable = true;

  encryption.cloud.enable = true;
};
```

## CLI Tools

| Command | Description |
|---------|-------------|
| `backup-all` | Run full server backup (system + databases + containers) |
| `backup-system` | Backup NixOS config, system state, package list |
| `backup-databases` | Dump CouchDB and Immich PostgreSQL |
| `backup-containers` | Export container configs and volumes |

## Systemd Units

- `server-backup.service` / `server-backup.timer` — daily automated full backup
- `local-backup.service` / `local-backup.timer` — rsync to external storage
- `cloud-backup.service` / `cloud-backup.timer` — rclone to Proton Drive

## Changelog

- 2026-04-04: Update notification refs: `hwc.alerts.*` to `hwc.monitoring.alerts.*`, `hwc.automation.gotify.*` to `hwc.notifications.send.gotify.*` (domain redistribution)

- 2026-03-25: Created README per Law 12
