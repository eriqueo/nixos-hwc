#!/usr/bin/env bash
# domains/automation/readme-freshness/run.sh
#
# Weekly Law-12 job. Two stages:
#   1. Report — run the README freshness linter, POST a drift summary to
#      hwc-notify (topic "nightly-builds" → #nightly-builds Discord).
#   2. Auto-fix (RF_AUTO_FIX=1, only when drift exists) — a headless Claude
#      agent runs the `readme-refresh` skill in a disposable worktree off
#      origin/main, editing READMEs only. The launcher HARD-VERIFIES the diff is
#      READMEs-only before pushing the branch + opening a PR. PR review is the
#      human gate; this script never rebuilds and never touches live state.
#
# Env (set by the systemd unit; sane fallbacks for manual runs):
#   RF_REPO_DIR RF_NOTIFY_URL RF_AUTO_FIX RF_BRANCH_PREFIX RF_CLAUDE_BIN RF_FIX_TIMEOUT

set -uo pipefail

REPO_DIR="${RF_REPO_DIR:-$HOME/.nixos}"
NOTIFY_URL="${RF_NOTIFY_URL:-http://127.0.0.1:11600/notify}"
AUTO_FIX="${RF_AUTO_FIX:-0}"
BRANCH_PREFIX="${RF_BRANCH_PREFIX:-readme/auto-refresh}"
CLAUDE_BIN="${RF_CLAUDE_BIN:-/etc/profiles/per-user/eric/bin/claude}"
FIX_TIMEOUT="${RF_FIX_TIMEOUT:-7200}"
LINTER_REL="workspace/tools/readme-freshness.sh"

[ -x "$REPO_DIR/$LINTER_REL" ] || { echo "FATAL: linter not found at $REPO_DIR/$LINTER_REL"; exit 1; }
cd "$REPO_DIR" || { echo "FATAL: cannot cd to $REPO_DIR"; exit 1; }

# notify <priority> <title> <body> — best-effort; never fails the run.
notify() {
  local priority="$1" title="$2" body="$3" payload
  command -v curl >/dev/null 2>&1 || { echo "WARN: curl missing — notify skipped"; return 0; }
  command -v jq   >/dev/null 2>&1 || { echo "WARN: jq missing — notify skipped"; return 0; }
  payload=$(jq -nc --arg t "$title" --arg b "$body" --argjson p "$priority" \
    '{topic:"nightly-builds", title:$t, body:$b, priority:$p, source:"readme-freshness", tags:["readme-freshness","law-12"]}')
  curl -fsS -m 8 -X POST -H 'content-type: application/json' -d "$payload" "$NOTIFY_URL" >/dev/null \
    && echo "notify sent: $title" \
    || echo "WARN: notify POST failed ($NOTIFY_URL)"
}

# Count stale dirs from a linter stderr summary line ("STALE: n / total ...").
stale_count() { rg -o 'STALE: ([0-9]+)' -r '$1' <<<"$1" | head -1; }

# ── Stage 1: report ──────────────────────────────────────────────────────────
TMP_ERR="$(mktemp)"; trap 'rm -f "$TMP_ERR"' EXIT
stdout="$("$LINTER_REL" 2>"$TMP_ERR")"; rc=$?
summary="$(cat "$TMP_ERR")"; [ -n "$summary" ] || summary="(no summary; linter exit $rc)"

case "$rc" in
  0) prio=5; title="✅ README freshness — all current" ;;
  1) prio=3; title="📋 README freshness — $summary" ;;
  *) prio=2; title="⚠️ README freshness — linter error (exit $rc)" ;;
esac
[ -n "$stdout" ] && body="$summary

$stdout" || body="$summary"
notify "$prio" "$title" "$body"

# ── Stage 2: autonomous fix (only when drift exists) ─────────────────────────
if [ "$AUTO_FIX" != "1" ] || [ "$rc" -ne 1 ]; then
  echo "auto-fix skipped (AUTO_FIX=$AUTO_FIX rc=$rc)"; exit 0
fi
if [ ! -x "$CLAUDE_BIN" ]; then
  notify 2 "⚠️ README auto-fix — claude binary missing" "RF_CLAUDE_BIN=$CLAUDE_BIN not executable; reported $summary but could not fix."
  exit 0
fi

BEFORE="$(stale_count "$summary")"
STAMP="$(date +%F-%H%M)"
BRANCH="$BRANCH_PREFIX-$STAMP"
WT="/tmp/readme-refresh/$STAMP"
mkdir -p /tmp/readme-refresh

git fetch origin 2>/dev/null && BASE="origin/main" || BASE="main"
git worktree remove --force "$WT" 2>/dev/null
if ! git worktree add -b "$BRANCH" "$WT" "$BASE" 2>/dev/null; then
  notify 2 "❌ README auto-fix — worktree failed" "Could not create worktree on $BRANCH from $BASE. $summary unfixed."
  exit 0
fi

PROMPT="You are running UNATTENDED in a disposable git worktree of the nixos-hwc
repo, already on branch \`$BRANCH\` off $BASE. Today is $STAMP.

First read the skill file and follow it exactly:
  ~/.claude/skills/readme-refresh/SKILL.md

It tells you how to bring every stale domain README current (the detector is
$LINTER_REL). Constraints the launcher ENFORCES — it will REFUSE TO PUSH if you
break them, voiding the whole run:
- Modify \`domains/**/README.md\` files ONLY. One non-README file in your commits
  and nothing gets pushed.
- Never fabricate a changelog entry — derive each from the real git diff.
- Commit as you go: \`docs(<area>): refresh README changelog (Law 12)\`.
- Do NOT push, do NOT run gh, do NOT rebuild. The launcher pushes and opens the PR.
End your final message with exactly: NIGHTLY-VERDICT: success|failure"

echo "launching fix agent on $BRANCH (timeout ${FIX_TIMEOUT}s)..."
START=$(date +%s)
(cd "$WT" && timeout "$FIX_TIMEOUT" "$CLAUDE_BIN" -p "$PROMPT" --dangerously-skip-permissions) \
  > "$WT/.agent-output.log" 2>&1
AGENT_EXIT=$?
ELAPSED=$(( $(date +%s) - START ))
VERDICT=$(rg -o 'NIGHTLY-VERDICT: (success|failure)' -r '$1' "$WT/.agent-output.log" 2>/dev/null | tail -1)
echo "agent exited $AGENT_EXIT after ${ELAPSED}s verdict=${VERDICT:-none}"

# Any commits at all?
if [ -z "$(git -C "$WT" log --oneline "$BASE"..HEAD 2>/dev/null)" ]; then
  notify 2 "❌ README auto-fix — no changes (${ELAPSED}s)" \
    "Agent made no commits on \`$BRANCH\` (exit=$AGENT_EXIT verdict=${VERDICT:-none}). $summary still unfixed."
  git worktree remove --force "$WT" 2>/dev/null
  exit 0
fi

# ── HARD GUARD: the pushed diff must be READMEs-only ─────────────────────────
OFFENDERS="$(git -C "$WT" diff --name-only "$BASE"..HEAD | rg -v '(^|/)README\.md$' || true)"
if [ -n "$OFFENDERS" ]; then
  notify 1 "🛑 README auto-fix — blast-radius violation, NOT pushed" \
    "Agent committed non-README files on \`$BRANCH\`; refused to push. Worktree kept at $WT for inspection.
Offending paths:
$OFFENDERS"
  echo "BLAST RADIUS VIOLATION — not pushing. Worktree left at $WT"
  exit 0
fi

# Safe to push.
if ! git -C "$WT" push -u origin "$BRANCH" >/dev/null 2>&1; then
  notify 2 "⚠️ README auto-fix — push failed" "Branch \`$BRANCH\` is READMEs-only and committed but push failed; it remains in $WT."
  exit 0
fi

# After-count from the fixed tree.
AFTER="$(cd "$WT" && "$LINTER_REL" 2>&1 >/dev/null | rg -o 'STALE: ([0-9]+)' -r '$1' | head -1)"
NCOMMITS="$(git -C "$WT" rev-list --count "$BASE"..HEAD)"

PR_BODY="Autonomous README freshness refresh (Law 12). Generated by the weekly
\`readme-freshness\` service via the \`readme-refresh\` skill, running headless.

- Stale domain READMEs before: **${BEFORE:-?}** → after: **${AFTER:-?}**
- Commits: $NCOMMITS (READMEs-only — launcher-verified before push)

**Review focus:** spot-check that each \`## Changelog\` entry matches the actual
\`git log\` for that directory (the agent is instructed never to fabricate).

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

PR_URL="$(cd "$WT" && gh pr create --base main --head "$BRANCH" \
  --title "docs: autonomous README freshness refresh ($STAMP)" \
  --body "$PR_BODY" 2>/dev/null || true)"

git worktree remove --force "$WT" 2>/dev/null

if [ -n "$PR_URL" ]; then
  notify 5 "✅ README auto-fix — PR opened (${ELAPSED}s)" \
    "Stale ${BEFORE:-?} → ${AFTER:-?} across $NCOMMITS READMEs-only commit(s).
Review + merge: $PR_URL"
else
  notify 3 "✅ README auto-fix — branch pushed (PR open failed) (${ELAPSED}s)" \
    "Branch \`$BRANCH\` pushed (stale ${BEFORE:-?} → ${AFTER:-?}, $NCOMMITS commits) but \`gh pr create\` failed.
Open it: https://github.com/eriqueo/nixos-hwc/pull/new/$BRANCH"
fi
