# domains/data/borg/

## Purpose

Borg deduplicating encrypted backup service. Provides block-level deduplication, client-side encryption (repokey-blake2), automatic pruning with configurable retention, and pre/post backup hooks for database dumps.

## Boundaries

- **Manages**: Borg backup jobs, repository integrity checks, CLI wrapper scripts, retention pruning
- **Does NOT manage**: rsync/cloud backups (→ `domains/data/backup/`), backup source directories

## Structure

```
domains/data/borg/
├── index.nix          # Options, shared snapshot/jobs, optional independent SSH destinations, CLI tools
├── sqlite-snapshot.py # Readonly application-user copy and private atomic publication
└── README.md          # This file
```

## Namespace

`hwc.data.borg.*`

## Configuration

```nix
hwc.data.borg = {
  enable = true;

  repo.path = "/mnt/backup/borg";

  sources = [ "/home" "/var/lib/data" ];
  excludePatterns = [ "/nix" ".cache" "node_modules" "__pycache__" ];

  encryption = {
    mode = "repokey-blake2";
    passphraseSecret = "borg-passphrase";   # agenix secret name
  };

  compression = "auto,zstd";

  schedule = {
    frequency = "daily";
    timeOfDay = "03:00";
    randomDelay = "1h";
  };

  retention = {
    daily = 7;
    weekly = 4;
    monthly = 6;
    yearly = 0;
  };

  monitoring.enable = true;
  notifications.onFailure = true;
};
```

## CLI Tools

| Command | Description |
|---------|-------------|
| `borg-hwc` | Wrapper with passphrase pre-loaded (`borg-hwc list`, `borg-hwc info`, etc.) |
| `borg-list` | Show recent archives and repository info |
| `borg-restore <archive> <target> [path]` | Restore files from an archive |
| `borg-backup-now` | Trigger manual backup immediately |
| `borg-sqlite-snapshot create ...` | Bounded online SQLite snapshot; installed when configured |

## SQLite recovery

`sqliteSnapshots.<name>` declares `source`, `user`, `maxBytes` (8 GiB default)
and `timeoutSeconds` (600 default). The base role binds T3 on Borg-enabled hosts.
The application user reads the live database through SQLite's online backup API.
The caller validates its own private copy, then publishes it atomically at
`${hwc.paths.state}/borg-sqlite/ready/<name>.sqlite`. Borg includes that file
and excludes the exact raw database, WAL and SHM paths. Other userdata, including
pairing keys and attachments, remains covered.

These files are CRITICAL backed-up data. There is one last-good snapshot per
name and one bounded staging slot. A failed snapshot aborts the archive and keeps
the previous published file. An unknown surviving worker or unexpected staging
content holds the slot. Inspect the failed unit and exact slot before recovery;
do not purge staging or retry blindly. The worker has a deadline and a 64-event
busy ceiling with jitter. Publication requires space for two maximum-size copies
plus 1 GiB headroom. Older raw-file archives are unchanged and may be inconsistent.

Restore the archived `ready/<name>.sqlite` in private disposable state first.
Check SQLite integrity and required application records before an offline restore.
Never overlay it onto a running application's database.

## Independent destinations

`additionalDestinations.<name>` adds an encrypted SSH repository without changing
`hwc-backup` or its historical archive prefix. No machine enables one by default.
Declare `host`, `repository` (absolute remote path), `hostKey` (ed25519 public key),
`sshKeySecret`, `passphraseSecret`, `startAt` (systemd calendar), and optionally
`user` (default `borg`). Each destination needs its own declared SSH identity and
encryption secret; the secret mounts use root:secrets mode 0440. Systemd LoadCredential gives the job a private SSH identity, read through CREDENTIALS_DIRECTORY.

Generated native units are `borgbackup-job-hwc-backup-<name>.service` and timer.
They share source/exclusion lists, snapshot producers, compression and retention.
They inherit application-provided snapshot write paths, but cannot write the
primary repository. Each has an independent failure status/notification and the
existing 12-hour job deadline. SSH pins the declared host key, allows only the
chosen identity and has connection/liveness deadlines. This interface supports
at most four safe, unique destinations. Repository data is AUTO-MANAGED through
the inherited prune/compact policy; provision and test a server-side quota too.

When destinations exist, all native backup jobs hold one per-host lock through
snapshot publication, archive creation and completion. A contender fails after
300 seconds; it never scans a snapshot while another archive is reading it.
An empty map retains the original primary hook and permissions. Existing manual
snapshot writers must respect this lock before offsite activation.

This is source support, not a production offsite deployment. Before enabling it,
verify seed/catch-up timing, remote quota enforcement, independent key recovery,
remote integrity checks, and file/database restores. Interactive primary wrappers
and `borg-check` continue to refer to the primary repository. Each enabled additional
destination has `borg-check-<name>` and a timer using the same pinned SSH identity.
These perform repository consistency checks, not full cryptographic verification.
Additional SSH operations require systemd credential delivery; invoking the generated
Borg wrapper alone does not load its private identity.

## Dependencies

- **agenix secret**: `borg-passphrase` (repository encryption passphrase)
- **Alerts** (optional): failure notifications via `hwc-service-failure-notifier`

## Systemd Units

- `borgbackup-job-hwc-backup.service` / timer — scheduled Borg backup
- `borg-check.service` / `borg-check.timer` — weekly primary consistency check
- `borg-check-<name>.service` / timer — additional destination consistency checks

## Changelog
- 2026-10-23: Add per-destination consistency services/timers with bounded repository locking and shared private SSH credentials.
- 2026-10-23: Deliver additional SSH identities through private systemd credentials from standard root:secrets 0440 agenix mounts. Refuse missing credential delivery before SSH.
- 2026-10-23: Add disabled-by-default independent SSH destinations with pinned host keys, dedicated credentials, native per-target jobs/timers and bounded snapshot/archive serialization. Preserve primary identities and application snapshot permissions.
- 2026-10-16: Add bounded readonly SQLite online snapshots, private validation and atomic publication. Derive archive paths and exact raw-file exclusions from one map. Preserve other userdata and fail before Borg on producer errors. Exercise actual rendered hooks and archive extraction with wiring mutations.
- 2026-09-26: Share configured-version PostgreSQL dumps across hosts; fail closed and publish atomically. Preserve restore errors, wait for locks, and keep nested recovery archives outside daily dump cleanup.

- 2026-04-04: Update failure notification ref from `hwc.alerts.enable` to `hwc.monitoring.alerts.enable` (domain redistribution)
- 2026-04-03: Fix backup timeout — increase to 12h (compact on 240GB repo), raise compact threshold to 25%, exclude regenerable Prometheus/Jellyfin data
- 2026-03-25: Created README per Law 12
