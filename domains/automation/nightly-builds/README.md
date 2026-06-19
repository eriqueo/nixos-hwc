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
- **2026-06-18** — Launcher re-run idempotency (`run.sh`). The disposable
  worktree is now created with `git worktree add -B` (was `-b`) after a
  `worktree prune`, so a card whose stable-named branch already exists from a
  prior **failed** attempt resets cleanly to BASE instead of dying in ~2s with a
  perpetual `failed: worktree` (a once-pushed card could never be re-run — the
  launcher force-removed the worktree but never the branch). `-B` only resets a
  disposable *local* branch; the launcher still uses a plain `push` (no
  force-push) so remote history / open PRs are never clobbered (gate 7/8 /
  run-wrapper rule 2). Sibling `sr_gauntlet/run.sh` uses `worktree add --detach`
  (no named branch) and is immune — left untouched.
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
