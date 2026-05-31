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

`npm install <pkg>` (or `npm update`) modifies `package-lock.json`. The Nix build content-pins the lock file via `npmDepsHash` — when the lock changes, the hash changes, and Nix refuses to build with the stale hash.

Workflow:

```bash
cd domains/notifications/notify/parts/src
npm install <pkg>           # updates package.json + package-lock.json
git add package.json package-lock.json
```

Then edit `index.nix` and set `npmDepsHash = lib.fakeHash;`. Run `sudo nixos-rebuild build --flake .#hwc-server` — it will fail with:

```
error: hash mismatch in fixed-output derivation '…hwc-notify-…-npm-deps.drv':
       specified: sha256-AAAAAAAA…  (= lib.fakeHash)
          got:    sha256-w76KLDIu…  ← the real one
```

Copy the `got:` value into `npmDepsHash` and rebuild. The hash is the proof that what's on disk matches what built — that's the value it provides. The annoyance is only in HOW you obtain the new value (force a build failure to print it), not in having it.

### Doing the hash update better

The "edit fakeHash → rebuild → copy `got:` → paste → rebuild again" cycle is the manual form. Cleaner options exist:

1. **`nix-prefetch-npm-deps`** (in nixpkgs) computes the hash from a lockfile without doing a real build. One command:

   ```bash
   nix run nixpkgs#prefetch-npm-deps -- ./parts/src/package-lock.json
   # → sha256-w76KLDIu…
   ```

   Then paste into `index.nix`. Removes the rebuild-fail step but you still hand-edit `npmDepsHash`.

2. **A wrapper CLI** (TODO — `hwc-notify-deps-update` as a `pkgs.writeShellApplication`) that does the whole flow in one shot:

   ```bash
   cd domains/notifications/notify/parts/src
   npm install <pkg>           # or `npm update`
   hwc-notify-deps-update      # runs prefetch + patches index.nix + stages changes
   git diff --stat             # review
   sudo nixos-rebuild switch --flake .#hwc-server
   ```

   This is the right "fix it properly" answer for a single-developer repo. The wrapper is ~15 lines of bash. Not built yet — see [[../../../README.md]] backlog or open an issue when this starts to grate.

3. **Alternative npm-to-nix translators** (`napalm`, `node2nix`, `yarn2nix`) skip the hash entirely by reading `package-lock.json` directly inside the Nix evaluator. They have their own tradeoffs (evaluation cost, lockfile-format coverage, opinionated about scripts). Worth evaluating only if option 2 isn't enough.

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
