#!/usr/bin/env bash
# send-report.sh <run_dir> <status> <elapsed_s> <branch> <label>
#
# Post one nightly-builds card result to the #nightly-builds Discord webhook as
# ONE message: a verdict header (status, elapsed, branch), the report's Success
# criteria block as the scannable "info", then the full REPORT.md attached
# (click to read in Discord's file viewer — no download).
#
# Modeled on sr_gauntlet/send-report.sh. The webhook URL is read from the file
# named by $NB_DISCORD_WEBHOOK_FILE (the agenix mount of
# discord-webhook-nightly-builds, set by index.nix). Posting the report body as
# a file attachment is why this bypasses hwc-notify: the dispatcher is
# JSON-only and cannot carry a file.
#
# Exit 0 on success or graceful skip (no webhook / no report); the launcher
# falls back to a metadata-only notify() when this skips.
set -uo pipefail
RUN_DIR="$1"; STATUS="$2"; ELAPSED="${3:-?}"; BRANCH="${4:-?}"; LABEL="${5:-card}"

WEBHOOK_FILE="${NB_DISCORD_WEBHOOK_FILE:-/run/agenix/discord-webhook-nightly-builds}"
[ -r "$WEBHOOK_FILE" ] || { echo "SKIP: webhook unreadable ($WEBHOOK_FILE)"; exit 1; }
[ -f "$RUN_DIR/REPORT.md" ] || { echo "SKIP: $RUN_DIR/REPORT.md missing"; exit 1; }
command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "SKIP: curl/jq missing"; exit 1; }
WEBHOOK="$(cat "$WEBHOOK_FILE")"

case "$STATUS" in done|success) EMOJI="✅"; WORD="done" ;; *) EMOJI="❌"; WORD="failed" ;; esac

# Title: the report's first "# " heading (strip leading "# "), else the label.
TITLE=$(awk '/^# /{sub(/^# /,""); print; exit}' "$RUN_DIR/REPORT.md")
[ -n "$TITLE" ] || TITLE="$LABEL"
TITLE=$(printf '%s' "$TITLE" | head -c 150)

# The "info": the Success criteria block (lines between "## Success criteria"
# and the next "## "), non-blank. Falls back to the first 12 non-blank body
# lines after the first heading if the section is absent (free-form failures).
INFO=$(awk '/^## Success criteria/{f=1;next} /^## /{f=0} f && NF' "$RUN_DIR/REPORT.md")
if [ -z "$INFO" ]; then
  INFO=$(awk 'NF && !/^#/ && !/^---/{print; n++} n>=12{exit}' "$RUN_DIR/REPORT.md")
fi

CONTENT="${EMOJI} **${LABEL}** — ${WORD} (${ELAPSED}s)
Branch: \`${BRANCH}\`
**${TITLE}**

${INFO}

📎 Full report attached below — click to read in Discord."

# Defensive: Discord rejects content > 2000 chars. Truncate UTF-8-safely.
CONTENT=$(python3 -c 'import sys; print(sys.argv[1][:1990])' "$CONTENT")

PAYLOAD=$(jq -nc --arg c "$CONTENT" '{content:$c, allowed_mentions:{parse:[]}}')
curl -fsS -m 20 --form-string "payload_json=$PAYLOAD" \
  -F "files[0]=@$RUN_DIR/REPORT.md;filename=REPORT-$(basename "$RUN_DIR").md;type=text/markdown" \
  "$WEBHOOK" >/dev/null || { echo "ERROR: Discord POST failed"; exit 1; }
echo "sent: $LABEL ($WORD) -> Discord"
