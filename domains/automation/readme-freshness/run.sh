#!/usr/bin/env bash
# domains/automation/readme-freshness/run.sh
#
# Weekly Law-12 drift report. Runs the README freshness linter against the repo
# working copy and POSTs a summary to hwc-notify (topic "nightly-builds" → the
# #nightly-builds Discord channel). Report-only — never edits a README.
#
# Env (set by the systemd unit; sane fallbacks for manual runs):
#   RF_REPO_DIR    repo working copy (default ~/.nixos)
#   RF_NOTIFY_URL  hwc-notify endpoint (default loopback :11600)

set -uo pipefail

REPO_DIR="${RF_REPO_DIR:-$HOME/.nixos}"
NOTIFY_URL="${RF_NOTIFY_URL:-http://127.0.0.1:11600/notify}"
LINTER="$REPO_DIR/workspace/tools/readme-freshness.sh"

[ -x "$LINTER" ] || { echo "FATAL: linter not found/executable at $LINTER"; exit 1; }
cd "$REPO_DIR" || { echo "FATAL: cannot cd to $REPO_DIR"; exit 1; }

# stdout = STALE lines (clean list); stderr = "STALE: n / total domain READMEs".
TMP_ERR="$(mktemp)"
trap 'rm -f "$TMP_ERR"' EXIT
stdout="$(workspace/tools/readme-freshness.sh 2>"$TMP_ERR")"; rc=$?
summary="$(cat "$TMP_ERR")"
[ -n "$summary" ] || summary="(no summary; linter exit $rc)"

case "$rc" in
  0) prio=5; title="✅ README freshness — all current" ;;
  1) prio=3; title="📋 README freshness — $summary" ;;
  *) prio=2; title="⚠️ README freshness — linter error (exit $rc)" ;;
esac

if [ -n "$stdout" ]; then
  body="$summary

$stdout"
else
  body="$summary"
fi

payload=$(jq -nc --arg t "$title" --arg b "$body" --argjson p "$prio" \
  '{topic:"nightly-builds", title:$t, body:$b, priority:$p, source:"readme-freshness", tags:["readme-freshness","law-12"]}')

curl -fsS -m 8 -X POST -H 'content-type: application/json' -d "$payload" "$NOTIFY_URL" >/dev/null \
  && echo "report posted: $title" \
  || { echo "WARN: notify POST failed ($NOTIFY_URL)"; exit 0; }
