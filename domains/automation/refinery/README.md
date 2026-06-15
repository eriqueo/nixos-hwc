# domains/automation/refinery

Refinery — the substance-agnostic refinement engine that generalizes the
nightly-builds + sr_gauntlet gauntlets. Full design lives in the brain vault at
`tech/development/builds/refinery/refinery_engine_design.md`.

The module is being built in slices:

- **Slice 01+02 — board:** the read-only Kanban **board** for the gauntlet
  hopper. It renders every card across the brain vault's
  `_inbox/nightly_builds/*/NN-*.md` goal folders (plus raw `_ideas.md` ideas) as
  a live, status-grouped board.
- **Slice 03 — engine core:** the substance-agnostic engine itself — a typed
  Item state machine driven by genre manifests, with hexagonal boundaries (the
  core knows nothing about filesystem, Firestore, or Claude).

The gate registry, genres, and interactivity (amend/rewind) are later slices
(cards 04–09 in the hopper).

- **Namespace:** `hwc.automation.refinery.*`
- **URL:** `refinery.hwc.iheartwoodcraft.com` (Caddy vhost → `127.0.0.1:8060`)
- **Reads:** the brain vault, read-only (`hwc.paths.brain.*`).

The TypeScript board app (`app/src/*.ts`, zero runtime deps, pure `node:http`) is
bundled to one JS file by **esbuild** at build time — no npm / node_modules /
`npmDepsHash`. The page meta-refreshes every 10s; no client framework (htmx
arrives with the interactive amend/rewind slice). The engine core (`engine/`) is
a standalone TypeScript library with `node --test` unit tests, substance-agnostic
and IO-free beyond injected ports.

## Structure
| Path | Purpose |
|---|---|
| `index.nix` | Module: options, esbuild bundle derivation, systemd service |
| `app/src/parse.ts` | Read-only parser over the hopper (cards + ideas) |
| `app/src/render.ts` | Server-side Kanban HTML render |
| `app/src/server.ts` | `node:http` shell; late-bound port + vault from env |
| `app/tsconfig.json` | TS config (typecheck/editor; esbuild needs no build step) |
| `engine/` | Engine core: Item + GateModule + Manifest contracts (Zod), stage runner, in-memory ItemStore. TypeScript library, `node --test` unit tests. Substance-agnostic, no IO beyond injected ports. |

## Changelog
- **2026-06-15** — Slice 03: scaffolded `engine/` (TypeScript + Zod + yaml).
  Added Item / GateModule / Manifest Zod schemas in `src/contracts.ts`,
  named-error classes in `src/errors.ts`, YAML manifest loader/validator in
  `src/manifest.ts`, the stage runner + `rewind` in `src/runner.ts`, and an
  `InMemoryItemStore` for tests. Coverage (`node --test`, 14 tests):
  forward-advance, park-on-fail, fail-stop, park-and-resume, `applies()`
  skip, `rewind` + replay, unknown-gate / unknown-stage structured errors,
  manifest schema + YAML-parse rejection, hexagonal loader delegation.
- **2026-06-14** — Initial board (slice 01+02): read-only Kanban over the
  gauntlet hopper. New `hwc.automation.refinery` module + systemd service (port
  8060), esbuild-bundled TS app, Caddy vhost route (`refinery`), enabled on the
  server role. Built by hand (not via the gauntlet) to bring the board up
  immediately; hopper cards 01/02 cover the same scope and are marked done.
