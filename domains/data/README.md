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
- 2026-07-06: Podman gateway boot-race fixes for the database services (`databases/`) — postgres gains a best-effort ExecStartPre that waits for the `10.89.0.1` bridge gateway before binding (it silently dropped the listen address on a boot where the gateway wasn't yet assigned, crash-looping paperless/firefly), and redis-main now retries (`Restart=on-failure`) until the gateway IP exists. Backup (`backup/`) lost its gotify branches in the notifications decommission (audit 2.6) — hwc-notify is now the sole alert path.
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.
- 2026-06-09: Law 3 finish — databases per-DB backup outputDir default derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-04-12: Add syncthing module (hwc.data.syncthing.*), extracted from machine configs
- 2026-03-18: Add CloudBeaver container for managing PostgreSQL databases, expanding data infrastructure capabilities.

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
