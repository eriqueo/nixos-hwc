# domains/notifications/notify — hwc-notify

Hexagonal TypeScript notification dispatcher. Replaces the n8n `home:admin:alert-manager` workflow and the per-script CLI senders (`hwc-gotify-send`, `hwc-webhook-send`, `hwc-smartd-notify`, …) with one service that:

- Validates every inbound message against a Zod schema at the boundary.
- Routes per-notification through a declarative table.
- Delivers via pluggable channel adapters (Discord + SMTP today; Gotify / Slack / iGotify slots ready when needed).
- Records every dispatch + per-channel result in a SQLite audit log.
- Breaks the circuit per channel after 5 consecutive failures (60s cool-down + one half-open probe).
- Exposes the whole surface over HTTP, a `hwc-notify` CLI, and the `hwc_notify` MCP tool.

**Namespace**: `hwc.notifications.notify.*` (Charter Law 2 — namespace = folder).

**Status**: production. Alertmanager has been cut over (2026-05-31); the n8n alert-manager workflow is deactivated but preserved as the rollback path.

## Why

On 2026-05-31 the existing n8n alert-manager workflow had been silently failing for a full day — every alert errored on a stale `ntfy` URL and no one noticed because the workflow's own failures weren't audited anywhere. Replacing it required:

- A schema-validated contract at every shell (HTTP / CLI / MCP).
- Channels as data, not nodes in a flowchart, so adding a Discord channel is one line of Nix.
- An audit log that records what we **tried** to deliver and what actually went out.
- Circuit breakers so an external outage doesn't turn every alert into a 30-second timeout.

See `~/.claude/plans/hashed-snacking-crab.md` for the full design rationale and the multi-phase restructure plan.

## Architecture (hexagonal)

```
                              ┌────────────────┐
   Alertmanager ──▶ /webhook/alertmanager ─┐   │   ┌─▶ Discord (channel-discord)
                                            │   │   │
   curl POST /notify ────────────────────────┤  core │
                                            │  ────  ├─▶ SMTP / Proton Bridge (channel-smtp)
   hwc-notify CLI ───────────────────────────┤  router│
   hwc_notify MCP tool ──────────────────────┘ dispatch│ ┌─▶ … (future adapters)
                                                 ┌────┘ │
                                                 ▼      │
                                            SQLite audit log
                                            CircuitBreaker (in-mem)
```

Inbound (**shells**) translate external requests into the canonical `Notification` shape; **core** is pure (types, routing, dispatch, circuit logic); **outbound adapters** implement the `Channel` port. Swapping Discord for Slack is a new adapter file + a Nix data row — no core change.

## File layout

```
notify/
├── README.md                # This file.
├── index.nix                # Charter Law 6 module (OPTIONS / IMPL / VALIDATION).
└── parts/
    ├── channels.nix         # Default channel registry (data).
    ├── routes.nix           # Default routing rules (data).
    └── src/                 # TypeScript service.
        ├── package.json     # type=module, zod + nodemailer runtime deps.
        ├── tsconfig.json    # ES2023, NodeNext, strict, declaration false.
        └── src/
            ├── main.ts                          # Entry — HTTP server, wiring.
            ├── config.ts                        # Late-binding env loader.
            ├── core/
            │   ├── types.ts                     # Notification, DeliveryResult, DispatchResult.
            │   ├── dispatch.ts                  # Pure: notification × channels[] → result.
            │   ├── router.ts                    # Pure: route(notif, rules, defaults).
            │   ├── circuit.ts                   # CircuitBreaker (in-memory).
            │   ├── from-alertmanager.ts         # Pure: Alertmanager payload → Notifications.
            │   └── errors.ts                    # Structured NotifyError + codes.
            ├── ports/
            │   ├── channel.ts                   # Outbound Channel interface.
            │   ├── audit.ts                     # AuditLog interface.
            │   └── log.ts                       # Logger interface.
            ├── adapters/
            │   ├── channel-discord.ts           # Discord webhook embed.
            │   ├── channel-smtp.ts              # nodemailer / Proton Bridge.
            │   ├── channel-logonly.ts           # Dev / fallback.
            │   ├── audit-sqlite.ts              # node:sqlite (Node 22 built-in).
            │   ├── audit-noop.ts                # Disabled-mode AuditLog.
            │   └── log-stderr.ts                # Structured JSON to stderr.
            └── schemas/
                ├── notification.ts              # Lenient input + canonical Zod.
                ├── runtime-config.ts            # channels + routes JSON contract.
                └── alertmanager.ts              # AM webhook v4 schema.
```

## Runtime

Hermetic Nix-built derivation via `pkgs.buildNpmPackage`. `nixos-rebuild` runs `npm ci` offline against a hash-pinned `package-lock.json`, then `npm run build` (tsc → `dist/`). The output is a single Nix store path containing the compiled JS + a populated `node_modules/`.

The systemd unit's `ExecStart` is:

```
node --experimental-sqlite --no-warnings ${pkg}/lib/node_modules/hwc-notify/dist/main.js
```

`--experimental-sqlite` enables Node 22's built-in `node:sqlite` module for the audit log (no native compilation, no separate sqlite package — drop the flag when the module ships stable). `--no-warnings` silences the experimental notice.

## HTTP endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Liveness + wired channel list + route count |
| `POST` | `/notify` | Single Notification (Zod-validated) |
| `POST` | `/webhook/alertmanager` | Alertmanager v4 webhook; each alert → its own dispatch + audit row |
| `GET` | `/audit/recent` | `?limit=N&topic=X&source=Y&status=ok\|failed` — recent dispatches with per-channel results |
| `GET` | `/circuit/status` | Per-channel breaker state |

Status codes from dispatch endpoints: `200` all-ok / `207` mixed / `502` all-failed / `202` no channels matched.

## hwc-notify CLI

On the system PATH. Thin shell wrapper over the loopback HTTP service.

```bash
hwc-notify send <topic> <title> [body] [--priority N] [--source S] [--tags t1,t2]
hwc-notify recent [--limit N] [--topic X] [--source Y] [--status ok|failed]
hwc-notify status     # circuit-breaker state
hwc-notify health
```

Example:

```bash
hwc-notify send monitoring "[P3] Test ping" "Smoke test." --priority 3 --tags smoke,test
hwc-notify recent --limit 5 --status failed | jq '.rows[] | {id, title, deliveries}'
```

## hwc_notify MCP tool

Consolidated single tool with an `action` enum (`send` / `recent` / `status` / `health`). Lives in `domains/system/mcp/src/src/tools/notify.ts`. Same HTTP under the hood as the CLI. In a Claude Code session:

> "send a P2 to monitoring topic about the disk getting full"
>
> → `mcp__claude_ai_hwc__hwc_notify action=send topic=monitoring title="..." priority=2 ...`

> "what failed in the last hour"
>
> → `mcp__claude_ai_hwc__hwc_notify action=recent filter_status=failed limit=20`

The MCP gateway logs the consolidated tool count at startup (`Gateway ready: N tools (hwc-sys: M, …)`); after adding `notify.ts` the count went 14 → 15.

## Editing the source

For pure source changes (no new deps):

```bash
cd ~/.nixos/domains/notifications/notify/parts/src
npx tsc --noEmit                                # local typecheck; no output = clean
git -C ~/.nixos commit -a                       # commit before rebuild
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
```

`buildNpmPackage` rebuilds whenever the source content changes; the new derivation gets a new store path; systemd restarts to it.

## Adding / upgrading npm deps

`npm install <pkg>` (or `npm update`) modifies `package-lock.json`. The Nix build content-pins the lockfile via `npmDepsHash` — when the lock changes, the hash must change, or the build fails. **This is enforced; do not bypass.**

Use the shipped wrapper:

```bash
cd ~/.nixos/domains/notifications/notify/parts/src
npm install <pkg>                                          # updates package.json + package-lock.json
hwc-notify-deps-update                                     # patches npmDepsHash + git-adds the touched files
git -C ~/.nixos diff --cached                              # review
git -C ~/.nixos commit
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
```

`hwc-notify-deps-update` is a `pkgs.writeShellApplication` on the system PATH. Under the hood it runs `nix run nixpkgs#prefetch-npm-deps` to compute the hash from the lockfile, in-place patches the `npmDepsHash = "sha256-…"` line in `index.nix`, and `git add`s the touched files. Anchored on `config.hwc.paths.nixos` per Charter Law 3.

If the CLI isn't available, fall back to:

1. `nix run nixpkgs#prefetch-npm-deps -- ./parts/src/package-lock.json` — prints the hash; hand-edit `index.nix`.
2. **Deliberate failure**: set `npmDepsHash = lib.fakeHash;`, `nixos-rebuild build` fails with the real hash in the error, paste it in, rebuild.

Full background: `wiki/nixos/nixos-buildnpmpackage-hash-workflow.md` in the brain vault.

## Adding a channel

Channels are pure Nix data in `parts/channels.nix`. To add (e.g.) a second SMTP channel for the office address:

```nix
# parts/channels.nix
{
  id        = "smtp-office";
  name      = "email → office@iheartwoodcraft.com";
  adapter   = "smtp";
  secretRef = "proton-bridge-password";
  params = {
    host       = "127.0.0.1";
    port       = 1025;
    requireTls = true;
    login      = "office@iheartwoodcraft.com";
    from       = "office@iheartwoodcraft.com";
    to         = "office@iheartwoodcraft.com";
    timeoutMs  = 10000;
  };
}
```

Then optionally add a routing rule that references it in `parts/routes.nix`. Commit + rebuild. No TS code change needed.

If the new channel uses a secret that isn't already in agenix, add it to `domains/secrets/declarations/services.nix` first (and `secrets.nix` for recipients).

## Adding / changing a routing rule

Rules are pure Nix data in `parts/routes.nix`. First-rule-wins. An empty `match` is a catch-all. To send `priority=2` alerts about a specific source to a custom channel:

```nix
{
  name     = "kitchen-leads-fanout";
  match    = { source = "calculator"; priority = 2; };
  channels = [ "discord-hwc-leads" "smtp-eric" ];
}
```

Insert before any conflicting catch-all. Commit + rebuild.

If no rule matches a notification, the dispatcher falls back to `defaultChannels`. The eval-time cross-ref assertion in `index.nix` guarantees every channel id in routes/defaultChannels exists in `cfg.channels`.

## Audit log

Schema lives in `adapters/audit-sqlite.ts`. Two tables: `notifications` (one row per dispatched Notification) and `deliveries` (one row per per-channel attempt). The DB is at `${stateDir}/audit.sqlite` (default `/var/lib/hwc/notify/audit.sqlite`). WAL mode; foreign-keyed; prepared statements; BEGIN/COMMIT around each `record()`.

Queries:

```bash
# Recent dispatches:
hwc-notify recent --limit 20

# Just the failed ones:
hwc-notify recent --status failed

# Direct SQL for ad-hoc exploration:
sudo sqlite3 /var/lib/hwc/notify/audit.sqlite "SELECT id, title, topic, priority FROM notifications ORDER BY received_at DESC LIMIT 10"
```

## Circuit breaker

In-memory per-channel state: closed → open after 5 consecutive failures → half-open after 60s → close on success / re-open on failure. Defaults are hardcoded in `main.ts`; move into the `# OPTIONS` section of `index.nix` when there's a reason to tune per-host.

When a channel's circuit is open, dispatch skips the channel and records `{ok: false, message: "circuit_open"}` in the audit log. Operators see the open state via `hwc-notify status`.

A service restart resets every circuit. Acceptable because the alerting system is its own canary — a stuck circuit that persists past a restart shows up as silent notifications, which the operator notices.

## Operations

Quick verification after any change:

```bash
# Is the service running?
systemctl is-active hwc-notify.service

# Wired channels?
hwc-notify health

# Send a self-test (lands in #hwc-alerts via monitoring-to-alerts rule):
hwc-notify send monitoring "[P3] self-test" "ping from hwc-notify CLI."

# Verify the audit row:
hwc-notify recent --limit 1
```

Alertmanager integration is wired via `profiles/monitoring.nix` → `hwc.monitoring.alertmanager.webhookReceivers`. Since the 2026-07-06 gotify decommission, `hwc-notify` is the sole receiver. Adding/removing receivers there reconfigures Alertmanager on the next rebuild.

If `hwc-notify` is down, Alertmanager will retry (its own backoff) until it recovers; there is no parallel push sink anymore.

## Charter compliance

| Law | Status |
|---|---|
| Law 1 (handshake) | n/a — server-only service |
| Law 2 (namespace = folder) | ✅ `hwc.notifications.notify.*` |
| Law 3 (no hardcoded paths) | ✅ `stateDir` from `config.hwc.paths.state`; secrets from `config.age.secrets.<ref>.path` |
| Law 4 (eric:users) | ✅ `User=eric`, `Group=users`, secrets group-read |
| Law 5 (containers) | n/a — native service |
| Law 6 (module structure) | ✅ OPTIONS / IMPL / VALIDATION |
| Law 7 (sys.nix purity) | n/a |

Hardening: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only`, `RestrictNamespaces`, `RestrictRealtime`, `LockPersonality`, `PrivateTmp`, `PrivateDevices`, `SystemCallArchitectures=native`. State path is the only `ReadWritePath`.

## Status

| Phase | State | What landed |
|-------|-------|------------|
| 0   | ✅ scaffolded | Domain shape + agenix secrets. |
| 1.1 | ✅ deployed   | HTTP skeleton + `/health`, structured stderr logging, systemd hardening, Caddy port-mode route. |
| 1.2 | ✅ deployed   | `POST /notify` + Zod input schema + Discord adapter wired to agenix secret. |
| 1.3 | ✅ deployed   | Channels + routes as declarative Nix data; runtime-config JSON in the Nix store. |
| 1.4 | ✅ deployed   | SMTP adapter via Proton Bridge (STARTTLS + agenix password). |
| 1.5 | ✅ deployed   | SQLite audit log (`node:sqlite`) + per-channel circuit breaker + `GET /audit/recent` + `GET /circuit/status`. |
| 1.6 | ✅ deployed   | `POST /webhook/alertmanager` + Alertmanager cutover (n8n receiver removed, workflow deactivated). |
| 1.7 | ✅ deployed   | `hwc-notify` CLI + `hwc_notify` MCP tool. |

## Changelog

- **2026-06-12**: Added the `discord-nightly-builds` channel (`#nightly-builds`, secretRef `discord-webhook-nightly-builds`) and a `topic=nightly-builds` route in `parts/`. Used by the automation domain's nightly-builds runner (per-card verdict) and the weekly readme-freshness report.
- **2026-05-31 (Phase 1.7)**: Shipped `hwc-notify` CLI (`pkgs.writeShellApplication`) and `hwc_notify` MCP tool (`domains/system/mcp/src/src/tools/notify.ts`). MCP gateway tool count 14 → 15.
- **2026-05-31 (Phase 1.6)**: Added `POST /webhook/alertmanager` with Zod schema + pure converter. Alertmanager cut over from n8n to hwc-notify; `n8n-webhook` receiver removed; n8n `home:admin:alert-manager` workflow deactivated (preserved as rollback). Gotify-bridge receiver kept for iOS push.
- **2026-05-31 (Phase 1.5)**: SQLite audit log via Node 22's built-in `node:sqlite` (no new npm dep, no native build). Per-channel `CircuitBreaker` (5 failures / 60s cool-down / half-open probe). `GET /audit/recent` and `GET /circuit/status`. `restartTriggers` on channel `.age` files so secret rotation forces a restart.
- **2026-05-31 (Phase 1.4)**: SMTP channel adapter via Proton Bridge (STARTTLS, `auth plain`, agenix `proton-bridge-password`). Re-encrypted the agenix secret from password-store (was stale). Login is the send address, not the Proton account name — sources of truth: `~/.config/msmtp/config`, NOT `domains/mail/PROTON_BRIDGE_DEBUG_HISTORY.md`.
- **2026-05-31 (Phase 1.3)**: Channels and routes moved into pure Nix data files (`parts/channels.nix`, `parts/routes.nix`). Runtime reads a `pkgs.writeText`-built JSON at startup. `nullable().optional()` on route match fields because Nix submodules emit `null` for unset `nullOr` defaults.
- **2026-05-31 (Phase 1.2)**: Hexagonal layout established. `POST /notify` accepts Zod-validated input; lenient + canonical schemas split (canonical deferred to Phase 1.5 audit-log replay). Discord adapter reading the webhook from `/run/agenix/discord-webhook-hwc-alerts`. LogOnly fallback channel for missing wires.
- **2026-05-31 (Phase 1.1)**: First HTTP service skeleton (`/health` only). Cut over from Node's `--experimental-strip-types` to `pkgs.buildNpmPackage` to take real npm deps (zod first). Shipped `hwc-notify-deps-update` wrapper to automate the `npmDepsHash` dance after `npm install`. TS parameter-property shorthand replaced with explicit field declarations (strip-types holdover; tsc handles either now).
- **2026-05-31 (Phase 0)**: Initial scaffold. Charter-compliant module, agenix secrets for both Discord webhooks + the future hwc-leads HMAC.
