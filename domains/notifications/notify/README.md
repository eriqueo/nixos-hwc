# domains/notifications/notify — hwc-notify

Hexagonal TypeScript notification dispatcher. **Phase 0 scaffold — not yet implemented.**

## Purpose

Replace the n8n `home:admin:alert-manager` workflow and the per-script CLI
senders (`hwc-gotify-send`, `hwc-webhook-send`, `hwc-smartd-notify`, etc.)
with one service that:

- exposes HTTP, CLI, and MCP shells over the same core
- runs outbound notifications through pluggable adapters (Discord, SMTP,
  later Gotify / Slack / iGotify)
- loads routing rules + channels from declarative Nix data
- enforces a Zod-validated `Notification` contract at every shell
- writes an audit row per delivery attempt
- trips per-channel circuit breakers and falls over to a secondary channel
  when one craters

## Why

Today's notification routing lives inside a 14-node n8n workflow whose
failures only surface as failed-execution rows nobody reads. On 2026-05-31
the workflow had been silently erroring for a full day because of a stale
`ntfy` URL. There is no schema validation, no circuit breaker, no audit
log of "what should have notified me today vs. what actually delivered."

See `~/.claude/plans/hashed-snacking-crab.md` for the full design.

## Namespace

`hwc.notifications.notify.*` (Charter Law 2 — namespace = folder).

## Structure

```
notify/
├── README.md          # This file
├── index.nix          # Charter Law 6 module (OPTIONS / IMPL / VALIDATION)
├── options.nix        # hwc.notifications.notify.* schema
├── parts/             # Phase 1: channels.nix, routes.nix (data-as-config)
└── src/               # Phase 1: TypeScript service (core / adapters / shells)
```

## Runtime

Node 22 with `--experimental-strip-types`. No `npm install` or build step at deploy time. TS source is bundled into the Nix store via `lib.sources.sourceFilesBySuffices` and Node strips type annotations at parse. `package.json` + the on-disk `node_modules/` exist only as type-only metadata for IDE typechecking and are ignored at runtime.

Same pattern as `domains/server/native/ai/hermes/parts/bootstrap`.

## Editing the source

After editing any `.ts` file:

```bash
cd domains/notifications/notify/parts/src
npx tsc --noEmit            # typecheck; no output = clean
sudo systemctl restart hwc-notify
```

`nixos-rebuild switch` picks up `.ts` changes automatically because the module bundles the source via `sourceFilesBySuffices`. The restart is needed because the systemd unit's `ExecStart` references a specific Nix store path that only changes on rebuild.

## Status

| Phase | State | What lands |
|-------|-------|------------|
| 0 | ✅ scaffolded | Charter module + namespace + empty src/ tree. |
| 1.1 | ✅ deployed | Node HTTP server, `GET /health`, structured stderr logging, systemd unit with hardening, Caddy port-mode route. |
| 1.2 | ⬜ planned | `POST /notify` + Zod schema + Discord adapter wired to `/run/agenix/discord-webhook-hwc-alerts`. |
| 1.3 | ⬜ planned | Routes + channels as data (`parts/routes.nix`, `parts/channels.nix`). |
| 1.4 | ⬜ planned | SMTP adapter via Proton Bridge. |
| 1.5 | ⬜ planned | Audit log (SQLite) + circuit breaker per channel. |
| 1.6 | ⬜ planned | `POST /webhook/alertmanager` + Alertmanager cutover. |
| 1.7 | ⬜ planned | `hwc-notify` CLI shim + MCP tool registration. |

## File layout

```
notify/
├── README.md
├── index.nix                # Charter Law 6 module + systemd unit + Caddy route
├── options.nix              # hwc.notifications.notify.* schema
└── parts/
    └── src/                 # IDE typecheck workspace; runtime reads from Nix store
        ├── package.json     # type-only devDeps
        ├── tsconfig.json    # noEmit, allowImportingTsExtensions
        └── src/
            ├── main.ts      # Entry point — HTTP server
            ├── config.ts    # Late-binding env loader
            ├── core/
            │   └── errors.ts
            ├── ports/
            │   └── log.ts
            └── adapters/
                └── log-stderr.ts
```

## Changelog

- **2026-05-31** (Phase 1.1): Wired the real Node runtime. Minimal HTTP server (`GET /health` only), structured JSON logging to stderr, systemd unit with full Charter hardening (NoNewPrivileges, ProtectSystem strict, etc.), Caddy port-mode route on 29443. Internal port 11600. Service evaluates clean both enabled and disabled.
- **2026-05-31** (Phase 0): Initial scaffold. Module structure + enable option only; no implementation.
