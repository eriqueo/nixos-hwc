# domains/automation/nightly-builds/

## Purpose

Unattended overnight execution of gauntlet cards: a card-smith pre-pass drafts
cards from `_ideas.md`, then queued cards run in disposable git worktrees via
headless Claude Code, push result branches, and write self-verifying `REPORT.md`
into the vault. A morning PR-review pass then reviews those branches and opens
PRs. The one privileged action — a workbench-triggered `nixos-rebuild switch` —
is gated and off by default.

## Boundaries

- **Manages**: the nightly runner service + timer (01:30), the targeted
  "run-now" drain (refinery board trigger), the morning PR-review service +
  timer (07:30), and the opt-in privileged rebuild-request consumer. The
  `run.sh`/`send-report.sh` launcher scripts.
- **Does NOT manage**: the refinery engine/board itself or the morning-review
  CLI source (→ `domains/automation/refinery/` — this domain only *runs* the
  exposed `refinery-morning-review` binary); the brain vault content
  (cards/ideas/runs live in the Syncthing'd vault); notification routing
  (→ `domains/notifications/`); the sr_gauntlet (→ `domains/automation/sr-gauntlet/`).

## Structure

```
domains/automation/nightly-builds/
├── index.nix         # Options + units: nightly-builds(.timer), -runnow(.path),
│                     #   -review(.timer), and the opt-in privileged -rebuild(.path).
│                     #   tmpfiles for the run-now / reviews / rebuild spools.
├── run.sh            # Nightly launcher: card-smith draft pass + queued-card runner
│                     #   (per-card timeout = the card's declared minute budget +50%)
├── send-report.sh    # Rich per-card Discord report (REPORT.md attached)
├── gen-index.sh      # Assemble a shared index README from per-card index.d/*.md
│                     #   fragments (run-wrapper rule 8 — avoids batch merge conflicts)
├── prompts/          # card-smith + run-wrapper prompts
└── README.md         # This file
```

### Units
| Unit | User | Trigger | Does |
|---|---|---|---|
| `nightly-builds.service` + `.timer` | eric | `onCalendar` (01:30) | run queued cards in worktrees |
| `nightly-builds-runnow.service` + `.path` | eric | refinery run-now spool | targeted single-goal run |
| `nightly-builds-review.service` + `.timer` | eric | `reviewOnCalendar` (07:30) | run `refinery-morning-review`, open PRs, write `/var/lib/refinery/reviews`, one digest notify |
| `nightly-builds-rebuild.service` + `.path` | **root** | rebuild-request spool | PRIVILEGED, opt-in: `nixos-rebuild switch` for an allowlisted host |

### Spools (all under `/var/lib/refinery`, group-writable for the eric-run board/MCP)
- `run-now/` — `<goal>` request files (board "▶ Run now").
- `reviews/` — morning-review JSON output (also feeds the board's `/morning`).
- `rebuild-request/` — `<host>` files (workbench rebuild button); only created
  + watched when `enableRebuildButton = true`.

## Namespace

`hwc.automation.nightlyBuilds.*` — `enable`, `onCalendar`, `reviewOnCalendar`,
`reviewLlmProvider`, `maxCards`, `vaultDir`, `repoDir`, `enableRebuildButton`.

## Changelog
- **2026-07-12** — **Morning-review digest was silently dropped when large.**
  hwc-notify's schema caps title at 200 / body at 4000 chars and 400-rejects
  oversized payloads; a long `errdetail` list pushed the digest body past the
  cap, so the notify vanished daily (journal: "schema validation failed:
  body too_big", 07:49 on 07-11 and 07-12) with only a WARN in the unit log.
  The review wrapper now truncates title/body at the edge before POSTing —
  the archived `_runs/*.json` keeps full detail.
- **2026-06-24** — Requeue hygiene + branch-parse robustness (found while running
  the post-hardening batch live):
  - **BRANCH parse takes the first match only** (`head -1`). `rg -m1` stops after
    the first matching *line*, but a requeue card can name two `` branch `x` ``
    refs on one line (old + new), so `rg -o` emitted both → multi-line BRANCH →
    `worktree add failed`.
  - **`run.sh` clears a card's stale morning-review record when it (re)builds it.**
    Review records are keyed by `<goal>/<slug>`, not by branch/run, so a requeued
    card kept its old record; the review CLI's idempotent-skip then never
    re-reviewed the new work and the graduate-gate graduated the project on stale
    data (live-hit: reconcile-script v2's record still pointed at closed PR #65).
    Now Phase B deletes `$REVIEWS_DIR/<goal>-<slug>.json` before rebuilding, so the
    next pass always re-reviews fresh. Covers every requeue path (board, manual,
    amendment) and needs no engine rebuild.
- **2026-06-24** — Hardening + observability from the 2026-06-24 media/hot batch
  retro (10/10 built, but delivery + verification leaked):
  - **Read-only `/mnt` (OS-enforced Gate 7).** `nightly-builds.service` and
    `-runnow` now set `ReadOnlyPaths = [ "/mnt" ]` — cards still READ media but
    physically cannot move/delete it; the guarantee was prompt-only before.
  - **Per-card budget = timeout.** `run.sh` parses the card's `Budget: ≤ N min`
    and uses N×60×1.5 as the agent `timeout` instead of the flat 5h, so a hung
    card can't starve a sequential batch (falls back to `NB_CARD_TIMEOUT`).
  - **Morning-review errors persist + go loud.** `reviewRun` archives the CLI's
    full JSON (incl `.errors[]`) to `reviews/_runs/<ts>-morning-review.json`
    BEFORE the trap deletes it, and on `errors>0` raises the notify priority and
    quotes each error + warns a branch may have pushed without a PR. (Last run
    silently swallowed 3 review errors as a bare count.)
  - **Wrapper standing rules (apply to every card).** `prompts/run-wrapper.md`
    adds: (6) prove executable behavior by RUNNING it against a fixture, never
    grep-for-tokens — a script that parses clean but does nothing is `failure`;
    (7) bulk data → `RUN_DIR`, not the repo; (8) contribute to shared indexes via
    `<dir>/index.d/<slug>.md` fragments, assembled by `gen-index.sh`, never edit
    the shared file (kills batch add/add conflicts).
  - **New `gen-index.sh`** — generic fragment→README index assembler (idempotent).
- **2026-06-18** — Verdict contract: differential-vs-BASE + tri-state (the real
  fix). The gauntlet verdict was *absolute-green* — "done" required the whole
  suite to pass in the worker — so completed cards were mislabeled `failed`
  whenever the venue couldn't run a check (missing browser/system lib) or a test
  was already red on the base branch. Root cause: the verdict had an opinion
  about its environment. Rewritten in the **prompts** (the contract): a card is
  done when it *advanced without regressing `{{BASE}}`, judged only by what the
  venue can run* — NOT "all tests green". `prompts/run-wrapper.md` now: derives
  the runnable slice from the repo's CI config (`.github/workflows/*`, late
  binding — no hardcoded "chromium"), timeboxes every check (a hung browser
  install can't eat the budget), and requires *evidence* to exclude a failure (it
  must be run on `{{BASE}}` and quoted). Verdict is now **tri-state**:
  `success` / `blocked` (work committed + own checks pass, but the done-condition
  can't be evaluated here — a human decides; the board renders this
  force-queueable, not failed) / `failure`. `run.sh` parses the third token →
  `status: blocked: …`; `send-report.sh` gets a ⚠️ blocked case.
  `prompts/card-smith.md` now authors done-conditions venue-scoped + differential
  (not absolute-green). SR (`~/700_datax/sr_gauntlet/prompts/investigate.md`,
  separate repo) is **exempt + documented**: it's read-only (no diff/tests/BASE),
  so its `investigated`/`inconclusive` already embodies the invariant — note
  added there, no behavior change. Follow-up (deferred, not this pass): the
  refinery engine's `engine/src/effectors/execute.ts` replicates the same
  absolute-green verdict (`exitCode===0 && !timedOut && reportPresent &&
  verdictOk`) and already receives `base`; port the differential/tri-state
  contract there **with** its parity-harness when the engine adopts the
  gauntlets — it's inert today (run.sh is the live path) so it's left untouched.
- **2026-06-18** — Launcher re-run idempotency (`run.sh`). Re-running a card now
  works regardless of stale worktree/branch state a prior run left behind — the
  norm for an overnight gauntlet, where a card fails one night and is re-queued
  the next morning. The disposable worktree is created with `git worktree add
  -B` (was `-b`) after a `worktree prune`, so a card whose stable-named branch
  already exists from a prior **failed** attempt resets cleanly to BASE instead
  of dying in ~2s with a perpetual `failed: worktree` (a once-pushed card could
  never be re-run — the launcher force-removed the worktree but never the
  branch). Because the worktree path is date-stamped, a cross-day re-run also
  **reclaims** the one stale worktree still holding `$BRANCH` (parsed from
  `worktree list --porcelain`) before `-B` resets it — scoped to that single
  branch; other date-stamped leftovers are kept for morning inspection. `-B`
  only resets a disposable *local* branch; the launcher still uses a plain
  `push` (no force-push) so remote history / open PRs are never clobbered (gate
  7/8 / run-wrapper rule 2). Sibling `sr_gauntlet/run.sh` uses `worktree add
  --detach` (no named branch) and is immune — left untouched. (Pending: a
  one-time cleanup of 7 pre-existing stale `/tmp/nightly` worktrees — Phase 4.)
- **2026-06-17** — Added the morning PR-review pass and the opt-in privileged
  rebuild consumer. New options `reviewOnCalendar` (default `*-*-* 07:30:00`,
  Persistent=false, RandomizedDelaySec=120), `reviewLlmProvider`
  (default `claude-cli`), and `enableRebuildButton` (default `false`). New units
  `nightly-builds-review.service`/`.timer` (runs `refinery-morning-review` from
  the refinery `package` option — env-driven vault/repo/reviews/provider, HOME
  set for claude+gh creds, then one consolidated `nightly-builds` notify), and
  the root `nightly-builds-rebuild.service`/`.path` watching
  `/var/lib/refinery/rebuild-request/` → `nixos-rebuild switch --flake
  <repoDir>#<host>` with a fixed `["hwc-server","hwc-laptop"]` allowlist guard
  (validated before any interpolation; unknown hosts dropped, file content never
  evaluated). New tmpfiles for the reviews + rebuild spools.
- **(prior)** — Initial nightly runner + card-smith + run-now drain (no README
  existed before this entry; pre-existing Law-12 gap filled here).
