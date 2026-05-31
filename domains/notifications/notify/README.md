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

Hermetic Nix-built derivation via `pkgs.buildNpmPackage`. `nixos-rebuild` runs `npm ci` offline against a hash-pinned `package-lock.json`, then `npm run build` (tsc → `dist/`). The output is a single Nix store path containing the compiled JS + a populated `node_modules/`. No `npm install` at deploy time, no network at switch, no developer manual-build step. The systemd unit's `ExecStart` is `node ${pkg}/lib/node_modules/hwc-notify/dist/main.js`.

This is the canonical Nix pattern (not the lighter strip-types approach used by `domains/server/native/ai/hermes/parts/bootstrap` — that one is right for zero-dep deploy CLIs; ours has real runtime deps).

## Editing the source

For pure source changes (no new deps):

```bash
cd domains/notifications/notify/parts/src
npx tsc --noEmit            # local typecheck; no output = clean
git commit                  # commit before rebuild — Nix reads the git store
sudo nixos-rebuild switch --flake .#hwc-server
```

`buildNpmPackage` rebuilds whenever the source content changes; the new derivation gets a new store path; systemd restarts to the new path.

## Adding / upgrading npm deps

`npm install <pkg>` (or `npm update`) modifies `package-lock.json`. The Nix build content-pins the lock file via `npmDepsHash` — when the lock changes, the hash changes, and Nix refuses to build with the stale hash. **This is enforced; do not bypass.** The hash is the proof that what's on disk matches what built.

### Workflow

```bash
cd ~/.nixos/domains/notifications/notify/parts/src
npm install <pkg>                                          # updates package.json + package-lock.json
hwc-notify-deps-update                                     # patches index.nix's npmDepsHash + stages all 3 files
git -C ~/.nixos diff --cached                              # review
git -C ~/.nixos commit                                     # commit before rebuild
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
```

`hwc-notify-deps-update` is shipped with this module (`pkgs.writeShellApplication`, on the system PATH). Under the hood it runs `nixpkgs#prefetch-npm-deps` to compute the hash from the lockfile, in-place patches the `npmDepsHash = "sha256-…"` line in `index.nix`, and `git add`s the touched files. Anchored on `config.hwc.paths.nixos` per Charter Law 3.

### If the CLI is not available

Either you're on a non-server machine without the module installed, or something broke. Fall back to either:

1. **`nix run nixpkgs#prefetch-npm-deps -- ./package-lock.json`** — computes the hash directly, then hand-edit `index.nix`.
2. **Deliberate failure**: set `npmDepsHash = lib.fakeHash;`, `nixos-rebuild build` fails with the real hash in the error, copy it in, rebuild. The base case; works anywhere.

### When this CLI needs to be lifted

When `hwc-leads` (Phase 2) or another `buildNpmPackage`-built service appears, the right move is to lift the body of `notify-deps-update` into a parameterised helper (e.g., `hwc-deps-update <service-namespace>`) rather than copy-paste. Single-call-site abstractions are wrong; two known call sites is the right time to factor.

## Local dev-loop without rebuilding NixOS

For tight iteration (no need to wait for `nixos-rebuild switch` per edit):

```bash
cd domains/notifications/notify/parts/src
npm install                 # one-time, populates node_modules/
npm run build && npm start  # run the same dist/main.js the systemd unit runs
```

This uses the local `node_modules/` (gitignored). The systemd-deployed service still runs from the Nix store path — local runs and the deployed service are independent processes.

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
