#!/usr/bin/env bash
set -euo pipefail

AGENT_DIR="/home/eric/agents/morning-briefing"
OUTPUT_DIR="${AGENT_DIR}/output"
LOG_FILE="${AGENT_DIR}/logs/run.log"
LOCK_FILE="/tmp/morning-briefing.lock"

mkdir -p "${OUTPUT_DIR}" "${AGENT_DIR}/logs"

if [ -f "${LOCK_FILE}" ]; then
  pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    echo "$(date -Iseconds) SKIP: Previous run still active (PID ${pid})" >> "${LOG_FILE}"
    exit 0
  fi
  rm -f "${LOCK_FILE}"
fi
echo $$ > "${LOCK_FILE}"
trap 'rm -f "${LOCK_FILE}"' EXIT

echo "$(date -Iseconds) START: Morning briefing compilation" >> "${LOG_FILE}"

cd "${AGENT_DIR}"
RESULT=$(/etc/profiles/per-user/eric/bin/claude --print -p "Compile today's morning briefing. Write the JSON output file as specified in CLAUDE.md." 2>&1) || {
  echo "$(date -Iseconds) ERROR: Claude Code CLI failed" >> "${LOG_FILE}"
  echo "${RESULT}" >> "${LOG_FILE}"
  cat > "${OUTPUT_DIR}/briefing.json.tmp" << ERRJSON
{
  "generated_at": "$(date -Iseconds)",
  "error": true,
  "error_message": "Claude Code CLI failed to compile briefing",
  "sections": {},
  "alerts": [{"level": "critical", "section": "system", "message": "Briefing compilation failed — check logs"}]
}
ERRJSON
  mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
  exit 1
}

if [ -f "${OUTPUT_DIR}/briefing.json" ]; then
  ALERT_COUNT=$(jq '.alerts | length' "${OUTPUT_DIR}/briefing.json" 2>/dev/null || echo "?")
  echo "$(date -Iseconds) OK: Briefing compiled (${ALERT_COUNT} alerts)" >> "${LOG_FILE}"
else
  echo "$(date -Iseconds) WARN: Claude ran but no output file found" >> "${LOG_FILE}"
fi

tail -100 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"
