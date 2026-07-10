# Unified Triage Architecture

**Status**: Phase 1 (taxonomy) implemented · Phases 2–5 planned
**Date**: 2026-07-09
**Scope**: mail triage/tagging/sorting today; leads, DataX SRs, brain inbox as future conformers.
**Surfaces**: aerc · workbench TUI · briefing dashboard/email · (future) briefing web app

## The intent, extracted

Everything built so far — afew rules, the LLM morning triage, `triage/*` tags,
the workbench kanban, aerc's tag taxonomy — converges on one unstated design:

> **Classification is a tag on the item's own store. AI and rules both write
> tags; every surface reads and writes the same tags; no surface owns the data.**

That's why the workbench can move a card and aerc sees it; why the briefing can
classify at 6am and the kanban shows it. The system was grown ad hoc, but the
intent is coherent and correct. This doc formalizes it so every current and
future triage domain has the same shape.

## Principles applied

| Principle | Application |
|---|---|
| Data-driven rendering | One taxonomy declaration; every consumer (rules, prompt, aerc colors, MCP constants) is *generated* from it. No hand-copied lists. |
| Hexagonal | Stores (notmuch, leads DB, SR store) at the center; MCP tools are the ports; aerc/workbench/web/briefing are shells. Shells never touch a store directly except through its tool. |
| Contracts before code | The Triage Surface Contract (below) is the interface every domain implements. Workbench's Universal Result Contract already validates it at the boundary. |
| Late binding | Buckets are re-read from live tags at render time (`hwc_mail_triage` reflectLiveBuckets) — cached JSON is content, tags are placement. This is the pattern for all domains. |
| Declarative over imperative | The taxonomy is a serializable data structure (Nix attrset → JSON). Verbs are declared in hub manifests (`card_actions`), not coded in the host. |

## Part 1 — One taxonomy (the drift-kill) · IMPLEMENTED

### The drift that existed

Four hand-kept copies of overlapping vocabulary:

1. `profiles/mail/home.nix` — `trashSenders` / `archiveSenders` (deterministic auto-sort)
2. `prompts/mail-triage.txt` — known-noise / known-review sender lists (LLM advisory), *divergent* from (1)
3. `domains/mail/aerc/parts/tags.nix` — category/flag tags + colors (Nix)
4. `domains/system/mcp/src/src/tools/mail.ts` — `CATEGORY_TAGS`, `FLAG_TAGS`, `TRIAGE_BUCKETS`, `SAVED_SEARCHES` (TypeScript)

Plus prose copies of the tag vocabulary inside the triage prompt.

### The fix

New module: **`domains/mail/taxonomy/`** → `hwc.mail.taxonomy.*` (namespace =
folder). It is pure data + derivations, no services:

- **`data.nix`** — the canonical registry:
  - `categories` — groups (business/money/personal/growth/system) → tags with
    display/spaceKey/dim/query. Colors stay OUT (palette roles only; aerc maps
    role→hex from the active theme — theme is presentation, not taxonomy).
  - `flags` — action/pending/keep.
  - `triage` — buckets `[urgent review noise]` + `tagPrefix = "triage/"`.
  - `senders` — ONE registry: `{ match, disposition, note? }` with
    `disposition ∈ trash | archive | newsletter | notification | finance |
    noise | review`. Deterministic dispositions feed notmuch rules;
    `noise`/`review` feed the LLM prompt; `trash`/`archive` senders are
    *also* emitted into the prompt's noise list (a sender the rules trash is
    by definition LLM-noise — one edit updates both layers).
  - `actionSubjects`.
- **Lane-independence (premortem 🔴1)**: `data.nix` is a PURE data file — no
  options, no `config`, no `lib` beyond basics. Both lanes import it directly:
  the HM mail modules (rules, aerc) AND the system-lane modules (MCP gateway,
  morning-briefing). Everything derives at *build time* from the same commit,
  so HM/system split-brain is structurally impossible. There is no runtime
  file handoff between lanes.
- **`lib.nix`** — pure derivation helpers over the data: per-disposition
  sender lists, the taxonomy JSON text, the prompt "Known senders" fragment.
- **`index.nix`** — the HM-lane options module (`hwc.mail.taxonomy.*`)
  exposing data + derived values to the other mail modules.
- **Consumers rewired**:
  - `hwc.mail.notmuch.rules.*` defaults now come from the taxonomy derivations
    (`lib.mkDefault`, so a machine can still override — but see risk 4).
    `profiles/mail/home.nix` drops its inline lists.
  - `aerc/parts/tags.nix` takes the taxonomy as an argument; group→palette
    mapping stays in aerc.
  - MCP gateway (`domains/system/mcp/index.nix`) bakes `mail-taxonomy.json`
    from the same import into the store and passes it via `MAIL_TAXONOMY_FILE`
    env; `mail.ts` loads it at startup for `CATEGORY_TAGS`/`FLAG_TAGS`/
    `TRIAGE_BUCKETS`/category saved-searches, keeping compiled-in constants
    only as a boot-robustness fallback with a startup log line naming which
    source loaded.
  - `prompts/mail-triage.txt` becomes a *template* (reasoning rules only);
    `morning-briefing/index.nix` renders template + generated senders fragment
    to a store path and passes it via `MAIL_PROMPT` env; `run.sh` honors the
    override.
- **Behavior preservation (premortem 🔴2)**: the registry's `disposition`
  field maps every sender to its EXACT current behavior — existing
  `trashSenders` → `trash`, `archiveSenders` → `archive`, prompt-only noise
  senders → `noise` (LLM-advisory only, never fed to auto-trash rules).
  Promoting a sender from `noise` to `trash` is a deliberate per-sender edit.
  The only auto-merge is the safe direction: trash/archive senders are also
  emitted into the prompt's noise list.

### Non-goals of Phase 1

- mail-janitor stays separate (Gmail-side deletion, deliberately independent).
- Proton dynamic label discovery stays runtime (it is late binding, not drift).
- No new tags, no re-tagging of existing mail.

## Part 2 — The Triage Surface Contract

Every triage domain (mail today; leads, SRs, brain inbox when conformed)
exposes exactly this shape through its MCP tool(s):

**Read** — `<domain>_triage` returns Universal Result Contract envelopes:
- `action=board` → `kind: kanban`, columns = buckets, cards carry
  `{id, label, priority?, summary?, suggested_action?, tags?}` (extra keys ride
  along per contract).
- `action=summary` → `kind: text` for briefing-style rollups.
- Placement MUST be re-derived from the live store at read time (the
  reflectLiveBuckets pattern), never from cached classification output.

**Write** — the domain's tool accepts `{action, id}` verbs:
- `set-triage` (move between buckets) — REQUIRED.
- Domain verbs (`archive`, `retag`, `mark_reviewed`, …) — optional, declared
  per-hub in workbench `card_actions` / `board_actions` (data, not host code).
- Writes go to the store (notmuch tag, leads DB row, SR typeId), so every
  other surface sees them on next read.

**Classify** — rules first, LLM second, both writing the same store:
- Deterministic layer runs on arrival (afew/rules; SR regex; lead source
  rules) — cheap, instant, no tokens.
- LLM layer runs on schedule + on demand (`action=retriage`) over the
  *unclassified/new* residue, writing the same bucket field. Prompt data
  (sender lists, taxonomy vocabulary) is GENERATED from the taxonomy, never
  hand-written into prompts.

**Store of truth per domain**: mail = notmuch tags · leads = leads DB
classification · SRs = sr_analyzer typeId/status · brain = frontmatter/folder.
No shared central database — the contract is shared, the stores are not.

## Part 3 — Surface work (config-level, phased)

### Phase 2 — aerc joins triage · IMPLEMENTED 2026-07-09
- Virtual folders `triage/urgent|review|noise` generated from the taxonomy
  (nested under one "triage" dirlist-tree node, inbox-scoped to mirror the
  kanban's window), in folders-sort after `people`.
- `<Space>tu/tr/tn` set-bucket keybinds (replace-set, identical semantics to
  the gateway's `set-triage`; `<Space>mt`/`<Space>gt` were taken by the tech
  category) and `<Space>gU/gR/gN` go-to-folder binds. Cheat sheet + which-key
  group label updated.

**Note (Phase 2): the server notmuch DB is canonical BY DESIGN.** notmuch
tag DBs are per-machine, but that's a non-issue here: all mail interaction
happens on hwc-server — the "aerc" used from the laptop is an SSH alias into
the server's aerc, and the briefing/gateway write there too. The laptop's
local notmuch DB (and its empty triage folders) is vestigial; every real
surface hits the one server DB. No tag sync (muchsync etc.) is needed.

### Phase 3 — workbench live + verbs · IMPLEMENTED 2026-07-10
- Laptop `gateway_url` was ALREADY wired (`WORKBENCH_GATEWAY_URL=
  http://hwc-server:6200` via HM env) — non-issue, like the aerc alias.
- Mail kanban migrated to the generic path: `hubs/mail.toml` declares
  `card_actions` (a=archive, d/x=trash confirm-gated, t=flag-action,
  u/r/n=triage-<bucket>) + `confirm_actions`; H/L moves dispatch
  `{action:"move", id, target}` to the tile source. `hwc_mail_triage`
  implements the verbs (notmuch tag ops); board reads drop de-inboxed
  threads. The mail-specific host route (`_dispatch_mail_write`) is deleted.
- Two latent write-safety bugs fixed: fixture fallback no longer applies to
  writes (a failed write raised, not faked), and a kanban with no
  `card_actions` is truly read-only (static a/d/t keys used to fire hwc_mail
  writes from ANY board).

### Phase 4 — on-demand classification · IMPLEMENTED 2026-07-10
- Classification logic extracted ONCE to
  `morning-briefing/triage-mail.sh` (`baseline` = the old Steps 2/2b/3;
  `delta` = classify ONLY unread threads with no `triage/*` tag, append to
  the cached board — manual moves survive).
- `mail-retriage.service` (own sandbox, same env pattern) runs `delta`;
  a systemd **path unit** watches `~/.cache/hwc/retriage.request`, which the
  gateway (`hwc_mail_triage action=retriage`) touches — fire-and-forget, no
  sudo/polkit, the LLM run never enters the gateway's sandbox.
- `hubs/mail.toml`: `board_actions = ["retriage"]`, hub key `R`.

### Phase 5 — conform the other domains + the web surface
- **DataX SRs · IMPLEMENTED 2026-07-10.** `datax_support_requests` grew the
  contract writes: `move` (id + target=phase id → sr_analyzer
  `PATCH /tickets/:id/move`), `delete` (confirm-gated, for spam/dupe SRs),
  and `retriage` (`POST /triage/all`, the analyzer's own rules pass).
  `hubs/datax.toml` declares `card_actions`/`confirm_actions`/
  `board_actions` — H/L now move SRs between phases from the workbench,
  persisted in the analyzer's store.
- **Leads · ASSESSED OUT (2026-07-10).** No leads board exists anywhere, and
  the lead-scout statuses (received/pending_jt/complete) are pipeline
  plumbing states — not triage buckets a human moves things between. Eric's
  real lead workflow lives in JobTread's stages. Forcing a kanban onto the
  plumbing would be conformance theater; revisit only if a genuine lead
  triage workflow emerges outside JT.
- Briefing web: the static dashboard stays read-only; interactivity = wire up
  the existing Next.js app at `~/600_apps/morning-briefing` (it already has
  MCP-backed tile implementations). Decision gate: run its own premortem;
  route/domain/deploy questions are out of scope here.

## Risk register (premortem 2026-07-09)

1. 🔴→prevented **HM/system split-brain** — original design had the
   system-lane gateway reading an HM-placed runtime JSON; if the server's HM
   half lagged or lacked the file, the gateway silently ran fallback constants
   forever (invisible re-drift). *Prevention*: lane-independent pure
   `data.nix` imported by both lanes at build time (see above); no runtime
   handoff. Fallback constants remain only for boot robustness, with a
   startup log naming the loaded source.
2. 🔴→prevented **Auto-trash behavior change from list unification** —
   prompt-noise senders reached the inbox today; a naive merge would
   auto-trash them on arrival. *Prevention*: `disposition` mapping preserves
   current behavior exactly; `noise` never feeds rules; promotion is a
   deliberate per-sender edit.
3. 🟡 **Prompt regression** — template+fragment restructuring could break the
   6am JSON parse or shift bucketing. *Detect*: diff the rendered prompt
   against the old file before deploy; run Step 2 manually once post-deploy;
   check `logs/mail-triage-raw.log` next morning. Soft failure (previous
   briefing kept).
4. 🟡 **aerc regression (daily driver)** — `tags.nix` signature change.
   *Detect*: diff generated aerc config before/after `hms`; refactor must be
   a rendered-config no-op.
5. 🟡 **`run.sh` MAIL_PROMPT wiring** — a mistake skips triage with a WARN.
   Covered by the same manual Step-2 test; skip path is loud in `run.log`.
6. 🟢 **Override re-fork** — a machine overriding `rules.*` directly diverges
   again. `mkDefault` + README note: edit taxonomy, not rules.
7. 🟢 **Custom-tag sidecar** — `tags-custom.json` (`<Space>M` flow) stays
   outside the taxonomy, untouched.
8. **Scope creep into a central triage engine** — resisted by design: shared
   contract, per-domain stores. If a future domain can't express its buckets
   as a field on its own store, it doesn't join; we don't build a sync layer.

## Known bugs adjacent (fix opportunistically)
- notmuch DB contains a literal tag `trash -inbox -unread` (a quoting bug from
  an old tagging call) — delete with
  `notmuch tag -- -"trash -inbox -unread" tag:"trash -inbox -unread"`.
- `savedSearches.urgent` in the old profile referenced nonexistent
  `tag:urgent` — superseded by `triage/urgent` in the taxonomy searches.

## Changelog
- 2026-07-09: Created. Phase 1 implemented (taxonomy module + four consumers).
