# domains/business/leads — hwc-leads

Hexagonal TypeScript lead pipeline. Single `POST /leads` HTTP endpoint replacing the three independent customer-facing webhook paths (contact form, calculator submit, appointment booking). Phase 2 of the broader notification + lead-pipeline restructure.

**Status**: Phase 2.1 — `/health` only. Subsequent chunks (2.2 → 2.8) add the Lead schema, HMAC verification, JobTread graph creation, Postgres write, hwc-notify ping, customer confirmation email, MCP tool, and the cutover.

**Namespace**: `hwc.business.leads.*` (Charter Law 2 — namespace = folder).

## Why

Before Phase 2 there were three paths into "we got a lead":

- **Contact form** → JT Web Form embed directly to JobTread. No `hwc.calculator_leads` row, no notification, no audit trail.
- **Calculator** → n8n webhook → 23-node workflow that built the JT graph, wrote the lead row, sent the customer email, added a khal calendar event.
- **Appointment** → n8n webhook → 8-node workflow (deactivated; zero recent executions).

Three different validation regimes (i.e. none — the workflows trusted whatever the website posted), three different notification gaps, three different storage policies. There's no single "Lead" entity, no single place to ask "did anything blow up while handling that submission?" When the contact form was filled out, the operator had to remember to go look in JobTread because nothing pinged.

hwc-leads collapses all three paths into one schema-validated TS service. The Phase 1 hwc-notify service is the downstream notification surface — same hexagonal pattern, same `Notification` shape, same audit trail.

## Architecture (hexagonal)

```
   Contact form  ─┐
                  │
   Calculator ────┤── HMAC-signed POST /leads ─▶ core (validate / JT / DB)
                  │                                  │
   Appointment ──┘                                   │  ┌─▶ JobTreadAdapter (account → location → contact → job)
                                                     ├─▶ PostgresAdapter (hwc.calculator_leads)
                                                     ├─▶ NotifyAdapter (HTTP → hwc-notify /notify)
                                                     └─▶ ReportStoreAdapter (Phase 4)
```

Inbound: one HTTP endpoint (Phase 2.2). Core: Lead entity + per-source validation + JT-graph idempotence + priority rules. Outbound: each downstream system has its own adapter behind a port; swapping JobTread for some other CRM would be a new adapter file.

## File layout

```
leads/
├── README.md                                # This file.
├── index.nix                                # Charter Law 6 module.
└── parts/
    └── src/                                 # TypeScript service.
        ├── package.json                     # type=module, zod runtime dep.
        ├── tsconfig.json                    # ES2023, NodeNext, strict.
        └── src/
            ├── main.ts                      # Entry — HTTP server, wiring.
            ├── config.ts                    # Late-binding env loader.
            ├── core/
            │   ├── types.ts                 # Lead, LeadSource, ProjectType (Phase 2.2 fills out).
            │   └── errors.ts                # Structured LeadsError.
            ├── ports/
            │   └── log.ts                   # Logger interface.
            └── adapters/
                └── log-stderr.ts            # Structured JSON to stderr.
```

Phase 2.2+ will fill out `schemas/`, additional `core/` modules, `ports/{audit,store,jt,notify}.ts`, and matching `adapters/`. The shape mirrors hwc-notify deliberately — same patterns, same hardening, same deps-update wrapper.

## Runtime

Hermetic Nix-built derivation via `pkgs.buildNpmPackage`. Identical pattern to hwc-notify (see `domains/notifications/notify/README.md` for the long-form treatment). `nixos-rebuild` runs `npm ci` offline against a hash-pinned `package-lock.json`, then `npm run build` (tsc → `dist/`); systemd `ExecStart` points at `node --experimental-sqlite ${pkg}/lib/node_modules/hwc-leads/dist/main.js`.

The `--experimental-sqlite` flag is pre-emptive — Phase 2 will eventually want an audit log of "lead in / dispatch out" the same way hwc-notify has one. Drop the flag when `node:sqlite` ships stable.

## HTTP endpoints (current)

| Method | Path | Response |
|---|---|---|
| `GET` | `/health` | `{status, service, version, uptimeSeconds, downstream: {notifyServiceUrl, hmacWired, jtGrantWired}}` |
| `POST` | `/leads` | `501 NOT_IMPLEMENTED` until Phase 2.2 |

`/health` reports which downstream credentials are wired without ever logging their values — a startup wiring sanity check.

## Editing the source

```bash
cd ~/.nixos/domains/business/leads/parts/src
npx tsc --noEmit                                     # local typecheck
git -C ~/.nixos commit -a
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
```

`buildNpmPackage` rebuilds whenever source content changes; systemd restarts.

## Adding / upgrading npm deps

Use the shipped wrapper (same flow as hwc-notify):

```bash
cd ~/.nixos/domains/business/leads/parts/src
npm install <pkg>
hwc-leads-deps-update                                # patches npmDepsHash + git-adds
git -C ~/.nixos diff --cached                        # review
git -C ~/.nixos commit
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
```

`hwc-leads-deps-update` is generated by the shared `domains/lib/deps-update.nix` helper (same code that produces `hwc-notify-deps-update`). Full background: `wiki/nixos/nixos-buildnpmpackage-hash-workflow.md`.

## NixOS options

| Option | Default | Notes |
|---|---|---|
| `hwc.business.leads.enable` | false | Enabled on hwc-server. |
| `hwc.business.leads.bindAddr` | `127.0.0.1` | Loopback; external access via Caddy. |
| `hwc.business.leads.port` | `11650` | Internal HTTP port. |
| `hwc.business.leads.reverseProxyPort` | `30443` | Caddy tailnet port. |
| `hwc.business.leads.statePath` | `${hwc.paths.state}/leads` | `StateDirectory = "hwc/leads"`. |
| `hwc.business.leads.logLevel` | `info` | `debug \| info \| warn \| error`. |
| `hwc.business.leads.notifyServiceUrl` | `http://127.0.0.1:11600` | Where to POST `Notification`s — usually loopback hwc-notify. |
| `hwc.business.leads.hmacSecretRef` | `hwc-leads-hmac-secret` | agenix secret name. Set null to disable HMAC (dev only). |
| `hwc.business.leads.jtGrantKeyRef` | `jobtread-grant-key` | agenix secret name for the JT grant key. |

## Charter compliance

| Law | Status |
|---|---|
| Law 1 (handshake) | n/a — server-only |
| Law 2 (namespace = folder) | ✅ `hwc.business.leads.*` |
| Law 3 (no hardcoded paths) | ✅ `statePath` from `hwc.paths.state`; secrets via `config.age.secrets.<ref>.path` |
| Law 4 (eric:users) | ✅ |
| Law 5 (containers) | n/a — native |
| Law 6 (module structure) | ✅ OPTIONS / IMPL / VALIDATION |
| Law 7 (sys.nix purity) | n/a |

Hardening: same set as hwc-notify (`NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only`, etc.). `restartTriggers` on the `.age` source files for both `hmacSecretRef` and `jtGrantKeyRef` so secret rotation auto-restarts on the next `nixos-rebuild switch`.

## Status & roadmap

| Phase | State | What lands |
|---|---|---|
| 0 | ✅ scaffolded | Charter module skeleton + agenix secrets pre-declared. |
| 2.1 | ✅ deployed | Node HTTP skeleton, `/health`, buildNpmPackage, structured logging, hardening, Caddy route, `hwc-leads-deps-update`. |
| 2.2 | ⬜ planned | Lead Zod schema, HMAC verify, POST /leads accepting validated payloads (no downstream calls yet — returns 202 + UUID). |
| 2.3 | ⬜ planned | Postgres adapter (writes to `hwc.calculator_leads`; new `source` + `status` columns via migration). |
| 2.4 | ⬜ planned | JobTreadAdapter (account → location → contact → job → comment; idempotent on existing IDs). |
| 2.5 | ⬜ planned | NotifyAdapter (HTTP client to hwc-notify) + customer confirmation email path. |
| 2.6 | ⬜ planned | Cutover: thin n8n shells; contact form converts off JT Web Form embed. |
| 2.7 | ⬜ planned | MCP tool `hwc_leads` (actions: list, get, recent, replay, update_status). |

## Changelog

- **2026-06-09** — `hwc-leads` Caddy route migrated from port-mode `:30443` to name-based vhost `hwc-leads.hwc.iheartwoodcraft.com` (shared `*.hwc.iheartwoodcraft.com` wildcard cert, no firewall port). The `lead-scout-api` MCP endpoint is intentionally **held on its dedicated port** — the laptop's Claude `.claude.json` pins that URL and is off-host (`~/.claude` isn't synced). See `domains/networking/README.md`.
- **2026-05-31** (Phase 2.1): Node HTTP skeleton + `/health` + hexagonal layout + Charter hardening + Caddy port-mode route on `:30443`. `--experimental-sqlite` flag pre-set for the upcoming audit log. Shipped via shared `domains/lib/deps-update.nix` (same helper that powers `hwc-notify-deps-update`).
- **2026-05-31** (Phase 0): Charter scaffold. Module + options + `enable = false` default with an assertion that fired when enabled. Agenix secret `hwc-leads-hmac-secret` (256-bit) pre-encrypted.
