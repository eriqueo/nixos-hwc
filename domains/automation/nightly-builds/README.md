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
├── send-report.sh    # Rich per-card Discord report (REPORT.md attached)
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
