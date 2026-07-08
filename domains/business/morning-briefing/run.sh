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
log "STEP 1: Gathering deterministic data locally (no Claude / no MCP)..."
STEP1_START=$(date +%s)

# The 6am HEADLESS run cannot get tool-permission approvals inside Claude
# (~/.claude runs defaultMode=acceptEdits, which does NOT cover Bash or MCP
# calls), so the agent's MCP gather was auto-denied — the CRITICAL "permission
# denied" alerts. Gather everything here in bash instead: full file/CLI access
# as eric, the same pattern Step 2 (notmuch) already uses. Claude is used ONLY
# for the mail-triage reasoning (Step 2), which needs no tools. JobTread
# sections (jobs/leads/tasks/overdue/docs) are placeholders until a local data
# source is wired — see README "JobTread follow-up".

SYSTEMCTL="/run/current-system/sw/bin/systemctl"; [ -x "${SYSTEMCTL}" ] || SYSTEMCTL="systemctl"
KHAL_BIN="/etc/profiles/per-user/eric/bin/khal"

# -- system: service counts + overall state (systemctl is read-only/always-safe) --
SERVICES_ACTIVE=$("${SYSTEMCTL}" list-units --type=service --state=running --no-legend 2>/dev/null | wc -l | tr -d ' ' || echo 0)
SERVICES_FAILED=$("${SYSTEMCTL}" list-units --type=service --state=failed --no-legend 2>/dev/null | wc -l | tr -d ' ' || echo 0)
# NB: `is-system-running` EXITS NON-ZERO when not "running" (e.g. "degraded"),
# so a `|| echo` fallback would fire ON TOP of the real output and concatenate
# ("degraded\nunknown"). Capture the output, swallow the exit with `|| true`,
# then default only if it came back empty.
SYS_STATE=$("${SYSTEMCTL}" is-system-running 2>/dev/null) || true
[ -n "${SYS_STATE}" ] || SYS_STATE="unknown"
[ -n "${SERVICES_ACTIVE}" ] || SERVICES_ACTIVE=0
[ -n "${SERVICES_FAILED}" ] || SERVICES_FAILED=0

# -- storage: df for the key mounts → [{mount, percent}] --
STORAGE_JSON=$(df -h --output=target,pcent / /mnt/hot /mnt/media 2>/dev/null \
  | tail -n +2 \
  | jq -R -s 'split("\n") | map(select(length>0)) | map(
      (split(" ") | map(select(length>0))) as $p
      | { mount: ($p[0] // "?"), percent: (($p[1] // "0%") | rtrimstr("%") | tonumber? // 0) }
    )' 2>/dev/null || echo '[]')
echo "${STORAGE_JSON}" | jq empty 2>/dev/null || STORAGE_JSON='[]'
WORST=$(echo "${STORAGE_JSON}" | jq '[.[].percent] | max // 0' 2>/dev/null || echo 0)

OVERALL="green"
if [ "${SERVICES_FAILED}" -gt 0 ] 2>/dev/null; then OVERALL="red"; fi
if [ "${WORST:-0}" -ge 90 ] 2>/dev/null; then OVERALL="red"; fi

# -- mail health (notmuch counts) --
UNREAD=$(notmuch count tag:unread 2>/dev/null || echo 0)
INBOX_UNREAD=$(notmuch count "tag:inbox and tag:unread" 2>/dev/null || echo 0)
[ -n "${UNREAD}" ] || UNREAD=0
[ -n "${INBOX_UNREAD}" ] || INBOX_UNREAD=0

# -- calendar: today's events via khal, parsed with jq. (NOT python3 — it is not
#    on the unit PATH [bash coreutils jq nodejs notmuch], which is why the old
#    injector silently failed and left the agent's denied calendar in place.) --
CAL_JSON='{"events": []}'
if [ -x "${KHAL_BIN}" ]; then
  CAL_JSON=$("${KHAL_BIN}" list \
    --format='{start-date}T{start-time}|{end-date}T{end-time}|{title}|{location}|{all-day}' \
    today today 2>/dev/null \
    | jq -R -s 'split("\n") | map(select(length>0)) | map(split("|")) | map(select(length>=5)) | map({
        summary: .[2],
        start: .[0],
        end: .[1],
        location: (if .[3] == "" then null else .[3] end),
        allDay: (.[4] | ascii_downcase == "true")
      }) | { events: . }' 2>/dev/null || echo '{"events": []}')
  echo "${CAL_JSON}" | jq empty 2>/dev/null || CAL_JSON='{"events": []}'
fi
EV_COUNT=$(echo "${CAL_JSON}" | jq '.events | length' 2>/dev/null || echo 0)

# -- config drift (2026-07-05 audit, Pattern 6): COMPUTED, not read by eye.
#    Two generation-table misreadings during the audit are why this exists. --
NIXOS_REPO="/home/eric/.nixos"
HEAD_REV=$(git -C "${NIXOS_REPO}" rev-parse HEAD 2>/dev/null || echo "")
# nixos-version reads the rev baked in by flake glue (system.configurationRevision);
# there is no /run/current-system/configuration-revision file on this release.
NIXOS_VERSION_BIN="/run/current-system/sw/bin/nixos-version"; [ -x "${NIXOS_VERSION_BIN}" ] || NIXOS_VERSION_BIN="nixos-version"
DEPLOYED_REV=$("${NIXOS_VERSION_BIN}" --configuration-revision 2>/dev/null | grep -v '^$' || echo "")
[ "${DEPLOYED_REV}" = "null" ] && DEPLOYED_REV=""
UNPUSHED=$(git -C "${NIXOS_REPO}" log --oneline "@{u}.." 2>/dev/null | wc -l | tr -d ' ')
DIRTY=$(git -C "${NIXOS_REPO}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
BOOTED_KERNEL=$(readlink /run/booted-system/kernel 2>/dev/null || echo "?booted")
CURRENT_KERNEL=$(readlink /run/current-system/kernel 2>/dev/null || echo "?current")
if [ "${BOOTED_KERNEL}" = "${CURRENT_KERNEL}" ]; then REBOOT_PENDING=false; else REBOOT_PENDING=true; fi
GEN_COUNT=$(ls -d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l | tr -d ' ')
COREDUMPCTL="/run/current-system/sw/bin/coredumpctl"; [ -x "${COREDUMPCTL}" ] || COREDUMPCTL="coredumpctl"
CORE_24H=$("${COREDUMPCTL}" list --since "-24h" --no-pager -q 2>/dev/null | wc -l | tr -d ' ')
DRIFT_JSON=$(jq -n \
  --arg head "${HEAD_REV}" \
  --arg deployed "${DEPLOYED_REV}" \
  --argjson unpushed "${UNPUSHED:-0}" \
  --argjson dirty "${DIRTY:-0}" \
  --argjson reboot_pending "${REBOOT_PENDING}" \
  --argjson generations "${GEN_COUNT:-0}" \
  --argjson coredumps_24h "${CORE_24H:-0}" '
  { head_rev: (if $head == "" then null else $head end)
  , deployed_rev: (if $deployed == "" then null else $deployed end)
  , deployed_matches_head: (if $head == "" or $deployed == "" then null else ($head == $deployed) end)
  , unpushed_commits: $unpushed
  , dirty_files: $dirty
  , reboot_pending: $reboot_pending
  , generations: $generations
  , coredumps_24h: $coredumps_24h
  }' 2>/dev/null || echo '{}')
echo "${DRIFT_JSON}" | jq empty 2>/dev/null || DRIFT_JSON='{}'

# -- alerts: computed from what we actually gathered (CLAUDE.md rules subset) --
ALERTS_JSON=$(jq -n \
  --argjson failed "${SERVICES_FAILED}" \
  --argjson worst "${WORST:-0}" \
  --argjson drift "${DRIFT_JSON}" '
  [ (if $failed > 0 then {level:"critical", section:"system", message:"\($failed) failed service(s)"} else empty end)
  , (if $worst >= 90 then {level:"critical", section:"system", message:"Storage at \($worst)% on a mount"} else empty end)
  , (if ($drift.reboot_pending // false) then {level:"warning", section:"config_drift", message:"Reboot pending: booted kernel differs from current generation"} else empty end)
  , (if ($drift.unpushed_commits // 0) > 0 then {level:"warning", section:"config_drift", message:"\($drift.unpushed_commits) unpushed commit(s) on ~/.nixos"} else empty end)
  , (if ($drift.deployed_matches_head == false) then {level:"warning", section:"config_drift", message:"Deployed system was not built from current HEAD"} else empty end)
  , (if ($drift.coredumps_24h // 0) >= 50 then {level:"warning", section:"config_drift", message:"\($drift.coredumps_24h) coredumps in 24h — a unit may be crash-looping behind an active status"} else empty end)
  ]' 2>/dev/null || echo '[]')
echo "${ALERTS_JSON}" | jq empty 2>/dev/null || ALERTS_JSON='[]'

# -- website: umami analytics (loopback :3009) + calculator leads (postgres) --
# Best-effort: any failure leaves an empty section, never fails the briefing.
UMAMI_URL="http://127.0.0.1:3009"
UMAMI_WID="02d2b023-55a7-4a24-8064-0d97e4801284"
UMAMI_PW_FILE="/run/agenix/umami-admin-password"
CURL_BIN="$(command -v curl || echo /etc/profiles/per-user/eric/bin/curl)"
PSQL_BIN="/run/current-system/sw/bin/psql"; [ -x "${PSQL_BIN}" ] || PSQL_BIN="psql"
UMAMI_TOKEN=""
if [ -r "${UMAMI_PW_FILE}" ] && [ -x "${CURL_BIN}" ]; then
  UMAMI_LOGIN=$(jq -n --rawfile pw "${UMAMI_PW_FILE}" '{username:"admin",password:($pw|rtrimstr("\n"))}' 2>/dev/null || echo "")
  [ -n "${UMAMI_LOGIN}" ] && UMAMI_TOKEN=$("${CURL_BIN}" -s -m 10 -X POST "${UMAMI_URL}/api/auth/login" \
    -H "content-type: application/json" -d "${UMAMI_LOGIN}" | jq -r '.token // empty' 2>/dev/null || echo "")
fi
STATS_24='{}'; STATS_7D='{}'; TOP_PAGES='[]'
if [ -n "${UMAMI_TOKEN}" ]; then
  NOW_MS=$(( $(date +%s) * 1000 ))
  DAY_MS=$(( NOW_MS - 86400000 ))
  WEEK_MS=$(( NOW_MS - 7 * 86400000 ))
  STATS_24=$("${CURL_BIN}" -s -m 10 -H "Authorization: Bearer ${UMAMI_TOKEN}" \
    "${UMAMI_URL}/api/websites/${UMAMI_WID}/stats?startAt=${DAY_MS}&endAt=${NOW_MS}" 2>/dev/null || echo '{}')
  STATS_7D=$("${CURL_BIN}" -s -m 10 -H "Authorization: Bearer ${UMAMI_TOKEN}" \
    "${UMAMI_URL}/api/websites/${UMAMI_WID}/stats?startAt=${WEEK_MS}&endAt=${NOW_MS}" 2>/dev/null || echo '{}')
  TOP_PAGES=$("${CURL_BIN}" -s -m 10 -H "Authorization: Bearer ${UMAMI_TOKEN}" \
    "${UMAMI_URL}/api/websites/${UMAMI_WID}/metrics?type=path&startAt=${WEEK_MS}&endAt=${NOW_MS}&limit=3" 2>/dev/null || echo '[]')
  echo "${STATS_24}" | jq empty 2>/dev/null || STATS_24='{}'
  echo "${STATS_7D}" | jq empty 2>/dev/null || STATS_7D='{}'
  echo "${TOP_PAGES}" | jq empty 2>/dev/null || TOP_PAGES='[]'
fi
# hwc.leads is the live store hwc-leads writes; hwc.calculator_leads is the
# legacy table only UPDATEd by the appointment workflow.
LEADS_24=$("${PSQL_BIN}" -d hwc -tAc "SELECT count(*) FROM hwc.leads WHERE created_at > now() - interval '1 day'" 2>/dev/null | tr -d ' ')
LEADS_7D=$("${PSQL_BIN}" -d hwc -tAc "SELECT count(*) FROM hwc.leads WHERE created_at > now() - interval '7 days'" 2>/dev/null | tr -d ' ')
[ -n "${LEADS_24}" ] || LEADS_24=0
[ -n "${LEADS_7D}" ] || LEADS_7D=0
WEBSITE_JSON=$(jq -n \
  --argjson s24 "${STATS_24}" \
  --argjson s7 "${STATS_7D}" \
  --argjson pages "${TOP_PAGES}" \
  --argjson leads24 "${LEADS_24}" \
  --argjson leads7 "${LEADS_7D}" \
  --arg ok "$([ -n "${UMAMI_TOKEN}" ] && echo true || echo false)" '
  {
    analytics_ok: ($ok == "true"),
    visitors_24h: ($s24.visitors // 0),
    pageviews_24h: ($s24.pageviews // 0),
    visitors_7d: ($s7.visitors // 0),
    pageviews_7d: ($s7.pageviews // 0),
    visits_7d: ($s7.visits // 0),
    leads_24h: $leads24,
    leads_7d: $leads7,
    top_pages_7d: ([$pages] | flatten | map(select(type=="object")) | map({url: (.x // "?"), views: (.y // 0)})),
    dashboard: "https://stats.iheartwoodcraft.com"
  }' 2>/dev/null || echo '{}')
echo "${WEBSITE_JSON}" | jq empty 2>/dev/null || WEBSITE_JSON='{}'
# Alert if analytics is unreachable (tracking data being lost)
if [ -z "${UMAMI_TOKEN}" ]; then
  ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq '. + [{level:"warning",section:"website",message:"Umami analytics unreachable — visitor tracking data may be lost"}]' 2>/dev/null || echo "${ALERTS_JSON}")
fi

# -- assemble briefing.json atomically: build .tmp, validate, then mv --
if jq -n \
  --arg now "$(date -Iseconds)" \
  --arg overall "${OVERALL}" \
  --arg sys_state "${SYS_STATE}" \
  --argjson cal "${CAL_JSON}" \
  --argjson storage "${STORAGE_JSON}" \
  --argjson services_active "${SERVICES_ACTIVE}" \
  --argjson services_failed "${SERVICES_FAILED}" \
  --argjson unread "${UNREAD}" \
  --argjson inbox_unread "${INBOX_UNREAD}" \
  --argjson alerts "${ALERTS_JSON}" \
  --argjson drift "${DRIFT_JSON}" \
  --argjson website "${WEBSITE_JSON}" '
  {
    generated_at: $now,
    sections: {
      config_drift: $drift,
      calendar: $cal,
      jobs: { active: [] },
      leads: { new_count: 0, items: [] },
      overdue: { count: 0, total_amount: 0, items: [] },
      system: {
        overall: $overall,
        state: $sys_state,
        services_active: $services_active,
        services_failed: $services_failed,
        storage: $storage
      },
      mail: { healthy: true, unread: $unread, inbox_unread: $inbox_unread,
              summary: "\($inbox_unread) inbox unread (\($unread) total)" },
      website: $website,
      weather: { location: "Bozeman, MT", outdoor_work_ok: true, notes: "not gathered" },
      comms: { source: "none", items: [] },
      weekly_snapshot: {},
      backup: {},
      tasks: { due_today: [], due_this_week: [], overdue: [] },
      recent_documents: { items: [] }
    },
    alerts: $alerts,
    notes: "JobTread sections pending a local data source (see README). System/mail/calendar are live."
  }' > "${OUTPUT_DIR}/briefing.json.tmp" 2>>"${LOG_FILE}" \
  && jq empty "${OUTPUT_DIR}/briefing.json.tmp" 2>/dev/null; then
  mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
  log "OK: Local briefing assembled (services: ${SERVICES_ACTIVE} active / ${SERVICES_FAILED} failed · cal: ${EV_COUNT} events · mail: ${INBOX_UNREAD} inbox unread)"
else
  log "ERROR: assembled briefing.json was invalid — keeping previous briefing"
  rm -f "${OUTPUT_DIR}/briefing.json.tmp"
fi

STEP1_END=$(date +%s)
log "STEP 1: completed in $((STEP1_END - STEP1_START))s"

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

# ── Step 2b: Persist triage buckets as notmuch tags ──────────────────────────
# "Move between columns" in the Mail-triage kanban must PERSIST, so the bucket
# is a notmuch tag `triage/<bucket>` (single source of truth: mail.ts
# TRIAGE_BUCKETS). Stamp each classified thread with its bucket tag, removing
# any stale triage/* first, so hwc_mail_triage reflects the daily baseline and
# later workbench moves (hwc_mail set-triage) layer on top. Best-effort: a
# notmuch failure here never fails the briefing.
NOTMUCH_BIN="/etc/profiles/per-user/eric/bin/notmuch"
command -v notmuch >/dev/null 2>&1 && NOTMUCH_BIN="$(command -v notmuch)"
if [ -x "${NOTMUCH_BIN}" ] && [ -f "${MAIL_TRIAGE_JSON}" ]; then
  log "STEP 2b: Persisting triage/<bucket> tags..."
  TAGGED=0
  for bucket in urgent review noise; do
    # All triage tag ops for this bucket: add triage/<bucket>, remove the others.
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
    done < <(jq -r --arg b "${bucket}" '.buckets[$b][]?.thread_id // empty' "${MAIL_TRIAGE_JSON}" 2>/dev/null)
  done
  log "STEP 2b: tagged ${TAGGED} threads with triage/<bucket>"
else
  log "STEP 2b: SKIP (notmuch missing or no triage JSON)"
fi

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

# ── Step 5: Email delivery (2026-07-06, audit 2.1: Eric wants email + workbench)
# Renders briefing.json to a plain-text email and sends via msmtp's default
# account (proton-hwc → eric@iheartwoodcraft.com). Best-effort: a send failure
# logs a WARN but never fails the briefing run.
MSMTP_BIN="$(command -v msmtp || echo /etc/profiles/per-user/eric/bin/msmtp)"
if [ -f "${OUTPUT_DIR}/briefing.json" ] && [ -x "${MSMTP_BIN}" ]; then
  log "STEP 5: Emailing briefing..."
  EMAIL_BODY=$(jq -r '
    def sec(x): "\n== " + x + " ==\n";
    "Morning Briefing — " + (.generated_at // "unknown")
    + (if (.alerts // []) | length > 0 then
        sec("ALERTS (" + ((.alerts | length) | tostring) + ")")
        + ([.alerts[] | "[" + .level + "] " + .section + ": " + .message] | join("\n"))
      else "\n\nNo alerts. All green." end)
    + (if .sections.config_drift then
        sec("CONFIG DRIFT")
        + "reboot pending: " + ((.sections.config_drift.reboot_pending // false) | tostring)
        + " · unpushed: " + ((.sections.config_drift.unpushed_commits // 0) | tostring)
        + " · dirty: " + ((.sections.config_drift.dirty_files // 0) | tostring)
        + " · generations: " + ((.sections.config_drift.generation_count // 0) | tostring)
        + " · coredumps 24h: " + ((.sections.config_drift.coredumps_24h // 0) | tostring)
      else "" end)
    + (if .sections.system then
        sec("SYSTEM")
        + "services: " + ((.sections.system.services_active // 0) | tostring) + " active / "
        + ((.sections.system.services_failed // 0) | tostring) + " failed · containers: "
        + ((.sections.system.containers_running // 0) | tostring) + " running"
        + ((.sections.system.storage // []) | map("\n  " + .mount + ": " + ((.percent // 0) | tostring) + "% used, " + (.available // "?") + " free") | join(""))
      else "" end)
    + (if (.sections.calendar.events // []) | length > 0 then
        sec("TODAY / THIS WEEK")
        + ([.sections.calendar.events[] | "  " + (.date // "") + " " + (.startTime // "") + " " + (.summary // "")] | join("\n"))
      else "" end)
    + (if .mail_triage then
        sec("MAIL")
        + "urgent: " + ((.mail_triage.urgent // []) | length | tostring)
        + " · review: " + ((.mail_triage.review // []) | length | tostring)
        + " · noise: " + ((.mail_triage.noise // []) | length | tostring)
        + (((.mail_triage.urgent // [])[:5]) | map("\n  ! " + (.subject // .from // "?")) | join(""))
      else "" end)
    + (if .sections.website and (.sections.website | length > 0) then
        sec("WEBSITE")
        + "visitors 24h: " + ((.sections.website.visitors_24h // 0) | tostring)
        + " · pageviews 24h: " + ((.sections.website.pageviews_24h // 0) | tostring)
        + " · 7d: " + ((.sections.website.visitors_7d // 0) | tostring) + " visitors / "
        + ((.sections.website.pageviews_7d // 0) | tostring) + " views"
        + "\ncalculator leads: " + ((.sections.website.leads_24h // 0) | tostring) + " today · "
        + ((.sections.website.leads_7d // 0) | tostring) + " this week"
        + ((.sections.website.top_pages_7d // [])[:3] | map("\n  " + .url + " (" + (.views | tostring) + ")") | join(""))
        + "\nfull analytics: https://stats.iheartwoodcraft.com"
      else "" end)
    + "\n\nDashboard: https://briefing.hwc.iheartwoodcraft.com\n"
  ' "${OUTPUT_DIR}/briefing.json" 2>/dev/null) || EMAIL_BODY=""
  if [ -n "${EMAIL_BODY}" ]; then
    ALERT_COUNT=$(jq -r '(.alerts // []) | length' "${OUTPUT_DIR}/briefing.json" 2>/dev/null || echo "?")
    SUBJECT="Morning Briefing $(date +%Y-%m-%d)"
    [ "${ALERT_COUNT}" != "0" ] && SUBJECT="${SUBJECT} — ${ALERT_COUNT} alert(s)"
    # From office@, NOT eric@: self-sent mail (eric→eric) gets Proton's
    # sent+auto-archive treatment and never shows in the Inbox (found 2026-07-06,
    # first live run). office@ is an alias on the same bridge; lands in Inbox.
    if printf 'Subject: %s\nFrom: office@iheartwoodcraft.com\nTo: eric@iheartwoodcraft.com\n\n%s\n' \
        "${SUBJECT}" "${EMAIL_BODY}" | "${MSMTP_BIN}" -a proton-office eric@iheartwoodcraft.com 2>>"${LOG_FILE}"; then
      log "OK: Briefing emailed"
    else
      log "WARN: msmtp send failed (briefing still on dashboard/workbench)"
    fi
  else
    log "WARN: email render produced empty body — skipped send"
  fi
else
  log "STEP 5: SKIP (no briefing.json or msmtp missing)"
fi

tail -100 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"
log "DONE"
