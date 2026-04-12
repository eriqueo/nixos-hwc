# domains/data/databases/

## Purpose

Foundational database services (PostgreSQL, Redis, InfluxDB) used by both containers and native services. Provides shared data persistence layer for server workloads.

## Boundaries

- **Manages**: PostgreSQL (with pgvector), Redis cache, InfluxDB time-series, backup scheduling
- **Does NOT manage**: Application-specific database schemas (→ respective service modules), database user permissions (→ service modules), backup storage location (→ machine config)

## Structure

```
domains/data/databases/
├── index.nix           # Options + implementation (PostgreSQL, Redis, InfluxDB, backups)
└── README.md
```

## Configuration

```nix
hwc.data.databases = {
  postgresql = {
    enable = true;
    version = "15";
    databases = [ "immich" "paperless" "n8n" ];

    # Full database dump (pg_dumpall)
    backup.enable = true;
    backup.schedule = "daily";

    # Per-database compressed backups with retention
    backup.perDatabase = {
      enable = true;
      databases = [ "hwc" "n8n" ];           # Specific DBs to backup
      outputDir = "/home/eric/backups/postgres";  # Default
      compress = true;                        # gzip compression (default)
      retentionDays = 30;                     # Auto-delete old backups (default)
      schedule = "*-*-* 02:30:00";            # 2:30 AM daily (default)
      user = "eric";                          # User with DB access (default)
    };
  };

  redis = {
    enable = true;
    port = 6379;
    maxMemory = "2gb";
  };

  influxdb = {
    enable = true;
    port = 8086;
  };
};
```

## PostgreSQL Notes

- **Version pinned to 15.x** - Data directory format requires migration for upgrades
- **Extensions**: pgvector (vector search), vectorchord (Immich compatibility)
- **Network access**: localhost + container gateway (10.89.0.1)

## Backup Services

| Service | Type | Output | Schedule |
|---------|------|--------|----------|
| `postgresql-backup` | pg_dumpall | `${paths.backup}/postgresql-YYYYMMDD.sql` | Configurable |
| `postgresql-db-backup` | Per-DB pg_dump | `~/backups/postgres/<db>_YYYY-MM-DD.sql.gz` | 2:30 AM daily |

## Consumers

- `domains/media/immich/` - PostgreSQL + Redis
- `domains/media/paperless/` - PostgreSQL + Redis
- `domains/business/firefly/` - PostgreSQL
- `domains/business/databases/` - PostgreSQL (hwc database — see that module's README for schema docs)
- `profiles/server.nix` - n8n uses PostgreSQL

## Changelog

- 2026-03-23: Added `backup.perDatabase` for compressed per-database backups with retention
- 2026-02-27: Migrated from server/native/networking/ per Law 2 namespace compliance
