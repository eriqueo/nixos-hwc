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
| `index.nix` | Module: options + the `:8060` service. Builds the **engine** HTTP shell (buildNpmPackage → esbuild bundle of `serve.ts`), profiles baked to the store, mutable state in `/var/lib/refinery`. Hardened (ProtectHome=tmpfs + vault bound read-only for `/hopper`). |
| `engine/src/shells/` | HTTP shell over the core: `http.ts` (routes — `/` Gauntlet, `/hopper` ideas+intake, `/cards` legacy, + intake/amend/rewind handlers), `render.ts` (Gauntlet board = projects in phase lanes tinted by profile color + a profiles **legend**; Hopper page = raw ideas + intake; plain form-posts), `hopper.ts` (legacy nightly-builds card view at `/cards`), `serve.ts` (service entry). |
| `app/` | **Superseded** by the engine shell as the `:8060` service; kept as the original read-only hopper board (slice 01/02) and its tests. The hopper view now lives at the engine's `/hopper` route. |
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
| `engine/src/adapters/` | `LlmPort` adapters — `claude-cli` (headless `claude -p`), `anthropic-api` (raw-fetch Messages API), `ollama` (local daemon) — plus `resolveLlm(provider)` mapping a profile's `llmProvider` to the adapter. All late-bound from env. |
| `engine/src/profiles/` | `ProfileCatalog` — lead_scout-style registry: disk scan of `profiles/*.yaml` + a writable `enabled` overlay (so toggling never rewrites a repo file). `list`/`get`/`enabled`/`setEnabled`. `gauntlet-config.ts` holds the per-gauntlet execute knobs (verdict token, success verdicts) not on the Profile schema. |
| `engine/src/sources/` | `SourcePort` — inbound intake boundary (a profile's `source` field names the adapter). Concrete adapters (vault card scan, Firestore SR fetch) are a later human-gated step. |
| `engine/src/triage.ts` | `triageSentence` — intake classifier: routes a raw sentence to one of the enabled profiles (via `LlmPort`) or `untriaged` below a confidence threshold. `makeTriagedItem` builds the Item (parked at `triage` if untriaged). |
| `engine/src/cli/run-once.ts` | `runGenreOnce` — orchestration core: load/create item → run gate pipeline → fire integrate effector on a clean pass. Fully injected (testable). |
| `engine/src/cli.ts` | CLI shell: `refinery run --genre … --input "<sentence>"`. Parses args, wires real adapters, delegates to `runGenreOnce`. |
| `profiles/` | Genre profiles (data; lead_scout-style — `genre`/`label`/`enabled`/`llmProvider` + pipeline). `project-ideation.yaml` (live e2e); `nightly-build.yaml` + `datax-sr.yaml` (the two gauntlets as profiles, shipped `enabled: false` — strangler-fig). |

## Changelog
- **2026-06-15** — Delete + nightly-cards mirror. Projects/ideas can be deleted
  from the detail page (`ItemStore.delete`, `POST /delete`). The live
  nightly-builds vault cards (`_inbox/nightly_builds/*/NN-*.md`) are mirrored
  read-only into the board (`sources/nightly-cards.ts`, `nb:` id prefix): they
  appear as orange `nightly-build` projects in the Gauntlet phase lanes and on
  the Nightly page, with their detail page showing run/PR links but no edit
  actions (the overnight `run.sh` owns them). Re-added a read-only vault bind for
  this. Engine 62/62. Driving the overnight timer *from* refinery (writing card
  status) is the next, human-gated step.
- **2026-06-15** — Vocabulary + board re-skin. Locked terminology: **Refinery**
  (whole system) → **Hopper** (raw untriaged *ideas*) → triage → **Project**
  (triaged, has a profile *color*) moving through **Phases** of the **Gauntlet**
  → **Report**. Renamed `stage → phase` across the engine. Profiles now carry a
  `color` (data-driven); the board splits into a **Gauntlet** page (projects in
  phase lanes, tinted by profile color, amend/rewind on parked) and a **Hopper**
  page (ideas + intake); the profiles panel is now a color **legend** (no
  toggle — profiles are always available to triage; the human gate is per-project
  at a phase). Legacy nightly-cards view moved to `/cards`. Engine 55/55.
- **2026-06-15** — Slices 07+08 (board side): the `:8060` service now runs the
  **engine HTTP shell** (`engine/src/shells/`), an interactive board over the
  engine item store. Intake (`POST /intake`) triages a sentence into an enabled
  profile (or parks it untriaged); parked items get amend (re-arm with a note)
  and rewind (to an earlier gate) controls; a profiles panel toggles profiles via
  the catalog overlay. The read-only gauntlet hopper is folded in at `/hopper`.
  `index.nix` repointed from the esbuild `app/` board to the engine server
  (buildNpmPackage + esbuild bundle; profiles baked to the store; state in
  `/var/lib/refinery`). Engine 55/55 (+7). Plain form-posts (no JS framework).
- **2026-06-15** — Slice 08 (engine core): `triage` intake classifier
  (`engine/src/triage.ts`). `triageSentence` routes a raw sentence to one of the
  enabled profiles via the injected `LlmPort`, falling back to `untriaged` when
  the model picks an unoffered genre or is below the confidence threshold;
  `makeTriagedItem` builds the Item (untriaged → parked at `triage` for human
  routing on the board). Engine 48/48 (+5). The HTTP `/intake` endpoint, keybind,
  and agent skill are the board-integration half of slice 08 (pending the
  board↔engine wiring decision).
- **2026-06-15** — Slice 09: the two gauntlets expressed as profiles
  (`profiles/nightly-build.yaml` write-mode, `profiles/datax-sr.yaml`
  read-only) + a parity harness proving the engine reproduces each gauntlet's
  observable behavior through the slice-06 execute effector. `gauntlet-config.ts`
  carries the per-gauntlet execute knobs (verdict token + success verdicts);
  `SourcePort` defines the intake boundary. Strangler-fig: both profiles ship
  `enabled: false`, and the live `run.sh` files + timers are untouched —
  adopting them is a separate human-gated step. Engine 43/43 (+5 parity tests).
- **2026-06-15** — Profiles catalog + multi-LLM adapters (lead_scout patterns).
  `ProfileCatalog` (`engine/src/profiles/`) scans `profiles/*.yaml` and merges a
  writable `enabled` overlay (disk template vs live state, lead_scout-style) with
  `list`/`get`/`enabled`/`setEnabled`. Two new `LlmPort` adapters —
  `anthropic-api` (raw-fetch Messages API, `claude-opus-4-8` default) and
  `ollama` (local daemon) — join `claude-cli`, behind `resolveLlm(provider)` that
  maps a profile's `llmProvider`. The CLI now resolves its LLM from the profile.
  Engine 38/38.
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
