# domains/data/databases/

## Purpose

Foundational database services (PostgreSQL, Redis, InfluxDB) used by both containers and native services. Provides shared data persistence layer for server workloads.

## Boundaries

- **Manages**: PostgreSQL (with pgvector), Redis cache, InfluxDB time-series, backup scheduling
- **Does NOT manage**: Application-specific database schemas (→ respective service modules), application permission policy (→ service modules; this capability applies it), backup storage location (→ machine config)

## Structure

```
domains/data/databases/
├── index.nix           # Options + implementation (PostgreSQL, Redis, InfluxDB, backups)
├── application-roles.py # Bounded, transactional credential/owner reconciliation
└── README.md
```

The Python boundary decodes credential tags into separate raw/environment types
and verifies its closed encoding enum against the generated Nix contract.

## Configuration

```nix
hwc.data.databases = {
  postgresql = {
    enable = true;
    version = "15";
    databases = [ "immich" "paperless" "n8n" ];

    # Extensions (default: none). Server enables pgvector + vectorchord for Immich.
    extensions = ps: [ ps.pgvector ps.vectorchord ];
    sharedPreloadLibraries = [ "vchord" ];

    # Podman media-network integration: 10.89.0.1 listener, container auth,
    # init-media-network ordering. Leave disabled on machines without Podman.
    containerNetwork.enable = true;

    # Full database dump (pg_dumpall)
    backup.enable = true;
    backup.schedule = "daily";

    # Per-database compressed backups with retention
    backup.perDatabase = {
      enable = true;
      databases = [ "hwc" "n8n" ];           # Specific DBs to backup
      outputDir = "/home/eric/backups/postgres";  # Default
      compress = true;                        # gzip compression (default)
      retentionDays = 30;                     # Auto-delete old backups (default)
      schedule = "*-*-* 02:30:00";            # 2:30 AM daily (default)
      user = "eric";                          # User with DB access (default)
    };
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
- **Extensions** (opt-in via `extensions`): server uses pgvector + vectorchord for Immich
- **Network access**: localhost only by default; `containerNetwork.enable = true` adds 10.89.0.1 + 10.89.0.0/16 auth

## Backup Services

| Service | Type | Output | Schedule | Status |
|---------|------|--------|----------|--------|
| `postgresql-backup` | pg_dumpall | `${paths.backup}/postgresql-YYYYMMDD.sql` | Configurable | available |
| `postgresql-db-backup` | Per-DB pg_dump | `~/backups/postgres/<db>_YYYY-MM-DD.sql.gz` | 2:30 AM daily | **disabled on hwc-server** |

**Where the real backup comes from.** Neither service above is what protects
hwc-server's databases. The borg job's own pre-hook (`machines/server/config.nix`,
`preBackupScript`) runs `pg_dumpall` into `/var/lib/backups`, which IS a borg
source — so every database lands in a deduplicated off-drive archive nightly.
Check there before concluding a database is unprotected:

```
zcat /var/lib/backups/postgresql-<date>.sql.gz | rg '^CREATE DATABASE'
borg list ::<archive> | rg 'var/lib/backups/postgresql'
```

`postgresql-db-backup` was disabled on 2026-08-26 (Law 15: one mechanism per
backup concern). It covered 3 of 14 databases and wrote to
`/home/eric/backups/postgres`, which is in no borg source — 445 MB sitting on
the drive whose loss it existed to survive. The module still works and can be
re-enabled; if you do, point `outputDir` at a path borg actually carries.

## Authentication and application roles

`authenticationMode = "peer-scram"` uses OS peer identity on Unix sockets and
SCRAM on loopback and the enabled Podman bridge. Home enables it after Immich's
actual password-file client and MCP socket client qualification. Work and laptop
retain the annotated `legacy-trust` mode while their clients are migrated under
the domain-exposure-review project; this is not a fleet completion claim.

Application modules declare `applicationRoles.<role>` with exactly one credential
source (`password` or `environment`) and authority (`owned` or `shared`). Owned
roles match their database name. Shared roles receive exact table-column grants
and sequence usage, without owning shared tables. The helper removes that role's
excess direct column, table, routine, schema and default grants. It refuses
unexpected ownership, memberships, authority in another database, PUBLIC schema
creation or callable application security-definer functions.

The data capability owns the schemaVersion2 configuration/limits contract and
restricted role declaration. Systemd loads protected credentials after native
PostgreSQL setup. Each database transaction includes its role password, bounded
application-owned preparation SQL, grants and ownership changes. Matching SCRAM
verifiers keep their salt. Limits are16roles,8owned schemas,32shared tables,
64columns per privilege,4096SQL operations,16KiB per credential and64KiB trusted
preparation SQL. Exceeding a limit rolls back and fails; no retry loop runs.
Extension membership in pg_class and pg_type, unrelated databases and peer admin
authority remain outside owner reconciliation.

Native modules register `localPeerRoles` and consume `peerEnvironmentFor`.
PGHOST/PGPORT/PGUSER plus an empty-host DATABASE_URL work with postgres.js,
node-postgres and libpq; the URI `?host=` form does not work with postgres.js.
`localPeerEnvironment` also binds intentional primary-user clients to the socket.
Each peer app waits for postgresql-setup. Application units depend on the role
operator and restart with its tool. Its tool identity includes every consumed
ciphertext revision, so rotating one credential cannot strand another requiring
client after the shared operator restarts.

The helper is a service payload beside `index.nix`, which retains the options and
Nix wiring. It provides one executable SQL/credential boundary for actual private
PostgreSQL qualification and production; embedding it in Nix would hide that seam.
Secrets and databases are CRITICAL and backed up by their existing agenix/Git and
Borg owners. The operator creates no persistent file or second backup mechanism.

## Historical access audit (2026-08-28)

The following describes the old trust model and why its dead grants were removed.
It does not describe the repaired home authentication path.

### Read this before adding a GRANT

**There is no privilege system here to speak of, and that is deliberate.** Three
facts, each measured on the live cluster 2026-08-28:

1. **`pg_hba.conf` opens with `local all all trust`**, followed by `trust` for
   `127.0.0.1/32`, `::1/128` and `10.89.0.0/16` (the podman bridge). The first
   matching rule wins, so **every local and every container connection may assume
   any role without a password.** The `md5` rules below those lines are
   unreachable.
2. **`eric` is a Postgres superuser** (`rolsuper = t`), and a superuser bypasses
   every privilege check.
3. **`eric` owns every table** in `datax_monitor`, `firefly`, `firefly_pico`
   and `paperless` — 6, 81, 15 and 68 tables respectively. `hwc` is mixed:
   `eric` owns 10 tables and `postgres` owns 31. This ownership is additional
   evidence for four databases, not part of the general access invariant;
   `eric`'s superuser status is what makes the deleted grants redundant across
   all five.

So a `GRANT … TO eric` is a no-op at least twice over everywhere (trusted
authentication plus superuser), with ownership supplying a third reason for
the objects Eric owns. This matches the standing single-user exception in
`~/.claude/engineering-principles.md` (Principle 5): isolation here comes from
the machine boundary, not from in-database roles.

**Who connects as what:**

| Database | App connects as | Database owner | Objects owned by |
|---|---|---|---|
| `hwc`, `datax_monitor` | `eric` | `eric` | `eric` |
| `firefly`, `firefly_pico` | `eric` | `postgres` | `eric` |
| `paperless` | `eric` | `postgres` | `eric` |
| `immich` | `immich` | `immich` | `immich` |
| `authentik` | `authentik` | `authentik` | `authentik` |
| `umami` | `umami` | `umami` | `umami` |
| `lead_scout`, `home_scout`, `research_scout` | own role | own role | own role |

**Declare roles with `services.postgresql.ensureUsers`. Never script SQL into
`systemd.services.postgresql.postStart`.** Two reasons, both structural:

- `postgresql-setup.service` is ordered `After=postgresql.service`, so `postStart`
  runs **before** `ensureDatabases` and `ensureUsers` have created anything. On a
  fresh cluster every statement targets a database that does not exist yet.
- `ExecStartPost` reports `ignore_errors=no`. A non-zero exit there fails
  `postgresql.service` and takes every dependent service down with it. That is why
  the old statements all ended in `|| true` — and why they were invisible.

### The 2026-08-28 audit — 54 dead statements

Ten modules wrote `postgresql.postStart`. The generated script held **58
variable-invoked `psql` call sites: 54 used `$PSQL`, which is never assigned
anywhere in the script.** Older nixpkgs `postgresql` modules defined that
variable; the pinned 15.x module does not. Each line expanded to `-c "…"`, failed
command-not-found, and `|| true` swallowed it. `set -e` cannot help, because
`|| true` is precisely the construct that disarms it.

Spread of the dead statements: immich 15, firefly 16, paperless 8, authentik 5,
`hwc` 4, datax_monitor 3, the three scouts 3. The only working block was
`umami`'s, which assigns its own `UMAMI_PSQL` to an absolute `psql` path — the
fossil of someone hitting this bug and repairing one call site.

**They were deleted, not repaired.** Repairing them would have applied 54 grants
for the first time, and every one grants access the grantee already has. One
exception was load-bearing: authentik's `CREATE ROLE`, whose failure meant a
rebuilt cluster would have had the `authentik` database and no `authentik` role.
That one became `ensureUsers` with `ensureDBOwnership`.

Verify the repair by reading the **generated** script, never the Nix source:

```
systemctl cat postgresql.service | rg ExecStartPost
rg -o '^\s*\$[A-Z_]+ ' <that store path> | sort | uniq -c   # expect only $UMAMI_PSQL
rg -n '^\s*\$PSQL ' domains machines profiles               # expect 0 hits
```

### Drift the dead code was masking — closed 2026-08-28

Deleting the dead statements exposed roles and databases that live on hwc-server
and were declared nowhere. A rebuilt cluster would not have reproduced them.

**Closed.** Each was claimed by the module that uses it:

| Name | Claimed by | Declaration |
|---|---|---|
| `eric` role | `domains/data/databases/index.nix` | `ensureUsers`, no ownership |
| `immich` role + database | `domains/media/immich-container/parts/config.nix` | `ensureUsers` with `ensureDBOwnership` (reproduces live state — `immich` already owns it) |
| `business_user` role | `domains/business/databases/index.nix` | `ensureUsers`, no ownership — `schema.sql:772-774` grants to it by name |
| `authentik` role | `domains/system/core/authentik/parts/config.nix` | `ensureUsers` with `ensureDBOwnership` |

**Current correction to the historical n8n audit.** n8n's own state is SQLite,
but the PostgreSQL role is an active client: the2026-11-03 live census found two
stored PostgreSQL credentials used by ten nodes against six public tables in hwc.
The module now declares that shared authority and updates only those credential
IDs. This does not make the leftover n8n database its application store.
Repository searches found no youtube_transcripts/youtube_videos consumer; that
search is not authority to drop their retained data.

## Consumers

- `domains/media/immich-container/` - PostgreSQL + Redis
- `domains/business/paperless/` - PostgreSQL + Redis
- `domains/business/firefly/` - PostgreSQL
- `domains/business/databases/` - PostgreSQL (hwc database — see that module's README for schema docs)
- n8n workflows use PostgreSQL nodes for application databases, but n8n's own
  state is SQLite; the leftover `n8n` database is not its configured store.

## Changelog
- 2026-11-03: Represent decoded credential sources as distinct types, without nullable fields standing in for a variant.
- 2026-11-03: Add versioned owned/shared role authority, environment credential decoding, explicit native peer environments and cross-client rotation wiring. Correct the historical claim that the n8n PostgreSQL role had no consumer.
- 2026-11-03: Keep the native postgres OS-account peer map and replace the complete composed HBA rule set, including unreachable appended md5 defaults.
- 2026-11-03: Add peer/SCRAM mode and protected, bounded per-app role provisioning; scope owner changes to declared database schemas and preserve extension members.

- 2026-08-28: Corrected the access audit after a live owner census: `hwc` has 10 `eric`-owned and 31 `postgres`-owned tables; superuser access, not blanket object ownership, is the general reason the deleted grants were redundant. Clarified that n8n's own store is SQLite even though workflows access other PostgreSQL databases.
- 2026-07-06: postgresql: add a best-effort `ExecStartPre` that waits (≤120s, exits 0 on timeout) for the podman gateway `10.89.0.1` before start. Same boot race as redis-main, but postgres does NOT fail when the address is absent — it starts localhost-only and silently drops the missing listen address, so `Restart=on-failure` can't heal it. The 2026-07-06 boot left postgres 127.0.0.1-only; paperless crash-looped (17k+ "connection refused", 0 successful starts) and firefly errored all morning until a manual restart rebound `10.89.0.1`. net-only containers (jellyfin/sonarr/qbittorrent) bring the bridge up independently, so the wait can't deadlock against postgres-dependent containers.
- 2026-07-05: redis-main: add `Restart=on-failure` + `RestartSec=5s` + unlimited start burst. Ordering on init-media-network is insufficient — the podman gateway IP (10.89.0.1) only appears when the first attached container starts; the 2026-07-05 reboot left redis dead on a one-shot bind failure.
- 2026-05-22: Promoted `package` to an option (default `postgresql_15` for server cluster safety). Assertion now checks `version` vs `package.version` for drift instead of hardcoding 15.x. Laptop runs v17, server stays on v15. Added tmpfiles rule for custom `dataDir` (NixOS module only auto-creates the default `/var/lib/postgresql`).
- 2026-05-22: Gated Podman-specific behavior behind `containerNetwork.enable`; promoted `extensions` and `sharedPreloadLibraries` to options so non-Podman hosts (laptop) can run a vanilla local dev DB.
- 2026-03-23: Added `backup.perDatabase` for compressed per-database backups with retention
- 2026-02-27: Migrated from server/native/networking/ per Law 2 namespace compliance
