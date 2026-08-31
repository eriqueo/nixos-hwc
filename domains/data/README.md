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
└── couchdb/        # CouchDB for Obsidian LiveSync
```

## Changelog
- 2026-08-28: **Postgres `postStart` audit.** `databases/index.nix` gained
  explicit `ensureUsers` declarations after 54 dead `$PSQL` statements were
  deleted repo-wide — `$PSQL` is undefined in the generated post-start script
  and `|| true` swallowed every command-not-found (`e82ca994`). The follow-on
  claimed the roles and databases those dead grants had been hiding — `eric`
  here, `immich` and `business_user` in their own modules (`53e84228`).
  `databases/README.md` now records why `postStart` was always the wrong unit
  (it is ordered *before* `ensureDatabases`/`ensureUsers` run, and its
  `ExecStartPost` failure would take postgresql and every dependent down), plus
  the known gaps left undeclared on purpose. `4845a1df` refined the same file
  during the brainvec checkout-refresh work.
- 2026-08-26: `backup/` — `postgresql-db-backup` retired; the per-database
  backup job and its `parts/local-backup.nix` registration were removed after
  the audit found the failure-notifier list naming units that do not exist and
  two jobs conflating separate concerns (`85b60856`). Postgres is still covered
  by the borg pre-hook's nightly `pg_dumpall` into `/var/lib/backups`.
- 2026-08-16: `storage/` — the cleanup sweep no longer eats live download state
  (`41371d7e`).
- 2026-07-11: Law 3 — syncthing's `dataDir` and the backup `mountPoint` now
  derive from `hwc.paths.*` instead of hardcoded strings (`24d869b5`).
- 2026-07-06: `databases/` — postgres and `redis-main` gained
  `ExecStartPre`/retry guards for the podman gateway `10.89.0.1` boot race
  (`d2e74a97`, `1474884a`). Gotify stack decommissioned domain-wide
  (`c3440a16`).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.
- 2026-06-09: Law 3 finish — databases per-DB backup outputDir default derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-04-12: Add syncthing module (hwc.data.syncthing.*), extracted from machine configs
- 2026-03-18: Add CloudBeaver container for managing PostgreSQL databases, expanding data infrastructure capabilities.

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
