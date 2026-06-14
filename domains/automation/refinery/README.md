# domains/automation/refinery

Refinery — the substance-agnostic refinement engine that generalizes the
nightly-builds + sr_gauntlet gauntlets. Full design lives in the brain vault at
`tech/development/builds/refinery/refinery_engine_design.md`.

This module is **slice 01+02**: the read-only Kanban **board** for the gauntlet
hopper. It renders every card across the brain vault's
`_inbox/nightly_builds/*/NN-*.md` goal folders (plus raw `_ideas.md` ideas) as a
live, status-grouped board. The engine core, gate registry, genres, and
interactivity (amend/rewind) are later slices (cards 03–09 in the hopper).

- **Namespace:** `hwc.automation.refinery.*`
- **URL:** `refinery.hwc.iheartwoodcraft.com` (Caddy vhost → `127.0.0.1:8060`)
- **Reads:** the brain vault, read-only (`hwc.paths.brain.*`).

The TypeScript app (`app/src/*.ts`, zero runtime deps, pure `node:http`) is
bundled to one JS file by **esbuild** at build time — no npm / node_modules /
`npmDepsHash`. The page meta-refreshes every 10s; no client framework (htmx
arrives with the interactive amend/rewind slice).

## Structure
| Path | Purpose |
|---|---|
| `index.nix` | Module: options, esbuild bundle derivation, systemd service |
| `app/src/parse.ts` | Read-only parser over the hopper (cards + ideas) |
| `app/src/render.ts` | Server-side Kanban HTML render |
| `app/src/server.ts` | `node:http` shell; late-bound port + vault from env |
| `app/tsconfig.json` | TS config (typecheck/editor; esbuild needs no build step) |

## Changelog
- 2026-06-14 — Initial board (slice 01+02): read-only Kanban over the gauntlet
  hopper. New `hwc.automation.refinery` module + systemd service (port 8060),
  esbuild-bundled TS app, Caddy vhost route (`refinery`), enabled on the server
  role. Built by hand (not via the gauntlet) to bring the board up immediately;
  hopper cards 01/02 cover the same scope and are marked done.
