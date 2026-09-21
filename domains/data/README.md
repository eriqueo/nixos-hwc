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
├── storage/        # Storage mount management
├── syncthing/      # Bidirectional file sync over Tailscale
├── borg/           # Borg repository + backup units (hwc.data.borg.*)
├── cloudbeaver/    # CloudBeaver DB admin UI container (raw oci-containers, Law 5 exception)
└── couchdb/        # CouchDB for Obsidian LiveSync
```

## Changelog
- 2026-09-21: `## Structure` corrected — `borg/` and `cloudbeaver/` were live but
  unlisted. Doc-only.
- 2026-08-28: Postgres cleanup across the cluster (e82ca994, 53e84228). The 54
  dead `$PSQL` post-start statements were deleted rather than repaired — `$PSQL`
  is unassigned in the pinned 15.x module, so every one failed
  command-not-found under a swallowing `|| true` — and the roles they were
  hiding are now declared by the module that uses them: `eric` here in
  `databases/`, `immich` in `domains/media/immich-container`, `business_user` in
  `domains/business/databases`. Details and the not-declared-and-not-a-gap list
  (n8n, the youtube pair) live in `databases/README.md`.
- 2026-08-26: Backup jobs split one concern each and the failure-notifier list
  stopped naming units that do not exist (85b60856).
- 2026-08-16: `storage/` — the cleanup sweep no longer eats live download state
  (41371d7e); see `storage/README.md`.
- 2026-07-11: Law 3 sweep — syncthing's `dataDir` and backup's `mountPoint` come
  from `hwc.paths.*` instead of literals.
- 2026-07-06: Boot-race fixes in `databases/` (postgres gains a wait-for-gateway
  `ExecStartPre`; redis-main retries until the podman gateway IP exists) and the
  gotify stack removed from `backup/` with the rest of its decommission.
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.
- 2026-06-09: Law 3 finish — databases per-DB backup outputDir default derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-04-12: Add syncthing module (hwc.data.syncthing.*), extracted from machine configs
- 2026-03-18: Add CloudBeaver container for managing PostgreSQL databases, expanding data infrastructure capabilities.

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
