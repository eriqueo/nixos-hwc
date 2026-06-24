#!/usr/bin/env bash
# domains/automation/nightly-builds/run.sh
#
# Nightly gauntlet-card launcher. Two phases:
#   A. card-smith — draft new cards from _ideas.md (drafts only, never queued)
#   B. runner     — execute up to NB_MAX_CARDS cards with `status: queued`
#
# Each card runs in a disposable git worktree under /tmp/nightly/, with
# headless Claude Code. The agent commits on a branch and writes REPORT.md
# into the vault's runs/<date>-<slug>/ dir; this launcher pushes the branch
# and flips card status. Nothing here touches live services (gate 7).
#
# Usage: run.sh [--dry-run]

set -uo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="${NB_VAULT_DIR:-$HOME/900_vaults/brain}"
REPO_DIR="${NB_REPO_DIR:-$HOME/.nixos}"
MAX_CARDS="${NB_MAX_CARDS:-1}"
# Runtime override: the refinery board writes the cap to a shared caps file so it
# can be changed from the GUI. Falls back to NB_MAX_CARDS if absent/unreadable.
NB_CAPS_FILE="${NB_CAPS_FILE:-/var/lib/refinery/caps.json}"
if [ -r "$NB_CAPS_FILE" ] && command -v jq >/dev/null 2>&1; then
  _cap=$(jq -r '.nightly // empty' "$NB_CAPS_FILE" 2>/dev/null || true)
  case "$_cap" in (''|*[!0-9]*) ;; (*) MAX_CARDS="$_cap" ;; esac
fi
CLAUDE_BIN="${NB_CLAUDE_BIN:-/etc/profiles/per-user/eric/bin/claude}"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN="$(command -v claude || true)"

NB_DIR="$VAULT_DIR/_inbox/nightly_builds"
RUNS_DIR="$VAULT_DIR/runs"
# Morning-review records dir (refinery StateDirectory). run.sh clears a card's
# stale record when it (re)builds the card — see "Requeue hygiene" in Phase B.
# Overridable for tests.
REVIEWS_DIR="${NB_REVIEWS_DIR:-/var/lib/refinery/reviews}"
IDEAS_FILE="$NB_DIR/_ideas.md"
LOCK_FILE="/tmp/nightly-builds.lock"
DATE="$(date +%F)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# Targeted run (the refinery board's "▶ Run now" / IMMEDIATE mode): when
# NB_ONLY_GOAL is set, this launch executes ONLY that one project's queued
# step(s) and skips the card-smith drafting pass. Empty = the normal nightly
# run over every queued card. The lock below still serializes targeted kicks
# against the 01:30 timer, so the two never touch git concurrently.
ONLY_GOAL="${NB_ONLY_GOAL:-}"
# Allow `run.sh <goal-folder-name>` as an alternative to the env var (but not
# the --dry-run flag, which keeps its meaning).
if [ -n "${1:-}" ] && [ "${1:-}" != "--dry-run" ]; then ONLY_GOAL="$1"; fi

mkdir -p "$RUNS_DIR"
LOG_FILE="$RUNS_DIR/_launcher.log"
log() { echo "$(date -Iseconds) $*" | tee -a "$LOG_FILE"; }

# hwc-notify HTTP endpoint (loopback). Run results POST here as topic
# "nightly-builds"; routes.nix fans that to the #nightly-builds Discord channel.
NOTIFY_URL="${NB_NOTIFY_URL:-http://127.0.0.1:11600/notify}"

# notify <priority> <title> <body> — best-effort run-result post. Never fails
# the run (the branch + REPORT are the durable output; a notify is a courtesy).
# Skipped on --dry-run; degrades quietly if curl/jq or the dispatcher are absent.
notify() {
  local priority="$1" title="$2" body="$3" payload
  if [ "$DRY_RUN" -eq 1 ]; then log "DRY: would notify [$priority] $title"; return 0; fi
  command -v curl >/dev/null 2>&1 || { log "WARN: curl missing — notify skipped"; return 0; }
  command -v jq   >/dev/null 2>&1 || { log "WARN: jq missing — notify skipped"; return 0; }
  payload=$(jq -nc --arg t "$title" --arg b "$body" --argjson p "$priority" \
    '{topic:"nightly-builds", title:$t, body:$b, priority:$p, source:"nightly-builds", tags:["nightly-builds"]}')
  curl -fsS -m 8 -X POST -H 'content-type: application/json' \
    -d "$payload" "$NOTIFY_URL" >/dev/null 2>&1 \
    && log "notify sent: $title" \
    || log "WARN: notify POST failed ($NOTIFY_URL)"
}

# ── Lock ─────────────────────────────────────────────────────────────────────
if [ -f "$LOCK_FILE" ]; then
  pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    log "SKIP: previous run still active (PID $pid)"
    exit 0
  fi
  rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log "START dry_run=$DRY_RUN vault=$VAULT_DIR repo=$REPO_DIR max_cards=$MAX_CARDS"

# ── Pre-flight ───────────────────────────────────────────────────────────────
[ -x "$CLAUDE_BIN" ] || { log "FATAL: claude binary not found"; exit 1; }
[ -d "$NB_DIR" ]     || { log "FATAL: $NB_DIR missing (vault not synced?)"; exit 1; }
git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || { log "FATAL: $REPO_DIR is not a git repo"; exit 1; }

# Frontmatter field editor (avoids sed; edits `key: value` in YAML frontmatter)
set_field() { # set_field <file> <key> <value>
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys, re
path, key, value = sys.argv[1:4]
text = open(path).read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
if not m:
    sys.exit(f"no frontmatter in {path}")
fm = m.group(1)
pattern = re.compile(rf'^{re.escape(key)}:.*$', re.M)
line = f'{key}: {value}'
fm = pattern.sub(line, fm) if pattern.search(fm) else fm + f'\n{line}'
open(path, 'w').write(f'---\n{fm}\n---\n' + text[m.end():])
PYEOF
}

# Frontmatter field reader (mirrors set_field's parse — reads a `key: value` from
# YAML frontmatter only, never the body; strips surrounding quotes/whitespace).
get_field() { # get_field <file> <key>  -> prints value, empty if absent
  python3 - "$1" "$2" <<'PYEOF'
import sys, re
path, key = sys.argv[1:3]
text = open(path).read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
if not m:
    sys.exit(0)
mm = re.search(rf'^{re.escape(key)}:[ \t]*(.*)$', m.group(1), re.M)
if mm:
    print(mm.group(1).strip().strip('\'"'))
PYEOF
}

# ── Phase A: card-smith ──────────────────────────────────────────────────────
# Skipped entirely on a targeted run — "Run now" executes an existing card, it
# does not draft new ones.
if [ -n "$ONLY_GOAL" ]; then
  log "PHASE A: skipped (targeted run for '$ONLY_GOAL')"
elif [ -f "$IDEAS_FILE" ]; then
  # Ideas are bullet lines under the "## new" heading
  NEW_IDEAS=$(python3 - "$IDEAS_FILE" <<'PYEOF'
import sys, re
text = open(sys.argv[1]).read()
m = re.search(r'^## new\n(.*?)(?=^## |\Z)', text, re.S | re.M)
if m:
    bullets = [l for l in m.group(1).splitlines() if l.strip().startswith('- ')]
    print('\n'.join(bullets))
PYEOF
)
  if [ -n "$NEW_IDEAS" ]; then
    COUNT=$(echo "$NEW_IDEAS" | wc -l)
    log "PHASE A: card-smith — $COUNT new idea(s)"
    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY: would draft cards for:"; echo "$NEW_IDEAS" | tee -a "$LOG_FILE"
    else
      SMITH_PROMPT="$(cat "$AGENT_DIR/prompts/card-smith.md")

## Launch context
Today's date: $DATE
Target repo working copy: $REPO_DIR

## Ideas to draft
$NEW_IDEAS"
      (cd "$NB_DIR" && timeout 1800 "$CLAUDE_BIN" -p "$SMITH_PROMPT" \
        --dangerously-skip-permissions) \
        > "$RUNS_DIR/_card-smith-$DATE.log" 2>&1 \
        && { log "PHASE A: card-smith done (log: runs/_card-smith-$DATE.log)"; \
             notify 4 "🛠 Card-smith: $COUNT idea(s) drafted" \
               "Drafted from $COUNT new idea(s). Review _inbox/nightly_builds/ at morning review and flip draft → queued for anything ready (that flip is the Phase-4 gate)."; } \
        || { log "WARN: card-smith failed — ideas left in place"; \
             notify 2 "⚠️ Card-smith failed" "Card-smith pass errored on $COUNT idea(s); they were left under ## new. See runs/_card-smith-$DATE.log."; }
    fi
  else
    log "PHASE A: no new ideas"
  fi
else
  log "PHASE A: no _ideas.md — skipping"
fi

# ── Phase B: run queued cards ────────────────────────────────────────────────
# Targeted run: only this project's queued step(s). Normal run: every queued
# card across all projects, capped at MAX_CARDS.
if [ -n "$ONLY_GOAL" ]; then
  QUEUED=$(rg -l '^status: queued' "$NB_DIR/$ONLY_GOAL"/[0-9][0-9]-*.md 2>/dev/null | sort | head -n "$MAX_CARDS")
else
  QUEUED=$(rg -l '^status: queued' "$NB_DIR"/*/[0-9][0-9]-*.md 2>/dev/null | sort | head -n "$MAX_CARDS")
fi
if [ -z "$QUEUED" ]; then
  log "PHASE B: no queued cards"
  log "DONE"
  exit 0
fi

mkdir -p /tmp/nightly

for CARD in $QUEUED; do
  SLUG="$(basename "$CARD" .md)"
  GOAL="$(basename "$(dirname "$CARD")")"
  RUN_NAME="$DATE-$GOAL-$SLUG"
  RUN_DIR="$RUNS_DIR/$RUN_NAME"
  WT="/tmp/nightly/$RUN_NAME"

  # Branch: prefer the card's declared "PR to branch `x`"; fall back to nightly/.
  # `head -1`: -m1 stops after the first matching LINE, but a single line may hold
  # two `branch `x`` refs (e.g. a requeue card naming the old + new branch); take
  # only the first match so BRANCH is never a multi-line string (worktree add fails).
  BRANCH=$(rg -o -m1 'branch `([^`]+)`' -r '$1' "$CARD" 2>/dev/null | head -1 || true)
  [ -n "$BRANCH" ] || BRANCH="nightly/$RUN_NAME"

  # Target repo: a card may declare `repo: <path>` in its frontmatter to run
  # against a repo other than the default ($REPO_DIR, i.e. ~/.nixos). Absent =
  # the default, so existing cards are byte-identical. A declared-but-invalid
  # repo fails the card here (fail-loud) rather than silently using the default.
  CARD_REPO=$(get_field "$CARD" repo)
  CARD_REPO="${CARD_REPO:-$REPO_DIR}"
  if ! git -C "$CARD_REPO" rev-parse --git-dir >/dev/null 2>&1; then
    log "ERROR: card $GOAL/$SLUG declares repo '$CARD_REPO' which is not a git repo — card marked failed"
    set_field "$CARD" status "failed: repo"
    continue
  fi

  log "PHASE B: card=$GOAL/$SLUG repo=$CARD_REPO branch=$BRANCH run=$RUN_NAME"

  # Requeue hygiene: this queued card is about to be (re)built, so any existing
  # morning-review record for it describes STALE work (a prior attempt / a closed
  # PR). Delete it now so the morning pass re-reviews fresh — otherwise the review
  # CLI's idempotent-skip keeps the old record, and the graduate-gate then sees a
  # record and graduates the project on stale data (live-hit 2026-06-24: the
  # reconcile-script requeue left a record pointing at closed PR #65, so the v2
  # work was skipped and the goal graduated unreviewed). Filename mirrors the
  # engine's safeReviewId("<goal>/<slug>"): the slug drops its NN- prefix and the
  # id's "/" becomes "-". Goals/slugs are kebab, so this matches exactly.
  CARD_SLUG="${SLUG#[0-9][0-9]-}"
  STALE_REC="$REVIEWS_DIR/${GOAL}-${CARD_SLUG}.json"
  if [ -f "$STALE_REC" ]; then
    rm -f "$STALE_REC" && log "PHASE B: cleared stale review record ($STALE_REC) — card is being rebuilt"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: would run card $CARD in worktree $WT"
    continue
  fi

  mkdir -p "$RUN_DIR"
  set_field "$CARD" status running
  set_field "$CARD" run "runs/$RUN_NAME/"

  # Fresh worktree based on the repo's default branch. Refresh remotes first
  # (best-effort), then resolve the base from origin/HEAD with a fallback chain —
  # don't assume "main": CARD_REPO may be any repo (kidpix is main, but other
  # repos could be master). All candidates are local remote-tracking refs, so
  # this still resolves if the fetch failed (matching the old offline fallback).
  git -C "$CARD_REPO" fetch origin 2>>"$LOG_FILE" \
    || log "WARN: fetch failed for $CARD_REPO — basing on last-known remote refs"
  BASE=$(git -C "$CARD_REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$BASE" ] || ! git -C "$CARD_REPO" rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
    BASE=""
    for cand in origin/main origin/master main master; do
      if git -C "$CARD_REPO" rev-parse --verify -q "$cand" >/dev/null 2>&1; then BASE="$cand"; break; fi
    done
  fi
  if [ -z "$BASE" ]; then
    log "ERROR: no base branch found in $CARD_REPO — card marked failed"
    set_field "$CARD" status "failed: base-branch"
    continue
  fi
  # Re-run idempotency: a prior (failed) attempt leaves a stale worktree and a
  # stable-named branch behind. For an overnight gauntlet, failing one night and
  # being re-queued the next morning is the *normal* lifecycle, so the re-run
  # must succeed regardless of state a prior run left behind. Remove this run's
  # worktree path, prune dangling registrations, then create-or-RESET the local
  # branch to BASE with `-B`. A plain `-b` dies on a pre-existing branch — that
  # was the old perpetual "failed: worktree" wedge (a once-pushed card could
  # never be re-run). `-B` only ever resets a *disposable local* branch; we
  # never force-push (the plain `push` below preserves remote history — gate 7/8
  # / run-wrapper rule 2). sr_gauntlet/run.sh uses `worktree add --detach` (no
  # named branch) and is immune to this class of bug.
  git -C "$CARD_REPO" worktree remove --force "$WT" 2>/dev/null
  git -C "$CARD_REPO" worktree prune 2>/dev/null
  # Reclaim-on-rerun: a prior run (usually on an earlier date — the worktree
  # path is date-stamped) may still hold $BRANCH checked out in its own
  # worktree, and `-B` refuses to reset a branch that is checked out elsewhere.
  # Reclaim ONLY that one worktree. Other date-stamped leftovers are deliberate
  # (morning inspection of cards we are NOT re-running) and are never touched.
  HELD_WT=$(git -C "$CARD_REPO" worktree list --porcelain 2>/dev/null \
    | awk -v b="branch refs/heads/$BRANCH" \
        '/^worktree /{wt=substr($0,10)} $0==b{print wt}')
  if [ -n "$HELD_WT" ] && [ "$HELD_WT" != "$WT" ]; then
    git -C "$CARD_REPO" worktree remove --force "$HELD_WT" 2>>"$LOG_FILE" \
      && log "PHASE B: reclaimed stale worktree holding $BRANCH ($HELD_WT)"
  fi
  if ! git -C "$CARD_REPO" worktree add -B "$BRANCH" "$WT" "$BASE" 2>>"$LOG_FILE"; then
    log "ERROR: worktree add failed for $BRANCH in $CARD_REPO — card marked failed"
    set_field "$CARD" status "failed: worktree"
    continue
  fi

  # Compose the prompt: wrapper (with placeholders filled) + full card body
  PROMPT_FILE="$RUN_DIR/prompt.md"
  python3 - "$AGENT_DIR/prompts/run-wrapper.md" "$CARD" "$PROMPT_FILE" \
    "$BRANCH" "$RUN_DIR" "$DATE" "$CARD_REPO" "$BASE" <<'PYEOF'
import sys
wrapper, card, out, branch, run_dir, date, repo, base = sys.argv[1:9]
text = open(wrapper).read()
text = (text.replace('{{BRANCH}}', branch).replace('{{RUN_DIR}}', run_dir)
            .replace('{{DATE}}', date).replace('{{REPO}}', repo).replace('{{BASE}}', base))
text += '\n\n---\n\n# THE CARD\n\n' + open(card).read()
open(out, 'w').write(text)
PYEOF

  # Per-card budget as the timeout. A card declares "Budget: ≤ N min"; honor it
  # (+50% margin) so a hung card can't starve the rest of a sequential batch — a
  # 45-min audit no longer gets the flat 5h ceiling. Falls back to NB_CARD_TIMEOUT
  # when no minute budget is parseable.
  CARD_MIN=$(rg -o -m1 '([0-9]+)[[:space:]]*min' -r '$1' "$CARD" 2>/dev/null | tail -1)
  if [ -n "$CARD_MIN" ] && [ "$CARD_MIN" -gt 0 ] 2>/dev/null; then
    CARD_TIMEOUT=$(( CARD_MIN * 90 ))   # N min × 60s × 1.5 margin
  else
    CARD_TIMEOUT="${NB_CARD_TIMEOUT:-18000}"
  fi
  log "PHASE B: launching agent (timeout ${CARD_TIMEOUT}s; card budget=${CARD_MIN:-none}min)..."
  START=$(date +%s)
  (cd "$WT" && timeout "$CARD_TIMEOUT" "$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" \
    --dangerously-skip-permissions) > "$RUN_DIR/agent-output.log" 2>&1
  AGENT_EXIT=$?
  ELAPSED=$(( $(date +%s) - START ))
  log "PHASE B: agent exited $AGENT_EXIT after ${ELAPSED}s"

  # Push whatever was committed (a failed run's partial branch is still
  # reviewable — gate 8). Only push if the branch has commits beyond base.
  if [ -n "$(git -C "$WT" log --oneline "$BASE"..HEAD 2>/dev/null)" ]; then
    git -C "$WT" push -u origin "$BRANCH" >>"$LOG_FILE" 2>&1 \
      && log "PHASE B: pushed $BRANCH to origin" \
      || log "WARN: push failed — branch remains local in $WT"
  else
    log "PHASE B: no commits on $BRANCH"
  fi

  # Verdict (tri-state — the agent's self-verdict separates the three; the rule
  # lives in prompts/run-wrapper.md). The contract is differential-vs-BASE, not
  # absolute-green:
  #   success — own checks pass + no regression vs BASE                → done
  #   blocked — work committed + own checks pass, but the done-condition
  #             can't be EVALUATED in this venue (missing browser/lib/
  #             capability CI itself doesn't use). The board renders
  #             `blocked: …` as a force-queueable human decision — NOT a
  #             failure (the code is ready; the venue couldn't confirm it).
  #   failure — own checks fail / real regression / blast-radius / budget
  # An agent that stops cleanly also exits 0, so the self-verdict — not the
  # exit code alone — is what separates the three.
  VERDICT=$(rg -o 'NIGHTLY-VERDICT: (success|failure|blocked)' -r '$1' \
    "$RUN_DIR/agent-output.log" 2>/dev/null | tail -1)
  REPORT_PRESENT=$([ -f "$RUN_DIR/REPORT.md" ] && echo yes || echo no)
  if [ "$AGENT_EXIT" -eq 0 ] && [ "$REPORT_PRESENT" = yes ] && [ "$VERDICT" = "success" ]; then
    set_field "$CARD" status done
    set_field "$CARD" pr "branch \`$BRANCH\` (pushed; open PR at morning review)"
    log "PHASE B: card $SLUG done"
    # Rich Discord post: verdict header + Success-criteria + full REPORT.md
    # attached. Falls back to a metadata-only notify() if the sender can't run.
    "$AGENT_DIR/send-report.sh" "$RUN_DIR" done "$ELAPSED" "$BRANCH" "$GOAL/$SLUG" >>"$LOG_FILE" 2>&1 \
      || notify 5 "✅ $GOAL/$SLUG — done (${ELAPSED}s)" \
        "Branch \`$BRANCH\` pushed to origin. Open the PR at morning review.
Report: runs/$RUN_NAME/REPORT.md"
  elif [ "$AGENT_EXIT" -eq 0 ] && [ "$REPORT_PRESENT" = yes ] && [ "$VERDICT" = "blocked" ]; then
    # Venue-blocked: the work is committed and the card's own checks pass, but
    # the done-condition can't be confirmed here. NOT a failure — a human
    # decides at morning review (usually: open/merge the pushed branch). The
    # board treats `blocked: …` as a force-queueable, non-dead-end state.
    set_field "$CARD" status "blocked: done-condition unverifiable in venue — see report"
    set_field "$CARD" pr "branch \`$BRANCH\` (pushed; venue could not confirm — human decides)"
    log "PHASE B: card $SLUG BLOCKED (venue) — see $RUN_DIR/REPORT.md"
    "$AGENT_DIR/send-report.sh" "$RUN_DIR" blocked "$ELAPSED" "$BRANCH" "$GOAL/$SLUG" >>"$LOG_FILE" 2>&1 \
      || notify 3 "⚠️ $GOAL/$SLUG — blocked: venue can't confirm (${ELAPSED}s)" \
        "Code committed + the card's own checks pass, but the done-condition can't be evaluated in this venue.
Branch \`$BRANCH\` pushed (reviewable). A human decides at morning review.
Report: runs/$RUN_NAME/REPORT.md"
  else
    set_field "$CARD" status "failed: exit=$AGENT_EXIT verdict=${VERDICT:-none} report=$REPORT_PRESENT"
    log "PHASE B: card $SLUG FAILED — see $RUN_DIR/agent-output.log"
    # If a (partial) REPORT.md exists, post it richly — the failure report is
    # exactly what you want to read. Otherwise fall back to metadata notify().
    "$AGENT_DIR/send-report.sh" "$RUN_DIR" failed "$ELAPSED" "$BRANCH" "$GOAL/$SLUG" >>"$LOG_FILE" 2>&1 \
      || notify 2 "❌ $GOAL/$SLUG — failed (${ELAPSED}s)" \
        "exit=$AGENT_EXIT verdict=${VERDICT:-none} report=$REPORT_PRESENT
Any partial commits were pushed to \`$BRANCH\` (reviewable, gate 8).
Logs: runs/$RUN_NAME/agent-output.log"
  fi
  # Worktree is left in place for morning inspection; next run recreates it.
done

tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
log "DONE"
