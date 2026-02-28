# domains/server/databases/

## Purpose

Foundational database services (PostgreSQL, Redis, InfluxDB) used by both containers and native services. Provides shared data persistence layer for server workloads.

## Boundaries

- **Manages**: PostgreSQL (with pgvector), Redis cache, InfluxDB time-series, backup scheduling
- **Does NOT manage**: Application-specific database schemas (→ respective service modules), database user permissions (→ service modules), backup storage (→ `domains/system/services/backup/`)

## Structure

```
domains/server/databases/
├── index.nix           # Implementation with OPTIONS/IMPLEMENTATION/VALIDATION
├── options.nix         # hwc.server.databases.* options
└── README.md
```

## Configuration

```nix
hwc.server.databases = {
  postgresql = {
    enable = true;
    databases = [ "immich" "paperless" "n8n" "frigate" ];
    backup.enable = true;
    backup.schedule = "daily";
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

## Consumers

- `domains/server/containers/immich/` - PostgreSQL + Redis
- `domains/server/containers/paperless/` - PostgreSQL + Redis
- `domains/server/containers/firefly/` - PostgreSQL
- `domains/business/` - PostgreSQL
- `domains/server/native/n8n/` - PostgreSQL

## Changelog

- 2026-02-27: Migrated from server/native/networking/ per Law 2 namespace compliance
