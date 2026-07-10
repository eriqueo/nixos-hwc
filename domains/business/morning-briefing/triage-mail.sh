#!/usr/bin/env bash
# triage-mail.sh — THE mail classification step (Claude → buckets → tags).
#
# Shared by two callers so the classify/parse/tag logic exists exactly once
# (unified-triage Phase 4; docs/plans/unified-triage-architecture.md):
#   run.sh Step 2/2b/3      →  triage-mail.sh baseline
#   mail-retriage.service   →  triage-mail.sh delta
#
# Modes:
#   baseline  Classify ALL unread inbox threads from the last WINDOW_HOURS
#             (the 6am daily baseline). REPLACES output/mail-triage.json,
#             stamps triage/<bucket> tags (overwriting yesterday's — the daily
#             baseline is allowed to re-bucket), replaces .mail_triage in
#             briefing.json.
#   delta     Classify ONLY unread inbox threads with NO triage/* tag (the
#             intraday residue). Stamps their tags and APPENDS them to the
#             existing .mail_triage buckets — never touches already-classified
#             threads, so manual moves survive. No-op when nothing is new.
#
# Env (all late-bound with unit-provided values taking precedence):
#   MAIL_PROMPT   rendered prompt file (index.nix passes the store path built
#                 from the template + taxonomy fragment)
#   CLAUDE_BIN    claude CLI (default: per-user nix profile)
#   WINDOW_HOURS  baseline query window (default 48)
set -uo pipefail

MODE="${1:-baseline}"
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${AGENT_DIR}/output"
LOG_FILE="${AGENT_DIR}/logs/run.log"
MAIL_TRIAGE_JSON="${OUTPUT_DIR}/mail-triage.json"
BRIEFING_JSON="${OUTPUT_DIR}/briefing.json"
MAIL_PROMPT="${MAIL_PROMPT:-${AGENT_DIR}/prompts/mail-triage.txt}"
CLAUDE_BIN="${CLAUDE_BIN:-/etc/profiles/per-user/eric/bin/claude}"
WINDOW_HOURS="${WINDOW_HOURS:-48}"

NOTMUCH_BIN="/etc/profiles/per-user/eric/bin/notmuch"
command -v notmuch >/dev/null 2>&1 && NOTMUCH_BIN="$(command -v notmuch)"

log() { echo "$(date -Iseconds) [triage-${MODE}] $*" >> "${LOG_FILE}"; }

write_empty_triage() {
  # baseline only: an empty/failed classification still yields a valid file so
  # the merge and the readers never see a stale window. delta must NOT clobber.
  [ "${MODE}" = "delta" ] && return 0
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
  merge_baseline
}

# ── query per mode ────────────────────────────────────────────────────────────
if [ "${MODE}" = "delta" ]; then
  # Only never-classified threads — a delta run must not re-bucket anything.
  QUERY="tag:inbox AND tag:unread AND NOT (tag:triage/urgent OR tag:triage/review OR tag:triage/noise)"
else
  QUERY="tag:inbox AND tag:unread AND date:${WINDOW_HOURS}h..today"
fi

# ── merge helpers ─────────────────────────────────────────────────────────────
merge_baseline() {
  [ -f "${BRIEFING_JSON}" ] && [ -f "${MAIL_TRIAGE_JSON}" ] || { log "WARN: merge skipped — missing files"; return 0; }
  jq --slurpfile triage "${MAIL_TRIAGE_JSON}" \
    '. + {"mail_triage": $triage[0]}' \
    "${BRIEFING_JSON}" > "${BRIEFING_JSON}.tmp" \
  && mv "${BRIEFING_JSON}.tmp" "${BRIEFING_JSON}" \
  && log "merge: replaced .mail_triage in briefing.json"
}

merge_delta() {
  # Append the fresh threads to the existing buckets (dedupe by thread_id —
  # existing placement wins), recompute stats, bump generated_at.
  local fresh_json="$1"
  [ -f "${BRIEFING_JSON}" ] || { log "WARN: no briefing.json — delta merge skipped (tags are stamped; board picks them up at the next baseline)"; return 0; }
  jq --argjson fresh "${fresh_json}" --arg now "$(date -Iseconds)" '
    (.mail_triage // {generated_at: $now, query_window_hours: 0, total_unread: 0,
                      buckets: {urgent: [], review: [], noise: []},
                      stats: {urgent_count: 0, review_count: 0, noise_count: 0}}) as $cur
    | ([$cur.buckets.urgent[]?, $cur.buckets.review[]?, $cur.buckets.noise[]?
        | .thread_id]) as $known
    | {
        urgent:  ($cur.buckets.urgent  + [$fresh.buckets.urgent[]?  | select(.thread_id as $t | $known | index($t) | not)]),
        review:  ($cur.buckets.review  + [$fresh.buckets.review[]?  | select(.thread_id as $t | $known | index($t) | not)]),
        noise:   ($cur.buckets.noise   + [$fresh.buckets.noise[]?   | select(.thread_id as $t | $known | index($t) | not)])
      } as $merged
    | .mail_triage = ($cur + {
        generated_at: $now,
        total_unread: (($cur.total_unread // 0) + ($fresh.total_unread // 0)),
        buckets: $merged,
        stats: {
          urgent_count: ($merged.urgent | length),
          review_count: ($merged.review | length),
          noise_count:  ($merged.noise  | length)
        }
      })
  ' "${BRIEFING_JSON}" > "${BRIEFING_JSON}.tmp" \
  && jq empty "${BRIEFING_JSON}.tmp" 2>/dev/null \
  && mv "${BRIEFING_JSON}.tmp" "${BRIEFING_JSON}" \
  && jq '.mail_triage' "${BRIEFING_JSON}" > "${MAIL_TRIAGE_JSON}" \
  && log "merge: appended delta into .mail_triage"
}

# ── classify ──────────────────────────────────────────────────────────────────
if [ ! -f "${MAIL_PROMPT}" ]; then
  log "WARN: prompt not found at ${MAIL_PROMPT} — skipping"
  write_empty_triage "prompt file not found"
  exit 0
fi

MAIL_JSON=$("${NOTMUCH_BIN}" search --format=json --limit=30 "${QUERY}" 2>/dev/null || echo "[]")
THREAD_COUNT=$(echo "${MAIL_JSON}" | jq 'length' 2>/dev/null || echo "0")
log "${THREAD_COUNT} thread(s) to classify"

if [ "${THREAD_COUNT}" -eq 0 ]; then
  write_empty_triage ""
  exit 0
fi

TRIAGE_INPUT="$(mktemp /tmp/mail-triage-XXXXXX.txt)"
cat "${MAIL_PROMPT}" > "${TRIAGE_INPUT}"
printf '\n\n' >> "${TRIAGE_INPUT}"
echo "${MAIL_JSON}" >> "${TRIAGE_INPUT}"

TRIAGE_RAW=$("${CLAUDE_BIN}" --print -p "$(cat "${TRIAGE_INPUT}")" 2>/dev/null); TRIAGE_EXIT=$?
rm -f "${TRIAGE_INPUT}"

if [ ${TRIAGE_EXIT} -ne 0 ]; then
  log "WARN: claude failed (exit ${TRIAGE_EXIT})"
  write_empty_triage "claude call failed"
  exit 1
fi

# Extract the JSON object with node: whole output · fenced block · brace span
# (same tolerant parse the 6am run stabilized on — see run.sh history 2026-07-08).
TRIAGE_CLEAN=$(echo "${TRIAGE_RAW}" | node -e '
  const s = require("fs").readFileSync(0, "utf8");
  const tryParse = (t) => { try { return JSON.stringify(JSON.parse(t)); } catch { return null; } };
  let r = tryParse(s);
  if (!r) { const m = s.match(/```(?:json)?\s*([\s\S]*?)```/); if (m) r = tryParse(m[1]); }
  if (!r) { const a = s.indexOf("{"), b = s.lastIndexOf("}"); if (a >= 0 && b > a) r = tryParse(s.slice(a, b + 1)); }
  if (r) process.stdout.write(r); else process.exit(1);
' 2>/dev/null) || TRIAGE_CLEAN=""

if [ -z "${TRIAGE_CLEAN}" ] || ! echo "${TRIAGE_CLEAN}" | jq empty 2>/dev/null; then
  echo "${TRIAGE_RAW}" > "${AGENT_DIR}/logs/mail-triage-raw.log"
  log "WARN: invalid JSON from claude — full raw saved to logs/mail-triage-raw.log"
  write_empty_triage "invalid JSON from claude (raw saved to logs/mail-triage-raw.log)"
  exit 1
fi

U=$(echo "${TRIAGE_CLEAN}" | jq '.stats.urgent_count' 2>/dev/null || echo "?")
R=$(echo "${TRIAGE_CLEAN}" | jq '.stats.review_count' 2>/dev/null || echo "?")
N=$(echo "${TRIAGE_CLEAN}" | jq '.stats.noise_count'  2>/dev/null || echo "?")
log "classified OK (${U} urgent, ${R} review, ${N} noise)"

# ── persist tags (both modes — placement source of truth is the notmuch tag) ──
if [ -x "${NOTMUCH_BIN}" ]; then
  TAGGED=0
  for bucket in urgent review noise; do
    case "${bucket}" in
      urgent) OPS=(+triage/urgent -triage/review -triage/noise) ;;
      review) OPS=(-triage/urgent +triage/review -triage/noise) ;;
      noise)  OPS=(-triage/urgent -triage/review +triage/noise) ;;
    esac
    while IFS= read -r tid; do
      [ -z "${tid}" ] && continue
      if "${NOTMUCH_BIN}" tag "${OPS[@]}" -- "thread:${tid}" 2>/dev/null; then
        TAGGED=$((TAGGED + 1))
      fi
    done < <(echo "${TRIAGE_CLEAN}" | jq -r --arg b "${bucket}" '.buckets[$b][]?.thread_id // empty' 2>/dev/null)
  done
  log "tagged ${TAGGED} thread(s) with triage/<bucket>"
else
  log "WARN: notmuch missing — tags not stamped"
fi

# ── merge into briefing.json ──────────────────────────────────────────────────
if [ "${MODE}" = "delta" ]; then
  merge_delta "${TRIAGE_CLEAN}"
else
  echo "${TRIAGE_CLEAN}" > "${MAIL_TRIAGE_JSON}"
  merge_baseline
fi

exit 0
