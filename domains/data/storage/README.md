# domains/data/storage/

## Purpose

Storage automation services providing temporary file cleanup and disk usage monitoring. Cleans processing directories, container logs, Caddy logs, and systemd journal. Monitors disk usage with configurable alert thresholds.

## Boundaries

- **Manages**: Temp file cleanup, log rotation (Caddy, containers), storage usage monitoring, systemd journal vacuuming
- **Does NOT manage**: Mount configuration (→ `domains/system/mounts/`), backup storage (→ `domains/data/backup/`)

## Structure

```
domains/data/storage/
├── index.nix              # Options, imports
├── README.md              # This file
└── parts/
    ├── cleanup.nix        # Cleanup service + timer, log rotation config
    └── monitoring.nix     # Disk usage monitoring service + timer
```

## Namespace

`hwc.data.storage.*`

## Configuration

```nix
hwc.data.storage = {
  enable = true;

  cleanup = {
    enable = true;
    schedule = "daily";
    retentionDays = 7;
    paths = [
      "/mnt/hot/processing/sonarr-temp"
      "/mnt/hot/processing/radarr-temp"
      "/mnt/hot/processing/lidarr-temp"
      "/mnt/hot/downloads/incomplete"
      "/var/tmp/hwc"
      "/var/cache/hwc"
    ];
  };

  monitoring = {
    enable = true;
    alertThreshold = 85;   # Percentage
  };
};
```

## Monitoring Thresholds

| Path | Threshold | Notes |
|------|-----------|-------|
| `/` | 75% | Root partition — critical, lower threshold |
| `/var/log` | 80% | Where previous disk space issues occurred |
| Hot storage | 85% (configurable) | Processing/downloads |
| Media storage | 85% (configurable) | Long-term media |

Root partition >90% triggers a `user.crit` syslog entry.

## Systemd Units

- `media-cleanup.service` / `media-cleanup.timer` — daily temp file cleanup
- `storage-monitor.service` / `storage-monitor.timer` — hourly disk usage check

## Changelog

- 2026-03-25: Created README per Law 12
