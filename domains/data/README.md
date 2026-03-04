# domains/data/ — Data Infrastructure Domain

## Purpose

Consolidates all data infrastructure: databases (PostgreSQL), backup (rsync/borg),
storage (mount management), and CouchDB (Obsidian LiveSync).

## Boundaries

- Owns: database services, backup automation, storage mounts, CouchDB
- Does NOT own: application-level data (that belongs to the apps using these services)

## Structure

```
data/
├── index.nix       # Domain aggregator
├── README.md       # This file
├── databases/      # PostgreSQL management
├── backup/         # Rsync + Borg backup automation
├── storage/        # Storage mount management
└── couchdb/        # CouchDB for Obsidian LiveSync
```

## Changelog

- 2026-03-04: Namespace migration hwc.server.{databases,storage,native.backup,native.couchdb} → hwc.data.*
- 2026-03-04: Created data domain; moved databases, backup, storage, couchdb from domains/server/ (Phase 5 of DDD migration)
