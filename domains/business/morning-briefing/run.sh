#!/usr/bin/env bash
# domains/business/morning-briefing/run.sh
#
# Step 1: Claude Code CLI → MCP servers → output/briefing.json
# Step 2: notmuch → Claude → output/mail-triage.json
# Step 3: jq merge → .mail_triage injected into briefing.json
# Step 4: copy output/briefing.json → dashboard/briefing.json for Caddy

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${AGENT_DIR}/output"
DASHBOARD_DIR="${AGENT_DIR}/dashboard"
PROMPTS_DIR="${AGENT_DIR}/prompts"
LOG_FILE="${AGENT_DIR}/logs/run.log"
LOCK_FILE="/tmp/morning-briefing.lock"
CLAUDE_BIN="/etc/profiles/per-user/eric/bin/claude"

mkdir -p "${OUTPUT_DIR}" "${DASHBOARD_DIR}" "${AGENT_DIR}/logs"

log() { echo "$(date -Iseconds) $*" >> "${LOG_FILE}"; }

# Lock
if [ -f "${LOCK_FILE}" ]; then
  pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    log "SKIP: Previous run still active (PID ${pid})"
    exit 0
  fi
  rm -f "${LOCK_FILE}"
fi
echo $$ > "${LOCK_FILE}"
trap 'rm -f "${LOCK_FILE}"' EXIT

log "START"
cd "${AGENT_DIR}"

# ── Step 0: Pre-flight ───────────────────────────────────────────────────────
if [ ! -x "${CLAUDE_BIN}" ]; then
  log "FATAL: Claude binary not found at ${CLAUDE_BIN}"
  cat > "${OUTPUT_DIR}/briefing.json.tmp" <<ERRJSON
{
  "generated_at": "$(date -Iseconds)",
  "error": true,
  "error_message": "Claude Code CLI not found at ${CLAUDE_BIN}",
  "sections": {},
  "alerts": [{"level": "critical", "section": "system", "message": "Claude Code CLI binary missing — cannot compile briefing"}]
}
ERRJSON
  mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
  cp "${OUTPUT_DIR}/briefing.json" "${DASHBOARD_DIR}/briefing.json"
  exit 1
fi
log "OK: Pre-flight passed (claude binary exists)"

# ── Step 1: Main briefing ─────────────────────────────────────────────────────
log "STEP 1: Main briefing (Claude Code CLI)..."
STEP1_START=$(date +%s)

TODAY="$(date +%Y-%m-%d)"
RESULT=$("${CLAUDE_BIN}" \
  --print \
  -p "Today is ${TODAY} ($(date '+%A, %B %-d, %Y')). Compile today's morning briefing as specified in CLAUDE.md. IMPORTANT: For the calendar section, call hwc_calendar_list with range='today' to get today's events from iCloud via khal."
  2>&1) || {
  log "ERROR: Claude Code CLI failed"
  echo "${RESULT}" >> "${LOG_FILE}"
  cat > "${OUTPUT_DIR}/briefing.json.tmp" <<ERRJSON
{
  "generated_at": "$(date -Iseconds)",
  "error": true,
  "error_message": "Claude Code CLI failed to compile briefing",
  "sections": {},
  "alerts": [{"level": "critical", "section": "system", "message": "Briefing compilation failed — check logs"}]
}
ERRJSON
  mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
  cp "${OUTPUT_DIR}/briefing.json" "${DASHBOARD_DIR}/briefing.json"
  exit 1
}

STEP1_END=$(date +%s)
STEP1_ELAPSED=$((STEP1_END - STEP1_START))
log "STEP 1: completed in ${STEP1_ELAPSED}s"

if [ -f "${OUTPUT_DIR}/briefing.json" ]; then
  # Stamp generated_at with the real time — don't trust Claude's timestamp
  NOW="$(date -Iseconds)"
  jq --arg ts "${NOW}" '.generated_at = $ts' \
    "${OUTPUT_DIR}/briefing.json" > "${OUTPUT_DIR}/briefing.json.tmp" \
  && mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
  ALERT_COUNT=$(jq '.alerts | length' "${OUTPUT_DIR}/briefing.json" 2>/dev/null || echo "?")
  log "OK: Main briefing compiled (${ALERT_COUNT} alerts)"

  # Validate minimum structure
  HAS_SECTIONS=$(jq 'has("sections") and (.sections | has("calendar")) and (.sections | has("jobs"))' \
    "${OUTPUT_DIR}/briefing.json" 2>/dev/null || echo "false")
  if [ "${HAS_SECTIONS}" != "true" ]; then
    log "WARN: briefing.json missing expected sections (calendar/jobs) — partial data, continuing"
  fi

  # ── Step 1b: Inject live khal calendar (overrides agent's stale data) ──────
  KHAL_BIN="/etc/profiles/per-user/eric/bin/khal"
  if [ -x "${KHAL_BIN}" ]; then
    log "STEP 1b: Injecting live khal calendar..."
    KHAL_JSON=$(${KHAL_BIN} list \
      --format='{start-date}T{start-time}|{end-date}T{end-time}|{title}|{location}|{all-day}' \
      today today 2>/dev/null \
      | python3 -c "
import sys, json
events = []
tz = '-06:00'
lines = sys.stdin.read().split('\n')
merged = []
for line in lines:
    line = line.strip()
    if not line:
        continue
    if len(line) >= 11 and line[4] == '-' and line[7] == '-' and 'T' in line[:11]:
        merged.append(line)
    elif merged:
        merged[-1] += ' ' + line
for line in merged:
    if '|' not in line:
        continue
    parts = line.split('|', 4)
    if len(parts) < 5:
        continue
    start, end, title, location, allday = [p.strip() for p in parts]
    is_allday = allday.lower() == 'true'
    ev = {
        'summary': title,
        'start': start + tz if not is_allday else start[:10],
        'end': end + tz if not is_allday else end[:10],
        'location': location if location else None,
        'allDay': is_allday
    }
    events.append(ev)
print(json.dumps({'events': events}))
" 2>/dev/null) && {
      if echo "${KHAL_JSON}" | jq empty 2>/dev/null; then
        jq --argjson cal "${KHAL_JSON}" '.sections.calendar = $cal' \
          "${OUTPUT_DIR}/briefing.json" > "${OUTPUT_DIR}/briefing.json.tmp" \
        && mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
        EV_COUNT=$(echo "${KHAL_JSON}" | jq '.events | length' 2>/dev/null || echo "?")
        log "OK: Calendar injected (${EV_COUNT} events from khal)"
      else
        log "WARN: khal output was not valid JSON — keeping agent calendar"
      fi
    } || log "WARN: khal calendar injection failed — keeping agent calendar"
  else
    log "WARN: khal binary not found — keeping agent calendar"
  fi
else
  log "WARN: Claude ran but no output/briefing.json found"
fi

# ── Step 2: Mail triage ───────────────────────────────────────────────────────
log "STEP 2: Mail triage..."
STEP2_START=$(date +%s)

MAIL_PROMPT="${PROMPTS_DIR}/mail-triage.txt"
MAIL_TRIAGE_JSON="${OUTPUT_DIR}/mail-triage.json"
WINDOW_HOURS=48

write_empty_triage() {
  local reason="${1:-}"
  local err_line=""
  [ -n "${reason}" ] && err_line="\"error\": \"${reason}\","
  cat > "${MAIL_TRIAGE_JSON}" <<EOF
{
  "generated_at": "$(date -Iseconds)",
  "query_window_hours": ${WINDOW_HOURS},
  "total_unread": 0,
  ${err_line}
  "buckets": { "urgent": [], "review": [], "noise": [] },
  "stats": { "urgent_count": 0, "review_count": 0, "noise_count": 0 }
}
EOF
}

if [ ! -f "${MAIL_PROMPT}" ]; then
  log "WARN: mail-triage.txt not found — skipping"
  write_empty_triage "prompt file not found"
else
  MAIL_JSON=$(notmuch search \
    --format=json \
    --limit=30 \
    "tag:inbox AND tag:unread AND date:${WINDOW_HOURS}h..today" \
    2>/dev/null || echo "[]")

  THREAD_COUNT=$(echo "${MAIL_JSON}" | jq 'length' 2>/dev/null || echo "0")
  log "mail-triage: ${THREAD_COUNT} unread threads"

  if [ "${THREAD_COUNT}" -eq 0 ]; then
    write_empty_triage ""
  else
    TRIAGE_INPUT="$(mktemp /tmp/mail-triage-XXXXXX.txt)"
    cat "${MAIL_PROMPT}" > "${TRIAGE_INPUT}"
    printf '\n\n' >> "${TRIAGE_INPUT}"
    echo "${MAIL_JSON}" >> "${TRIAGE_INPUT}"

    TRIAGE_RAW=$("${CLAUDE_BIN}" \
      --print \
      -p "$(cat "${TRIAGE_INPUT}")" \
      2>/dev/null); TRIAGE_EXIT=$?
    rm -f "${TRIAGE_INPUT}"

    [ ${TRIAGE_EXIT} -ne 0 ] && {
      log "WARN: Mail triage failed (exit ${TRIAGE_EXIT})"
      write_empty_triage "claude call failed"
      TRIAGE_RAW=""
    }

    if [ -n "${TRIAGE_RAW}" ]; then
      # Extract JSON object: strip markdown fences, preamble, and postamble
      TRIAGE_CLEAN=$(echo "${TRIAGE_RAW}" | tr -d '\r' \
        | sed -n '/^[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p')
      if echo "${TRIAGE_CLEAN}" | jq empty 2>/dev/null; then
        echo "${TRIAGE_CLEAN}" > "${MAIL_TRIAGE_JSON}"
        U=$(echo "${TRIAGE_CLEAN}" | jq '.stats.urgent_count' 2>/dev/null || echo "?")
        R=$(echo "${TRIAGE_CLEAN}" | jq '.stats.review_count' 2>/dev/null || echo "?")
        N=$(echo "${TRIAGE_CLEAN}" | jq '.stats.noise_count'  2>/dev/null || echo "?")
        log "mail-triage: OK (${U} urgent, ${R} review, ${N} noise)"
      else
        log "WARN: Mail triage returned invalid JSON — first 200 chars of raw:"
        log "$(echo "${TRIAGE_RAW}" | head -c 200)"
        write_empty_triage "invalid JSON from claude"
      fi
    fi
  fi
fi

STEP2_END=$(date +%s)
STEP2_ELAPSED=$((STEP2_END - STEP2_START))
log "STEP 2: completed in ${STEP2_ELAPSED}s"

# ── Step 3: Merge ─────────────────────────────────────────────────────────────
log "STEP 3: Merging..."

if [ -f "${OUTPUT_DIR}/briefing.json" ] && [ -f "${MAIL_TRIAGE_JSON}" ]; then
  jq --slurpfile triage "${MAIL_TRIAGE_JSON}" \
    '. + {"mail_triage": $triage[0]}' \
    "${OUTPUT_DIR}/briefing.json" \
    > "${OUTPUT_DIR}/briefing.json.tmp" \
  && mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
  log "OK: Merge complete"
else
  log "WARN: Skipping merge — missing files"
fi

# ── Step 4: Publish to dashboard/ ────────────────────────────────────────────
if [ -f "${OUTPUT_DIR}/briefing.json" ]; then
  # Use symlink if not already linked; otherwise cp with --remove-destination
  if [ -L "${DASHBOARD_DIR}/briefing.json" ]; then
    log "OK: Dashboard symlink already points to output"
  else
    cp --remove-destination "${OUTPUT_DIR}/briefing.json" "${DASHBOARD_DIR}/briefing.json"
    log "OK: Published to dashboard/"
  fi
fi

tail -100 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"
log "DONE"
