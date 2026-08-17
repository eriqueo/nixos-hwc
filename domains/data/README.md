# domains/data/ — Data Infrastructure Domain

## Purpose

Consolidates all data infrastructure: databases (PostgreSQL), backup (rsync/borg),
storage (mount management), Syncthing (file sync), and CouchDB (Obsidian LiveSync).

## Boundaries

- Owns: database services, backup automation, storage mounts, Syncthing file sync, CouchDB
- Does NOT own: application-level data (that belongs to the apps using these services)

## Structure

```
data/
├── index.nix       # Domain aggregator
├── README.md       # This file
├── databases/      # PostgreSQL + Redis management
├── backup/         # Rsync backup automation
├── borg/           # Borg deduplicating encrypted backup (hwc.data.borg.*)
├── cloudbeaver/    # CloudBeaver web DB admin UI (hwc.data.cloudbeaver.*)
├── storage/        # Storage mount management
├── syncthing/      # Bidirectional file sync over Tailscale
└── couchdb/        # CouchDB for Obsidian LiveSync
```

## Changelog
- 2026-08-17: Structure block corrected — `borg/` and `cloudbeaver/` were both absent
  from the listing despite `cloudbeaver` having a 2026-03-18 changelog entry here.
  `databases/` also covers Redis, and Borg is its own module rather than part of
  `backup/`; both descriptions adjusted to match.
- 2026-08-16: `41371d7e` — the storage cleanup sweep no longer eats live download state
  (`storage/index.nix` +14, `parts/cleanup.nix`). See `storage/README.md`.
- 2026-07-11: `24d869b5` — Law 3 sweep: syncthing `dataDir` and backup `mountPoint` now
  derive from `hwc.paths` instead of hardcoded literals.
- 2026-07-06: databases hardening against the podman-gateway boot race — `d2e74a97` adds
  a wait-for-gateway `ExecStartPre` to postgres (+33), and `1474884a` makes `redis-main`
  retry until the `10.89.0.1` gateway IP exists.
- 2026-07-06: `c3440a16` — gotify decommission removed the backup module's gotify
  notification path (`backup/index.nix` -27, `parts/local-backup.nix` -24).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.
- 2026-06-09: Law 3 finish — databases per-DB backup outputDir default derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-04-12: Add syncthing module (hwc.data.syncthing.*), extracted from machine configs
- 2026-03-18: Add CloudBeaver container for managing PostgreSQL databases, expanding data infrastructure capabilities.

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
