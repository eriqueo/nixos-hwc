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

  # Branch: prefer the card's declared "PR to branch `x`"; fall back to nightly/
  BRANCH=$(rg -o -m1 'branch `([^`]+)`' -r '$1' "$CARD" 2>/dev/null || true)
  [ -n "$BRANCH" ] || BRANCH="nightly/$RUN_NAME"

  log "PHASE B: card=$GOAL/$SLUG branch=$BRANCH run=$RUN_NAME"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: would run card $CARD in worktree $WT"
    continue
  fi

  mkdir -p "$RUN_DIR"
  set_field "$CARD" status running
  set_field "$CARD" run "runs/$RUN_NAME/"

  # Fresh worktree from origin/main (fall back to local main if fetch fails)
  git -C "$REPO_DIR" fetch origin 2>>"$LOG_FILE" \
    && BASE="origin/main" || { BASE="main"; log "WARN: fetch failed, basing on local main"; }
  git -C "$REPO_DIR" worktree remove --force "$WT" 2>/dev/null
  if ! git -C "$REPO_DIR" worktree add -b "$BRANCH" "$WT" "$BASE" 2>>"$LOG_FILE"; then
    log "ERROR: worktree add failed for $BRANCH — card marked failed"
    set_field "$CARD" status "failed: worktree"
    continue
  fi

  # Compose the prompt: wrapper (with placeholders filled) + full card body
  PROMPT_FILE="$RUN_DIR/prompt.md"
  python3 - "$AGENT_DIR/prompts/run-wrapper.md" "$CARD" "$PROMPT_FILE" \
    "$BRANCH" "$RUN_DIR" "$DATE" <<'PYEOF'
import sys
wrapper, card, out, branch, run_dir, date = sys.argv[1:7]
text = open(wrapper).read()
text = text.replace('{{BRANCH}}', branch).replace('{{RUN_DIR}}', run_dir).replace('{{DATE}}', date)
text += '\n\n---\n\n# THE CARD\n\n' + open(card).read()
open(out, 'w').write(text)
PYEOF

  log "PHASE B: launching agent (timeout ${NB_CARD_TIMEOUT:-18000}s)..."
  START=$(date +%s)
  (cd "$WT" && timeout "${NB_CARD_TIMEOUT:-18000}" "$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" \
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

  # Verdict: done only if the agent exited 0, wrote its report, AND declared
  # success itself (an agent that stops cleanly on an unsatisfiable card also
  # exits 0 — its self-verdict is what separates done from reviewable-failed)
  VERDICT=$(rg -o 'NIGHTLY-VERDICT: (success|failure)' -r '$1' \
    "$RUN_DIR/agent-output.log" 2>/dev/null | tail -1)
  if [ "$AGENT_EXIT" -eq 0 ] && [ -f "$RUN_DIR/REPORT.md" ] && [ "$VERDICT" = "success" ]; then
    set_field "$CARD" status done
    set_field "$CARD" pr "branch \`$BRANCH\` (pushed; open PR at morning review)"
    log "PHASE B: card $SLUG done"
    # Rich Discord post: verdict header + Success-criteria + full REPORT.md
    # attached. Falls back to a metadata-only notify() if the sender can't run.
    "$AGENT_DIR/send-report.sh" "$RUN_DIR" done "$ELAPSED" "$BRANCH" "$GOAL/$SLUG" >>"$LOG_FILE" 2>&1 \
      || notify 5 "✅ $GOAL/$SLUG — done (${ELAPSED}s)" \
        "Branch \`$BRANCH\` pushed to origin. Open the PR at morning review.
Report: runs/$RUN_NAME/REPORT.md"
  else
    set_field "$CARD" status "failed: exit=$AGENT_EXIT verdict=${VERDICT:-none} report=$([ -f "$RUN_DIR/REPORT.md" ] && echo yes || echo no)"
    log "PHASE B: card $SLUG FAILED — see $RUN_DIR/agent-output.log"
    # If a (partial) REPORT.md exists, post it richly — the failure report is
    # exactly what you want to read. Otherwise fall back to metadata notify().
    "$AGENT_DIR/send-report.sh" "$RUN_DIR" failed "$ELAPSED" "$BRANCH" "$GOAL/$SLUG" >>"$LOG_FILE" 2>&1 \
      || notify 2 "❌ $GOAL/$SLUG — failed (${ELAPSED}s)" \
        "exit=$AGENT_EXIT verdict=${VERDICT:-none} report=$([ -f "$RUN_DIR/REPORT.md" ] && echo yes || echo no)
Any partial commits were pushed to \`$BRANCH\` (reviewable, gate 8).
Logs: runs/$RUN_NAME/agent-output.log"
  fi
  # Worktree is left in place for morning inspection; next run recreates it.
done

tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
log "DONE"
