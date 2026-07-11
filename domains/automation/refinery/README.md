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
  Item state machine driven by pipelines, with hexagonal boundaries (the
  core knows nothing about filesystem, Firestore, or Claude).

The gate registry, pipelines, and interactivity (amend/rewind) are later slices
(cards 04–09 in the hopper).

- **Namespace:** `hwc.automation.refinery.*`
- **URL:** `refinery.hwc.iheartwoodcraft.com` (Caddy vhost → `127.0.0.1:8060`)
- **Reads:** the brain vault, read-only (`hwc.paths.brain.*`).

The `:8060` service is the engine's own HTTP shell (`engine/src/shells/serve.ts`),
esbuild-bundled to one dep-free JS file at build time. No client framework; plain
form-posts (POST → 303). The engine core (`engine/`) is a standalone TypeScript
library with `node --test` unit tests, substance-agnostic and IO-free beyond
injected ports: relative imports carry `.js` extensions (ESM convention), it's
compiled by **tsc** to `dist/`, and tests run against the compiled output
(`tsc && node --test dist/test/**`).

## Structure
| Path | Purpose |
|---|---|
| `index.nix` | Module: options + the `:8060` service. Builds the **engine** package (buildNpmPackage → esbuild bundles **two** entry points: `serve.ts`→`server.js` for the board, and `cli/morning-review.ts`→`morning-review.js` wrapped as `bin/refinery-morning-review`). Pipelines baked to the store, mutable state in `/var/lib/refinery`. Hardened (ProtectHome=tmpfs + vault bound read-only for `/hopper`). Exposes a read-only `package` option so the **nightly-builds** morning-review pass runs the CLI without rebuilding the engine. |
| `engine/src/cli/morning-review.ts` | The morning PR-review CLI shell. Late-binds config from env (`REFINERY_VAULT_DIR`, `REFINERY_DEFAULT_REPO`, `REFINERY_REVIEWS_DIR`, `REFINERY_LLM_PROVIDER`, optional `REFINERY_REVIEW_DATE`), wires real git/gh/fs/LLM adapters, runs the orchestrator, prints a JSON summary to stdout. Driven by `nightly-builds-review.service` (timer in the **nightly-builds** domain). |
| `engine/src/shells/` | HTTP shell over the core: `http.ts` (routes — `/` Flow board, `/hopper`, `/nightly` Overnight, `/finished`, `/sr`, `/reviews`, `/reference`, per-item detail, + intake/amend/rewind/promote handlers), `render.ts` (Flow board = projects in state lanes, each card carrying a **gate-dot progress strip**; item detail = a pipeline node strip with expandable gate verdicts + executor result; `/reference` = the terminology canon + live pipelines; `/reviews` = morning PR verdicts; plain form-posts, CSS-only interactivity), `serve.ts` (service entry). |
| `engine/` | Engine core: Item + GateModule + Pipeline contracts (Zod), step runner, in-memory ItemStore. TypeScript library, `node --test` unit tests. Substance-agnostic, no IO beyond injected ports. |
| `engine/src/gates/` | Gate registry: Eric's engineering canon as `GateModule`s (stepwise-refinement, principles-create/fix, chestertons-fence, blast-radius, premortem, admission-gates). Each = `applies()` predicate over item traits + a prompt + a Zod verdict schema + `decide()`. LLM consulted via an injected `LlmPort` (stubbed in tests). `makeGateRegistry(llm)` / `gateList(llm)`. |
| `engine/src/executors/` | Executors (`Executor`s): `gauntlet` — the thin port to a **standalone** gauntlet (trigger via `ProcessPort`, read its report+verdict back via `ResultReader`, map to `ExecutorResult`); the modular seam that keeps the engine from absorbing each gauntlet's code. `native` — the in-process executor (mode-parameterized worktree → headless-claude → verdict → report → push/pristine; git/claude/report injected) for a pipeline with no standalone runner. `spec` — the project-ideation terminal step (LLM → `SpecSchema` → markdown spec to scratch). |
| `engine/src/gauntlets/` | The gauntlet dispatch contract: `GauntletContract` schema (`{trigger, resultsDir, reportFile, verdictPattern, successVerdicts}`, Zod) + `parseGauntletContract`; `ProcessPort`/`ResultReader` ports (real `nodeProcessPort`/`fsResultReader`, stubbed in tests); `loadGauntlets` registry over `gauntlets/*.yaml`. A standalone gauntlet becomes one YAML file. |
| `engine/src/stores/` | `MarkdownItemStore` (`ItemStore`): one `.md` per item — board-readable frontmatter + a canonical ```json block for lossless round-trip. |
| `engine/src/adapters/` | `LlmPort` adapters — `claude-cli` (headless `claude -p`), `anthropic-api` (raw-fetch Messages API), `ollama` (local daemon) — plus `resolveLlm(provider)` mapping a pipeline's `llmProvider` to the adapter. All late-bound from env. |
| `engine/src/pipelines/` | `PipelineCatalog` — lead_scout-style registry: disk scan of `pipelines/*.yaml` + a writable `enabled` overlay (so toggling never rewrites a repo file). `list`/`get`/`enabled`/`setEnabled`. `gauntlet-config.ts` holds the per-gauntlet executor knobs (verdict token, success verdicts) not on the Pipeline schema. |
| `engine/src/sources/` | `SourcePort` — inbound intake boundary (a pipeline's `source` field names the adapter). Concrete adapters (vault card scan, Firestore SR fetch) are a later human-gated step. |
| `engine/src/triage.ts` | `triageSentence` — intake classifier: routes a raw sentence to one of the enabled pipelines (via `LlmPort`) or `untriaged` below a confidence threshold. `makeTriagedItem` builds the Item (parked at the `triage` step if untriaged). |
| `engine/src/cli/run-once.ts` | `runPipelineOnce` — orchestration core: load/create item → run gate pipeline → fire the executor on a clean pass. Fully injected (testable). |
| `engine/src/cli.ts` | CLI shell: `refinery run --pipeline … --input "<sentence>"`. Parses args, wires real adapters, delegates to `runPipelineOnce`. |
| `pipelines/` | Pipelines (data; lead_scout-style — `pipeline`/`label`/`enabled`/`llmProvider` + `executorMode`/`executors` + gate list + optional `defaultTraits`). `project-ideation.yaml` (live e2e, greenfield); `app-refinement.yaml` (live, **brownfield** — bring an existing app into engineering-principles compliance; fixing-systems gate pipeline); `nightly-build.yaml` + `datax-sr.yaml` (the two gauntlets as pipelines, shipped `enabled: false` — strangler-fig). |

## Changelog
- 2026-07-11: **Board vault links are now Obsidian deep links.** The markdown renderer promotes OKF vault cross-links (`[text](path.md)`) and legacy `[[wikilinks]]` from non-navigable `.vlink` spans to `obsidian://open?vault=brain&file=…` anchors (vault name overridable via `$REFINERY_OBSIDIAN_VAULT`; heading anchors dropped — the plain obsidian URI has no heading support; full path stays on hover). Closes the 2026-06-15 follow-up "render wikilinks as obsidian:// links". Tests updated (5/5 markdown tests green; the 2 pre-existing failures in review/http-shell suites are untouched).
- 2026-07-11: `srGauntletDir` default derives from `hwc.paths.user.home` (`${paths.user.home}/700_datax/sr_gauntlet`) instead of a hardcoded `/home/eric` literal (Law 3 migration, value unchanged).
- **2026-06-27** — De-advertised the dormant `ollama` triage provider in the
  `triageProvider` option description after the container ollama stack was retired
  (`domains/ai/ollama/` removed). The `engine/src/adapters/ollama.ts` adapter and
  its tests are **retained** (inert: default is `claude-cli`, no pipeline selects
  ollama). Local-LLM provider intent parked at
  `brain wiki/nixos/idea-refinery-local-llm-provider.md`.
- **2026-06-24** — **Morning-review resilience** (`review/run.ts`), from the
  2026-06-24 nightly batch retro where 3/10 cards errored transiently and were
  then swept off the board. (1) **Per-card retry with backoff** (`withRetry`,
  2s→6s, 3 attempts) around the LLM-review + gh + save body — idempotent, so a
  retry never double-opens a PR or double-counts. (2) **Graduate-after-review**:
  a project graduates to `_finished/` only when *every* reviewable step (done +
  has a `run:` dir) carries a review record; an errored/unreviewed step now keeps
  the project on the active board so the next pass retries it instead of losing
  it. Deliberately NOT done here: a dedicated "errored" board lane — it would
  widen the `PrReview.verdict` union across the board renderer *and* the external
  `hwc_nightly_review` MCP tool; retry + graduate-gate + the loud nightly-builds
  notify cover the visibility gap with far smaller blast radius.
- **2026-06-19** — **Idea → spec → build assembly line + two-kanban board.** New native
  **`build`** pipeline (`pipelines/build.yaml` + `prompts/build.md`, `BUILD-VERDICT`) that
  implements a developed spec in the target repo. **Declarative chaining**: a pipeline can
  declare `next:` (project-ideation → build) and each item has a **`chain`** auto-advance
  switch — OFF stops at the spec for review, ON runs idea→spec→build unattended; plus a
  one-shot **"▸ build this"** button on a finished spec. `chainTo` seeds a deterministic
  `<id>-build` successor (carries the spec + repo + domain) and kicks it (gates in-board →
  native spool). The board `/` is now **two stacked kanbans** — Hopper (ideas) over
  Development (projects); `/hopper` 303-redirects to `/`. 142 tests pass.
- **2026-06-19** — **Completed cards show their outcome + next step (no more dead end).** A passed project-ideation card led with a pointless "▶ run pipeline now" + "No human action needed" and never showed the spec it produced. Now a done item leads with a **"✓ Done — outcome"** section that renders the developed spec inline (goal / steps / deliverable + the spec path) and states the **Next** step; re-run is demoted. Native items show branch/report + next step. Skipped middle gates (e.g. a greenfield gate that didn't apply) now render **"skipped"** instead of a misleading "pending". 135 tests pass.
- **2026-06-19** — **Parked cards are actionable + native target-repo picker.** A gate
  that parks/fails now emits an `asks` array (added to `BaseVerdictSchema` + enforced in
  `buildGatePrompt`) — the specific, concrete decisions the human must make, not a prose
  refusal. The parked card renders them as a **"To unblock, decide:"** checklist with an
  **"answer & continue"** box (fallback note for items that ran before asks were captured).
  Native pipelines (app-refinement) get a prominent **Target repo** picker (`POST /set-repo`
  → `payload.repo`), required when unset — this is what lets app-refinement actually
  execute (names the target app, e.g. `~/600_apps/<app>`); the run hint is now executor-aware.
  134 tests pass.
- **2026-06-19** — **Native execution via spool → privileged runner.** The hardened
  board (no repo/push access) no longer runs the `native` executor in-process: for a
  `native` pipeline it runs the **gates in-process** (LLM-only, works in the sandbox)
  and, on a clean pass, drops `<itemId>` in `/var/lib/refinery/native-run` and marks
  the item "queued for native execution". A privileged `refinery-native-runnow`
  path+service (runs as eric — ~/.ssh, ~/600_apps, ~/.claude; intentionally
  unsandboxed, mirrors `nightly-builds-runnow`) drains the spool and runs the new
  `refinery-run-native --id <id>` CLI, which builds the real native executor
  (worktree → headless claude → push via `native-factory.ts`) and finalizes the item
  (executorResult + passed/failed). External-gauntlet pipelines stay guarded.
  `refinery-run-native` is a 3rd esbuild bundle in the package. NOTE: app-refinement
  still needs `payload.repo` set to name its target app (a UI affordance is the next
  small step); without it the runner fails the item cleanly. 131 tests pass.
- **2026-06-19** — **UI redesign — the board mirrors the engine flow.** The main
  board is now **Flow** (retired "Gauntlet" as the board name; "Nightly" tab →
  "Overnight"). Every Project card carries a **gate-dot progress strip** (one dot
  per pipeline step — gates + executor — colored by per-step state from history),
  so where an item sits in its pipeline is glanceable. The item detail page gains
  a **pipeline node strip** (Triage → each gate → Executor → Done) where each node
  expands (native `<details>`, no JS) to its persisted gate verdict / executor
  result / triage confidence — surfacing state that was previously thrown away.
  Two new pages: **`/reference`** (the terminology canon + live pipelines) and
  **`/reviews`** (the morning PR-review verdicts, which had zero UI). `REFINERY_REVIEWS_DIR`
  wired into the board. 127 tests pass (+4 render).
- **2026-06-19** — **Terminology canon (full rename, code + UI + data).** Retired
  the overloaded vocabulary: `Profile`/`genre`/`manifest` → **Pipeline** (`item.pipeline`,
  `pipelines/*.yaml`, `PipelineCatalog`); the overloaded `phase` → **step** (pipeline
  position) + **stage** (hopper maturation); `phaseStatus` → **state**; `effector` →
  **Executor** (`execute`→`native`, `dispatch`→`gauntlet`, `write-spec`→`spec`);
  `executeMode` → `executorMode`; `nightly` flag → **schedule** (`now`|`nightly`).
  `MarkdownItemStore` carries a read-old/write-new migration shim so existing
  `/var/lib/refinery/items` survive; the enabled-overlay file stays `profiles.json`
  to preserve toggles. Env vars `REFINERY_PROFILES_DIR`/`_PROFILE_STATE` →
  `REFINERY_PIPELINES_DIR`/`_PIPELINE_STATE`. 117 tests pass (+2 migration). No
  behavior or UI-label change yet — that's the next slice.
- **2026-06-19** — Removed the dead `app/` board (the original slice-01/02
  read-only hopper). `index.nix` builds only `./engine`; nothing referenced
  `app/`/`@refinery/board`. First step of the engine-finish + UI-redesign arc.
- **2026-06-19** — `app-refinement` genre (brownfield app compliance) + profile
  `defaultTraits`. A profile may now declare the item traits to stamp at intake,
  so gate applicability is profile **data**, not a hardcoded intake literal —
  fixing a latent bug where `makeTriagedItem` stamped `mode: greenfield` on every
  item, making any brownfield genre's gates (chestertons-fence / principles-fix /
  blast-radius) silently self-skip. `app-refinement.yaml` declares
  `{mode: brownfield, touchesExistingCode, writeMode}` so its fixing-systems
  pipeline (chestertons-fence → blast-radius → principles-fix → premortem →
  admission-gates) fires; `executeMode: write`, `effectors: [execute]`. Runs
  daytime via the board's Run button by default; flag an item `nightly` only to
  batch it into the unattended overnight lane (the executor is not nightly-coupled).
  `ItemTraitsSchema` moved to `contracts.ts` (core contract; `gates/traits.ts`
  re-exports). +2 triage tests (115 pass).
- **2026-06-18** — Two-axis board + domains + per-card control. The board now
  models the Refinery as one chain with two axes (SR2 parity): **domain**
  (identity → card color + header tag, data-driven `domains.yaml`, auto-classified
  from the idea's `prefix:` and overridable per card) and **stage/status** (the
  lane). The **Hopper is a maturation kanban** — Captured → Shaping → Ready
  (stages stored in `phase` on untriaged items) — and a Ready idea promotes into
  **project-ideation** with an **immediate vs nightly** scheduling choice (no
  genre dropdown: project-ideation is the universal idea→spec refiner; downstream
  gauntlet routing is a later auto-step). Color is now **domain everywhere** (the
  genre/pipeline becomes a badge). New per-card controls: idea stage advancer +
  domain picker + promote; project genre re-pick + domain picker (status/run/
  nightly/delete from the prior pass). New `engine/src/domains.ts` (Zod registry
  + `classifyDomain`/`domainOf`), `domains.yaml`, `REFINERY_DOMAINS_FILE`, and
  `/stage` `/domain` routes (+ `schedule` on `/promote`). Engine 112/112 (+16).
- **2026-06-17** — Morning PR-review CLI exposed. The engine `buildNpmPackage`
  now esbuild-bundles a **second** entry point (`cli/morning-review.ts` →
  `morning-review.js`) and `makeWrapper`s it into `bin/refinery-morning-review`.
  A new read-only `package` module option publishes the built engine so the
  **nightly-builds** domain's `nightly-builds-review.service` runs the CLI
  (env-driven: `REFINERY_VAULT_DIR` / `REFINERY_DEFAULT_REPO` /
  `REFINERY_REVIEWS_DIR=/var/lib/refinery/reviews` / `REFINERY_LLM_PROVIDER`)
  without rebuilding the engine. Board service untouched. NOTE: the new bundle
  may shift `npmDepsHash` if engine deps change — rebuild centrally to capture.
- **2026-06-16** — SR run-now: board parity with nightly. The SR detail page now
  has a "▶ re-investigate now" button — `POST /sr/run-now` writes the SR's
  Firestore `srId` to a spool (`REFINERY_SR_RUNNOW_SPOOL=/var/lib/refinery/sr-run-now`,
  under the writable StateDirectory) which the `sr-gauntlet-runnow` path unit
  drains as `run.sh --id <srId>`. Same hardened-board pattern as nightly run-now
  (the board only writes the intent; a privileged path unit executes). `srId` is
  passed via the form (SR mirror items aren't in the store) and sanitized to a
  bare filename. New `requestSrRunNow` + `srRunNowSpoolDir`. Engine 90/90 (+3).
  Pairs with the 15-min auto-investigation poll in `domains/automation/sr-gauntlet`.
- **2026-06-15** — Gauntlet **dispatch contract** (refinery goal step 10): the
  modular seam. Instead of folding each gauntlet's executor *into* the engine
  (the leviathan path), the refinery *dispatches* to **standalone** gauntlets
  through one data-driven port and reads the result back. New
  `engine/src/gauntlets/` (`GauntletContract` Zod schema + `parseGauntletContract`,
  `ProcessPort`/`ResultReader` with real `nodeProcessPort`/`fsResultReader`,
  `loadGauntlets` registry) + `engine/src/effectors/dispatch.ts`
  (`makeDispatchEffector`: template `{id}`/`{date}` → trigger → parse verdict →
  `EffectorResult`; all IO injected). `gauntlets/sr_gauntlet.yaml` is the first
  contract (data only — nothing is executed). `execute.ts` left untouched as the
  native-execution fallback. A new gauntlet = one YAML file; parity is by
  construction (same `run.sh`). Engine 84/84 (+10). Board wiring (live dispatch +
  SR page) is a later, human-reviewed step.
- **2026-06-15** — Run button + auto-run: the board executes engine pipelines.
  Triaged engine items (e.g. `project-ideation`) previously parked at their first
  gate with nothing to advance them. New `POST /run` + a Run button on the detail
  page invoke the engine runner (`runGenreOnce`: gates → integrate effector) on
  the item, reusing the CLI's wiring; it's fire-and-forget (item flips to a new
  `running` status + lane; result shows on refresh). A new per-profile `autoRun`
  flag makes a genre run automatically on intake instead of waiting for the button
  (the mechanism for event-driven genres like incoming SR tickets). `write-spec`
  is the wired effector; genres whose effector isn't board-runnable yet (SR's
  `execute`) fail loud and park with a clear reason. Specs land in
  `REFINERY_SCRATCH_DIR` (`/var/lib/refinery/specs`). Engine 74/74 (+4).
- **2026-06-15** — claude-cli triage authenticates on the Claude subscription.
  The home-masked service (`ProtectHome=tmpfs`) couldn't reach `~/.claude`, so
  intake items parked at `triage` (`response was not JSON` — headless `claude`
  got no creds). Bind `~/.claude` + `~/.claude.json` **read-only** back over the
  masked home (gated on `triageProvider == "claude-cli"`) and set `HOME`, mirroring
  the nightly-builds runner — no API key, host refreshes the token in place. The
  rest of home stays masked.
- **2026-06-15** — OKF vault cross-links in rendered markdown. `shells/markdown.ts`
  now recognizes the OKF link standard — `[text](relative/path.md[#anchor])` —
  in card bodies and REPORTs (wikilinks are deprecated, so they are not special-
  cased). The board is home-masked (`ProtectHome=tmpfs`) and can't read arbitrary
  vault paths, and a relative href would 404 against `/project/…`, so these render
  as styled, non-navigable `.vlink` spans (path on hover) rather than dead links;
  http(s) links still render as real `<a>`. A `/note` viewer + read-only vault
  bind can promote them to live links once cards actually carry OKF links. Engine
  70/70 (+2).
- **2026-06-15** — Readable reports + self-explanatory cards. New dependency-free
  `shells/markdown.ts` (`mdToHtml`) renders REPORTs and card bodies as HTML in a
  `.md` block that **wraps** (no more clipped, raw-markdown `<pre>`). Nightly
  mirror cards now carry the card's `goal` (shown as a badge on the board + the
  detail header) and its full markdown **body** (rendered under a "Card" section)
  — so a card isn't just a filename slug. The `/report` view renders markdown.
  Engine 65/65.
- **2026-06-15** — Configurable caps + dedicated SR page. The per-gauntlet "max
  per run" caps now live in a runtime file (`/var/lib/refinery/caps.json`,
  `{nightly, sr}`) the board edits — both `run.sh` files read it (env value as
  fallback, so nothing breaks if absent), so `NB_MAX_CARDS` / `SRG_MAX_SRS` are
  no longer Nix-only. New **SR page** (`/sr`): mirrors the sr_gauntlet
  investigations as blue cards that link straight to their REPORT (a click-through
  mirror of the SR2 board), with its own cap form. SR cards moved off the
  Gauntlet onto `/sr`. Engine 63/63. (Service env finalized: passes
  `REFINERY_CAPS_FILE=/var/lib/refinery/caps.json`, replacing the dead
  `REFINERY_NIGHTLY_CONFIG` the engine never read.)
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
