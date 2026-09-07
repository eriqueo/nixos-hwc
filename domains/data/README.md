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
├── databases/      # PostgreSQL management
├── backup/         # Rsync + Borg backup automation
├── borg/           # Borg repository jobs, integrity checks, CLI tools
├── cloudbeaver/    # CloudBeaver DB admin UI (raw infra container)
├── storage/        # Storage mount management
├── syncthing/      # Bidirectional file sync over Tailscale
└── couchdb/        # CouchDB for Obsidian LiveSync
```

## Changelog
- 2026-08-28: `databases/` — Postgres role/database declarations reworked over
  two commits. e82ca994 deleted the domain's dead `$PSQL` postStart statements
  (54 across ten modules; `$PSQL` is unassigned in the pinned 15.x module's
  post-start script and `|| true` swallowed every command-not-found), and
  53e84228 declared the roles and databases those dead grants had been hiding —
  `eric` is now declared once here, the module that owns Postgres. Full audit
  and the two structural reasons `postStart` was always the wrong unit are in
  `databases/README.md`. Same day: brainvec checkout refresh fixed and its drift
  exposed (4845a1df).
- 2026-08-26: `backup/` — the service-failure notifier list named seven units
  that do not exist, and two jobs each dumped one concern; `postgresql-db-backup`
  was retired wholesale (85b60856). Removed from `index.nix` and
  `parts/local-backup.nix` (also touched by the gotify decommission, c3440a16).
- 2026-08-16: `storage/` — the cleanup sweep stopped eating live download state
  (41371d7e): `${hot.downloads}/incomplete` is qBittorrent's TempPath, so
  `find -mtime +7 -delete` was pruning in-progress downloads. Removed from the
  default `cleanup.paths`, and the admission rule tightened to scratch-only.
- 2026-07-06: `databases/` — postgres gained a wait-for-gateway `ExecStartPre`
  against the 10.89.0.1 podman-bridge boot race (d2e74a97); redis-main now
  retries until the podman gateway IP exists (1474884a).
- 2026-07-11: Law 3 — `syncthing` dataDir and `backup` mountPoint now derive
  from `hwc.paths` instead of literals (24d869b5).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.
- 2026-06-09: Law 3 finish — databases per-DB backup outputDir default derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-04-12: Add syncthing module (hwc.data.syncthing.*), extracted from machine configs
- 2026-03-18: Add CloudBeaver container for managing PostgreSQL databases, expanding data infrastructure capabilities.

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
