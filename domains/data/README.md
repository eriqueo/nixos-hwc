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
├── backup/         # Rsync + local backup automation
├── borg/           # Borg repository, integrity checks, CLI tools
├── cloudbeaver/    # CloudBeaver DB admin UI (raw container, Law 5 exception)
├── storage/        # Storage mount management + cleanup sweep
├── syncthing/      # Bidirectional file sync over Tailscale
└── couchdb/        # CouchDB for Obsidian LiveSync
```

## Changelog
- 2026-08-28: **Postgres grants audit.** 54 dead `$PSQL` statements were deleted
  across ten modules (`$PSQL` is undefined in the generated post-start script and
  `|| true` swallowed the command-not-found, so none ever ran), and the roles they
  were hiding are now declared by the modules that use them. `eric` is declared
  once here in `databases/` — one producer per fact. The full audit, including why
  `postStart` was always the wrong unit, lives in `databases/README.md`
  (`e82ca994`, `53e84228`). Same day: brainvec checkout refresh fixed and its drift
  exposed (`4845a1df`).
- 2026-08-26: `backup/` — `postgresql-db-backup` retired and the two jobs that
  dumped one concern split; part of the sweep that found the monitoring notifier
  list naming seven units that do not exist. Those phantom names did not no-op:
  the `listToAttrs` generated unit files carrying only `OnFailure=` and no
  `ExecStart`, which systemd rejects as `bad-setting` while the list read as
  coverage (`85b60856`).
- 2026-08-16: `storage/` — the cleanup sweep stopped eating live download state.
  `${hot.downloads}/incomplete` (qBittorrent's TempPath) left the default
  `cleanup.paths`, and both `find` calls gained `-mindepth 1` so an emptied path
  no longer deletes its own root — the source of slskd's link-count-0 inode. The
  admission rule ("scratch only; no running service may own the contents") is now
  in the option description (`41371d7e`).
- 2026-07-11: Law 3 — syncthing `dataDir` and backup `mountPoint` derive from
  `hwc.paths.*` instead of hardcoded absolutes (`24d869b5`).
- 2026-07-06: `databases/` boot-race fixes against the podman gateway `10.89.0.1`,
  which only exists once the first attached container starts. Postgres gained a
  best-effort `ExecStartPre` (≤120s, exits 0 on timeout) because it silently drops
  a missing listen address rather than failing — it came up loopback-only after
  the 2026-07-06 boot and paperless crash-looped 17k+ times until a manual restart
  (`d2e74a97`). `redis-main` does fail, so it got `Restart=on-failure` +
  `RestartSec=5s` + `StartLimitIntervalSec=0` instead (`1474884a`). The gotify
  decommission removed this domain's gotify branches from the backup job;
  auto-restart and Slack/webhook paths are intact (`c3440a16`).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.
- 2026-06-09: Law 3 finish — databases per-DB backup outputDir default derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-04-12: Add syncthing module (hwc.data.syncthing.*), extracted from machine configs
- 2026-03-18: Add CloudBeaver container for managing PostgreSQL databases, expanding data infrastructure capabilities.

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
