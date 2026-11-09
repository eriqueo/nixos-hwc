# domains/business/firefly/

## Purpose

Firefly III personal finance manager running as a Podman container, with optional Firefly-Pico mobile companion app and a Workbench Finance explorer. Provides budgeting, transaction tracking, full-history recurring-payment review, and guarded transaction metadata edits.

## Boundaries

- **Manages**: Firefly III + Firefly-Pico containers, the Firefly Explorer Unix-socket service, env file generation from agenix secrets, DB grants, firewall rules
- **Does NOT manage**: PostgreSQL (→ `domains/data/databases/`), reverse proxy TLS termination (→ `domains/networking/`), secret declarations (→ `domains/secrets/`)

## Structure

Pico’s Alpine manifest pins APK tools and libapk2 together at 2.14.13-r0.

Core and Pico declare separate owned PostgreSQL roles and read protected
password environment files. The data capability provisions them before startup.
Core atomically publishes the existing APP_KEY/cron environment file at0600;
OAuth keys, encryption keys and current financial data stay in place.

`native-runtime-sources.json` and `native-build-packages.json` pin upstream
sources and acquisition-verified Debian build dependencies.
`pico-python-vendor-packages.json` pins two upstream wheels.
`pico-python-vendor.py` replaces those vendored libraries and checks supervisor
imports and archive traversal containment. `pico-frontend-cache.mjs` seeds the
fixed npm cache; `pico-frontend-test.mjs` exercises the calculator.
`native-runtime-build.sh` compiles and tests the libraries and the same PHP
version in an isolated build stage. The final stage removes the old ABI
libraries and copies only the new runtime binaries, libraries and provenance.


`pico-front-package*.json` own the locked frontend inputs. `index.nix` derives
the context’s `npm-packages.json` directly from the lock, so archive URLs and
integrity values have one source. `pico-frontend.patch` preserves default exports and supplies
named exports used by Nuxt auto-imports. The recipe rebuilds the real output
with network access disabled and removes build dependencies afterwards.


The three `*-composer.json` / `*-composer.lock` pairs define production-only
Composer inputs. `composer-runtime-packages.json` pins each changed dist archive
by URL and SHA256; `index.nix` rebuilds the offline cache. Install scripts and
plugins never run during builds, so build-time database migration is excluded.

Firefly runtime contexts include exact-hash Debian and Alpine package manifests.
The recipes install these vendor OS fixes offline before restoring the original
container user. No app or schema upgrade runs during the image build.

`parts/config.nix` persists the existing OAuth key pair under
`hwc.paths.state/firefly/oauth`, covered by the state backup. Startup refuses a
missing or mismatched pair before replacing the container. Seed the existing
keys before the first activation; replacing them invalidates existing tokens.

`index.nix` owns temporary same-app PHP runtime recipes for all three finance
containers. Core 6.6.6 and Importer 2.3.4 retain their application bytes and
configuration outside Composer inputs/vendor dependencies; the native build compiles PHP 8.5.12 against current ABI-matched libraries.
An immutable official Firefly donor supplies its configure options and matching
shared extensions. `system.build.fireflyCoreRuntimeImageContext` and
`system.build.fireflyImporterRuntimeImageContext` regenerate those contexts.
Pico retains app 1.10.1 and upgrades its 23 installed PHP82 packages together
to signed, fixed-hash Alpine 8.2.35-r0 packages in its offline context.

The Pico recipe also preserves its earlier security correction. It replaces
the actual `/usr/bin/node` with qualified Node 22.23.4 and supplies six signed,
fixed-hash Alpine packages for PHP's shared libraries and certificate stores.
Each OpenSSL/certificate release supplies both related package versions.
`system.build.fireflyPicoRuntimeImageContext` regenerates the offline build
context. Prebuild each recipe-derived local tag with `podman build --format=docker`
before deployment so the upstream health-check metadata is retained. The default
image has `pull = "never"`; startup fails if that image is absent.
Explicit image overrides remain available for compatible current-data recovery.
Remove this correction when a qualified upstream image passes the same runtime,
trust and current-data checks. Original finance services and data paths stay in place.

```
domains/business/firefly/
├── index.nix          # Option definitions + imports
├── sys.nix            # PostgreSQL database grants
├── README.md          # This file
└── parts/
    ├── config.nix     # Container definitions, storage, systemd deps, firewall, validation
    ├── automation.nix # firefly-cron + firefly-digest timers
    └── explorer.nix   # Root-only socket + hardened Workbench Finance service
```

## Namespace

`hwc.business.firefly.*`

## Configuration

```nix
hwc.business.firefly = {
  enable = true;

  images = {
    # Omit overrides to use the qualified local runtime images.
    # Explicit images remain available for compatible current-data recovery.
  };

  settings = {
    appUrl = "https://firefly.hwc.iheartwoodcraft.com";
    timezone = "America/Denver";
    locale = "en_US";
    trustedProxies = "**";          # Safe behind Tailscale
  };

  pico = {
    enable = true;                  # Enabled by default
    appUrl = "https://firefly-pico.hwc.iheartwoodcraft.com";
    fireflyUrl = "http://firefly:8080";  # Container-internal
  };

  explorer = {
    enable = true;
    appUrl = "https://firefly-explorer.hwc.iheartwoodcraft.com";
    assetAccountId = 12;
    accountName = "Dad - Checking";
    historyStart = "2019-08-19";
    allowedLogin = "eriqueo@github";
    patFile = "/run/agenix/firefly-explorer-pat";
  };

  database = {
    host = "10.89.0.1";            # media-network gateway
    port = 5432;
    name = "firefly";
    picoName = "firefly_pico";
    picoUser = "firefly_pico";
    picoPasswordSecret = "firefly-pico-db-env";
    user = "firefly";
    passwordSecret = "firefly-db-env";
  };

  storage = {
    dataDir = "/mnt/apps/firefly";
    uploadDir = "/mnt/apps/firefly/upload";
  };

  reverseProxy = {
    corePort = 10443;              # External TLS
    coreInternalPort = 8085;       # Internal HTTP
    picoPort = 11443;
    picoInternalPort = 8086;
  };

  network.mode = "media";

  resources.core = { memory = "1g"; cpus = "1.0"; };
  resources.pico = { memory = "512m"; cpus = "0.5"; };
};
```

## Dependencies

- **PostgreSQL** (`hwc.data.databases.postgresql.enable`) — auto-registers `firefly` and `firefly_pico` databases
- **agenix secret**: `firefly-app-key` (Laravel APP_KEY, written to env file at container start)
- **agenix secret**: `firefly-explorer-pat` (dedicated personal access token; `root:secrets`, mode `0440`)
- **media-network** — both containers join `media` Podman network by default

## Access

| Service | URL | Internal Port |
|---------|-----|---------------|
| Firefly III | `https://firefly.hwc.iheartwoodcraft.com` | 8085 |
| Firefly-Pico | `https://firefly-pico.hwc.iheartwoodcraft.com` | 8086 |
| Data Importer | `https://firefly-import.hwc.iheartwoodcraft.com` | 8087 |
| Workbench Finance | `https://firefly-explorer.hwc.iheartwoodcraft.com` | root-only Unix socket |

Firewall rules auto-open internal ports on `tailscale0` interface.

## Systemd Units

- `podman-firefly.service` — main Firefly III container (generates env file with APP_KEY + STATIC_CRON_TOKEN in preStart)
- `podman-firefly-pico.service` — Pico mobile companion (depends on firefly)
- `podman-firefly-importer.service` — data importer (CSV/SimpleFIN; stateless, OAuth client authorized per browser session)
- `firefly-cron.timer` — daily 03:10 hit on `/api/v1/cron/<token>` (recurring transactions, bill warnings, auto-budgets fire nowhere without this)
- `firefly-digest.timer` — daily 07:15 finance digest (balances, bills due 7d, yesterday's transactions) → hwc-notify `topic=finance` → #hwc-alerts. Skips with a journal note until a PAT exists at `/run/agenix/firefly-pat` (drop `firefly-pat.age` in `domains/secrets/parts/services/` to arm it).
- `firefly-explorer.socket` — `/run/firefly-explorer.sock`, `root:root` mode `0600`; only root-run Caddy can connect.
- `firefly-explorer.service` — immutable explorer package; validates its token, Firefly account, UI assets, and tailscaled socket before serving. Every API request is authorized with Tailscale WhoIs. Split groups remain read-only; writes are limited to existing category/expense-account ids and existing tags.

## Changelog

- 2026-11-09: Replace withdrawn Alpine APK tools 2.14.12 packages with the signed 2.14.13 pair and exact hashes. Regenerate Pico’s offline context and image identity.
- 2026-11-03: Declare restricted database ownership, protected password environment delivery and provisioning/rotation dependencies.

- 2026-11-02: Complete Core’s direct advisory repair with phpseclib 3.0.58 and
  Symfony Expression Language 8.1.9 plus compatible locked dependencies. Pin all
  six archive hashes and qualify parser depth rejection and X25519 consumption.

- 2026-11-02: Add ABI-matched PHP 8.5.12/libxml2 2.15.4/curl 8.23.0/ngtcp2
  1.25.0 source rebuilds with offline upstream tests, neutral build-stage INI and loopback-only local test name
  resolution in the network-isolated build.
  Rebuild Pico’s Nuxt output with fixed-hash npm inputs and the existing 1.10.1
  public version, repair its calculator
  and vendored Python archive libraries, and exercise their real consumers.
  Keep the existing app user’s provider cache and `/run` ownership after package
  updates, so first requests and the non-root Nginx PID file remain writable.
  Extend wiring checks to cover input hashes, build/test calls and startup guards.
  Exact app versions and serving configuration remain unchanged. Deployment is
  owned by the parent and does not occur in this checkout.

- 2026-11-02: Add fixed-hash signed-vendor OS package inventories and offline
  APT/APK installation to all three same-app finance contexts. Pin production
  Composer dependency repairs, replace `/usr/bin/composer` with 2.10.3, disable
  build scripts/plugins/network, and invalidate generated provider caches.
  Preserve the app versions, service metadata and original working directories.
  Wiring checks verify package hashes, offline installation and startup guards.
  Current-data qualification and live deployment remain separate.

- 2026-11-01: Persist the existing Core OAuth signing keys and check their pair
  before container startup, so runtime image replacement preserves API tokens.

- 2026-10-31: Keep the Importer optional when adding its runtime startup guard;
  the wiring check also evaluates the disabled service path.

- 2026-10-31: Add same-app PHP 8.5.12 runtime contexts for Core and Importer;
  extend Pico's offline context with PHP 8.2.35-r0 and every installed PHP82
  extension. All three default images fail closed when not prebuilt. App versions,
  data paths, credentials and schema code remain unchanged. Live activation is separate.

- 2026-10-23: Add same-app Pico Node/shared-library/trust correction with an
  immutable offline context and local-image startup guard. Private real-archive
  old/new/old preserves all 15 tables and the key; live activation is separate.
  Shared source release versions keep each package pair aligned.

- 2026-09-21: Pinned Explorer `0605857`: serve current HTML without conditional caching, since Nix-normalized mtimes can otherwise return stale 304 responses and reference removed JavaScript builds. Static asset caching, Tailscale API checks, and finance data are unchanged.
- 2026-09-16: Pinned Firefly Explorer fix `90a8a587`: tailscaled LocalAPI requires `Host: local-tailscaled.sock` even over its Unix socket. The original package used `localhost`, so the deployed authorization boundary failed closed with 403 for every API request. A Unix-socket regression test now watches the exact Host requirement.
- 2026-09-16: Added the Workbench Finance recurring-payment explorer from the revision-locked private `pnc-statement-pipeline` flake. The default report scans Firefly history from 2019-08-19; date controls filter visible occurrences without narrowing cadence/status analysis. Caddy reaches it only through a root-owned `0600` Unix socket, API reads require the configured Tailscale identity, and exact-fingerprint writes are limited to one journal's existing category, expense account, or tags. Added a dedicated encrypted PAT instead of sharing the digest token.
- 2026-09-15: Pinned Firefly III core 6.6.6, the minimum compatible release line for data-importer 2.3.4; importing had been blocked because core 6.4.22 was below the importer's required 6.6.0. OAuth clients and tokens must be recreated after this upgrade.
- 2026-07-13: Automation build-out — `firefly-cron-token` secret + daily cron timer, `firefly-importer` container + `firefly-import` vhost (:8087), `firefly-digest` timer posting to hwc-notify (`finance-to-alerts` route), PAT-gated until `firefly-pat.age` is provisioned.

- 2026-06-09: Access moved from dedicated tailnet ports (Firefly `:10443`, Pico `:11443`) to name-based vhosts `firefly.hwc.iheartwoodcraft.com` / `firefly-pico.hwc.iheartwoodcraft.com` under the shared `*.hwc.iheartwoodcraft.com` wildcard cert (no per-service listener / firewall hole). Both `appUrl`s updated to match — Firefly's `APP_URL` and Pico's app URL must equal the browser origin. See `domains/networking/README.md`.
- 2026-03-25: Created README per Law 12
- 2026-03-04: Namespace migration hwc.server.containers.firefly → hwc.business.firefly
