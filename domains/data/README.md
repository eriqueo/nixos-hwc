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
├── databases/      # PostgreSQL / Redis management
├── backup/         # Rsync backup automation (retired on server; borg is primary)
├── borg/           # Borg backup job: local repo or SSH remote (hwc.data.borg.*)
├── storage/        # Storage mount management
├── syncthing/      # Bidirectional file sync over Tailscale
└── couchdb/        # CouchDB for Obsidian LiveSync
```

## Changelog
- 2026-09-25: Retired `cloudbeaver/` (service-split audit: 0 requests in the 9 days of vhost logs; Eric: no longer used). Workspace archived to hwc-server `/var/lib/backups/service-split-wave3/cloudbeaver.tar.zst` before deletion.
- 2026-09-25: `databases/` — the primary user's role now declares `ensureClauses.superuser = true`. The module already assumed `eric` was a superuser (hand-made on hwc-server); hwc-work's cluster had created it without, which would have broken cross-database reads (crm → lead_scout/umami, gateway → umami) after the service split.
- 2026-09-25: Borg remote repositories are implemented, not "future". `hwc.data.borg.repo.remote.{enable,path,sshKeySecret}` swap the SSH URL in for the local path across the job, the `borg-hwc`/`borg-list`/`borg-restore` wrappers, `break-lock`, and `borg check`; the URL is kept out of `ReadWritePaths`. `BORG_RSH` carries the agenix key when one is named. First consumer: hwc-work pushing `/var/lib/hwc` and its `pg_dumpall` to the server's `/mnt/backup/borg-hwc-work` through a restricted `services.borgbackup.repos` user. Server behaviour unchanged (local path, same drv inputs apart from the new BORG_RSH env on borg-check).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.
- 2026-06-09: Law 3 finish — databases per-DB backup outputDir default derives from `hwc.paths.user.home`. Drv hash unchanged.
- 2026-04-12: Add syncthing module (hwc.data.syncthing.*), extracted from machine configs
- 2026-03-18: Add CloudBeaver container for managing PostgreSQL databases, expanding data infrastructure capabilities.

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
