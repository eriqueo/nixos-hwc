#!/usr/bin/env bash
# One classification path for the morning brief and intraday retriage timer.
# Laya decides; policy, tags, durable human locks, and the case ledger live in
# System One's mail_classifier.py.
set -uo pipefail

MODE="${1:-baseline}"
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${AGENT_DIR}/output"
DASHBOARD_DIR="${AGENT_DIR}/dashboard"
LOG_FILE="${AGENT_DIR}/logs/run.log"
MAIL_TRIAGE_JSON="${OUTPUT_DIR}/mail-triage.json"
BRIEFING_JSON="${OUTPUT_DIR}/briefing.json"
CLASSIFIER_BIN="${CLASSIFIER_BIN:-/run/current-system/sw/bin/mail-classifier-runtime}"
NOTMUCH_BIN="${NOTMUCH_BIN:-/etc/profiles/per-user/eric/bin/notmuch}"
EMAIL_TO_KHAL="${EMAIL_TO_KHAL:-/etc/profiles/per-user/eric/bin/email-to-khal}"
LEDGER="${MAIL_CLASSIFIER_LEDGER:-/var/lib/hwc/mail-classifier/ledger.sqlite}"
SOCKET="${MAIL_CLASSIFIER_SOCKET:-/run/hwc-mail-classifier/laya.sock}"
DRAFT_DIR="${OUTPUT_DIR}/calendar-drafts"

log() { echo "$(date -Iseconds) [triage-${MODE}] $*" >> "${LOG_FILE}"; }

publish_dashboard() {
  if [ ! -f "${BRIEFING_JSON}" ]; then
    log "WARN: no combined briefing to publish"
    return 1
  fi

  # dashboard/briefing.json is a served derivative, never a second producer.
  # Copy to a sibling and rename so Caddy sees either the old complete document
  # or the new complete document, never a partial JSON write.
  cp --remove-destination "${BRIEFING_JSON}" "${DASHBOARD_DIR}/briefing.json.tmp" \
    && jq empty "${DASHBOARD_DIR}/briefing.json.tmp" \
    && mv "${DASHBOARD_DIR}/briefing.json.tmp" "${DASHBOARD_DIR}/briefing.json"
}

mkdir -p "${OUTPUT_DIR}" "${DRAFT_DIR}" "${DASHBOARD_DIR}" "$(dirname "${LOG_FILE}")"
chmod 700 "${DRAFT_DIR}"

if [ "${MODE}" = "publish" ]; then
  publish_dashboard
  exit $?
fi

if [ "${MODE}" != "baseline" ] && [ "${MODE}" != "delta" ]; then
  log "ERROR: unknown mode '${MODE}'"
  exit 2
fi

if [ ! -x "${CLASSIFIER_BIN}" ] || [ ! -S "${SOCKET}" ]; then
  log "WARN: Laya classifier unavailable; unclassified mail remains DO"
  jq -n --arg now "$(date -Iseconds)" '{
    schemaVersion: 2, generated_at: $now, provider: "laya",
    error: "classifier unavailable; unclassified mail remains DO",
    buckets: {do: [], did: [], look: [], junk: []},
    stats: {do_count: 0, did_count: 0, look_count: 0, junk_count: 0}
  }' > "${MAIL_TRIAGE_JSON}.tmp" && mv "${MAIL_TRIAGE_JSON}.tmp" "${MAIL_TRIAGE_JSON}"
else
  if "${CLASSIFIER_BIN}" run \
      --socket "${SOCKET}" \
      --db "${LEDGER}" \
      --notmuch "${NOTMUCH_BIN}" \
      --output "${MAIL_TRIAGE_JSON}" \
      --draft-dir "${DRAFT_DIR}" \
      --email-to-khal "${EMAIL_TO_KHAL}"; then
    log "classified with resident Laya model"
  else
    log "ERROR: classifier run failed; unclassified mail remains DO"
    exit 1
  fi
fi

if [ -f "${BRIEFING_JSON}" ]; then
  jq --slurpfile triage "${MAIL_TRIAGE_JSON}" \
    '. + {mail_triage: $triage[0]}' \
    "${BRIEFING_JSON}" > "${BRIEFING_JSON}.tmp" \
    && jq empty "${BRIEFING_JSON}.tmp" \
    && mv "${BRIEFING_JSON}.tmp" "${BRIEFING_JSON}"
fi

publish_dashboard || {
  log "ERROR: dashboard publish failed"
  exit 1
}

exit 0
