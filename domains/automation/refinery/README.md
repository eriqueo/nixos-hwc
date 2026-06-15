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
  Item state machine driven by genre profiles, with hexagonal boundaries (the
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

### Two build toolchains (intentional)
The `app/` and `engine/` use **different** module-resolution worlds — don't
"unify" them:
- **`app/` (board)** — relative imports carry `.ts` extensions
  (`./parse.ts`). It's bundled by **esbuild** (which resolves TS specifiers) and
  has **zero runtime deps**. Tests run via Node's native type-stripping
  (`node --test 'test/**/*.test.ts'`) — no build step. `package.json` carries
  dev-only deps (`@types/node`, `typescript`) for typecheck/tests; they never
  reach the bundle.
- **`engine/` (library)** — relative imports carry `.js` extensions
  (`./contracts.js`, ESM convention). It's compiled by **tsc** to `dist/`, and
  tests run against the compiled output (`tsc && node --test dist/test/**`).

## Structure
| Path | Purpose |
|---|---|
| `index.nix` | Module: options, esbuild bundle derivation, hardened systemd service |
| `app/src/parse.ts` | Read-only parser over the hopper (cards + ideas) |
| `app/src/render.ts` | Server-side Kanban HTML render |
| `app/src/server.ts` | `node:http` shell; late-bound port + vault from env |
| `app/test/*.test.ts` | Parser + render unit tests (`node --test`, native type-strip) |
| `app/package.json` | Dev-only deps + `test`/`typecheck` scripts (esbuild bundle stays dep-free) |
| `app/tsconfig.json` | TS config (typecheck/editor; esbuild needs no build step) |
| `engine/` | Engine core: Item + GateModule + Profile contracts (Zod), stage runner, in-memory ItemStore. TypeScript library, `node --test` unit tests. Substance-agnostic, no IO beyond injected ports. |
| `engine/src/gates/` | Gate registry: Eric's engineering canon as `GateModule`s (stepwise-refinement, principles-create/fix, chestertons-fence, blast-radius, premortem, admission-gates). Each = `applies()` predicate over item traits + a prompt + a Zod verdict schema + `decide()`. LLM consulted via an injected `LlmPort` (stubbed in tests). `makeGateRegistry(llm)` / `gateList(llm)`. |
| `engine/src/effectors/` | Effectors (`ItemEffector`s): `execute` — one mode-parameterized worktree → headless-claude → verdict → report → push/pristine extract of the two `run.sh` files (git/claude/report injected); `write-spec` — the project-ideation `integrate` step (LLM → `SpecSchema` → markdown spec to scratch). |
| `engine/src/stores/` | `MarkdownItemStore` (`ItemStore`): one `.md` per item — board-readable frontmatter + a canonical ```json block for lossless round-trip. |
| `engine/src/adapters/` | `makeClaudeLlm` — production `LlmPort` via a headless `claude -p` call; binary late-bound from `$REFINERY_CLAUDE_BIN`. |
| `engine/src/cli/run-once.ts` | `runGenreOnce` — orchestration core: load/create item → run gate pipeline → fire integrate effector on a clean pass. Fully injected (testable). |
| `engine/src/cli.ts` | CLI shell: `refinery run --genre … --input "<sentence>"`. Parses args, wires real adapters, delegates to `runGenreOnce`. |
| `profiles/` | Genre profiles (data; lead_scout-style — `genre`/`label`/`enabled`/`llmProvider` + pipeline). `project-ideation.yaml` — gates `[stepwise-refinement, principles-create, premortem]`, integrate `write-spec`, no code execution. |

## Changelog
- **2026-06-15** — Renamed the genre recipe concept **manifest → profile**
  throughout the engine (`ProfileSchema`/`Profile`, `parseProfile`/`loadProfile`,
  `InvalidProfileError`/`E_INVALID_PROFILE`, `src/profile.ts`, `profiles/` dir)
  and enriched the schema lead_scout-style with optional `label`, `enabled`, and
  `llmProvider`. Historical changelog entries below predate the rename and still
  say "manifest" — that's the point-in-time record. Build/test now clean `dist/`
  first (a removed source file no longer leaves a stale compiled test behind).
- **2026-06-15** — Slice 05: first genre end-to-end (project-ideation). The
  whole engine proven on one no-code genre: a sentence → stepwise-refinement →
  principles-create → premortem → a developed project spec. New
  `manifests/project-ideation.yaml`, `MarkdownItemStore` (lossless `.md`
  round-trip via a canonical json block + board-readable frontmatter), the
  `write-spec` integrate effector (LLM → `SpecSchema` → markdown to scratch, with
  an `isSpecComplete` section check), a `runGenreOnce` orchestration core, the
  `refinery` CLI shell, and a late-bound `makeClaudeLlm` production adapter.
  Coverage (`node --test`, 34 total, +4): manifest validates against the schema,
  store round-trips, the e2e produces a complete spec, and a parked gate stops
  the pass before integrate. CLI shell smoke-tested end-to-end with a stub binary.
- **2026-06-15** — Slice 06: execute-harness extract (`engine/src/effectors/`).
  Defined the `ItemEffector` port + result contract in `contracts.ts`, then
  implemented one mode-parameterized execute effector factoring the shared
  worktree→headless-claude→verdict→report→push/pristine logic out of
  `nightly-builds/run.sh` (write mode) and `sr_gauntlet/run.sh` (read-only).
  The two axes they differ on — execute mode (commit+push vs assert-pristine)
  and verdict token (`NIGHTLY-VERDICT` vs `SR-VERDICT`) — are config, plus
  `successVerdicts`. git + claude + report-check are injected ports (`ports.ts`)
  so tests spawn nothing. The live `run.sh` files are untouched (adoption is
  slice 09). Coverage (`node --test`, 30 total, +9): prompt composition, verdict
  parse for both patterns, write-mode push path, read-only pristine + revert,
  timeout, worktree-add failure, and the write-mode-needs-branch guard.
- **2026-06-15** — Slice 04: gate registry + discipline gate modules
  (`engine/src/gates/`). Seven `GateModule`s implementing slice-03's contract —
  stepwise-refinement, principles-create, principles-fix, chestertons-fence,
  blast-radius, premortem, admission-gates — each with an `applies()` predicate
  over data-driven item traits (`traits.ts`), a prompt framed from Eric's canon,
  a Zod verdict schema, and `decide()`. LLM access is the injected `LlmPort`
  (hexagonal; stubbed in tests). `makeGateRegistry(llm)` resolves manifest gate
  ids; `gateList(llm)` feeds the runner. New `InvalidGateVerdictError`
  (`E_INVALID_VERDICT`) for malformed LLM verdicts. Coverage (`node --test`, 21
  total, +6): registry resolves all ids, `applies()` fires/skips per trait,
  `decide()` maps the verdict, `parseVerdict` rejects non-JSON/schema-mismatch,
  and a manifest gate list composes through the runner end-to-end (pass-through
  + park-at-first-gate).
- **2026-06-15** — Review-hardening pass over the consolidated branch. Engine:
  documented the `GateModule.run` idempotency contract (runner re-enters the
  parked stage on resume) and that `executeMode`/`effectors` are
  declared-but-not-yet-consumed; `rewind` now validates `toStage` against the
  manifest when one is supplied (fail-loud at the call site) — engine tests
  15 (was 14). Board: added `app/test/` parser + render unit tests (10,
  Node native type-stripping) and a dev-only `app/package.json`; `esc()` now
  escapes single quotes. systemd service hardened — `/home` is masked
  (`ProtectHome = true`) with only the vault bound back read-only.
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
