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
# Failed unit NAMES, not just a count — "1 failed service(s)" with no name is
# an alert you can't act on (2026-07-08 usability pass).
FAILED_UNITS_JSON=$("${SYSTEMCTL}" list-units --type=service --state=failed --no-legend --plain 2>/dev/null \
  | awk '{print $1}' | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null || echo '[]')
echo "${FAILED_UNITS_JSON}" | jq empty 2>/dev/null || FAILED_UNITS_JSON='[]'
# Containers = running podman-*.service units (works as eric; podman ps would
# need the root socket). The dashboard used to render literal "undefined" here.
CONTAINERS_RUNNING=$("${SYSTEMCTL}" list-units --type=service --state=running --no-legend --plain 'podman-*' 2>/dev/null | wc -l | tr -d ' ' || echo 0)
[ -n "${CONTAINERS_RUNNING}" ] || CONTAINERS_RUNNING=0
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
# Delta vs the previous run — an absolute "1374 unread" is a number Eric has
# stopped seeing; the day-over-day movement is the readable signal.
STATE_FILE="${OUTPUT_DIR}/.state.json"
PREV_INBOX_UNREAD=$(jq -r '.inbox_unread // empty' "${STATE_FILE}" 2>/dev/null || echo "")
MAIL_DELTA=null
[ -n "${PREV_INBOX_UNREAD}" ] && MAIL_DELTA=$(( INBOX_UNREAD - PREV_INBOX_UNREAD ))
jq -n --argjson u "${INBOX_UNREAD}" '{inbox_unread: $u}' > "${STATE_FILE}" 2>/dev/null || true

# -- calendar: THIS WEEK's events via khal, parsed with jq. (NOT python3 — it is
#    not on the unit PATH [bash coreutils jq nodejs notmuch], which is why the
#    old injector silently failed.) A today-only window hid the whole week
#    behind "No events today" (2026-07-08 usability pass) — gather 7 days and
#    let the dashboard group by day. khal repeats day-header lines in list
#    output; the length>=5 filter drops them. --
CAL_JSON='{"events": []}'
if [ -x "${KHAL_BIN}" ]; then
  CAL_JSON=$("${KHAL_BIN}" list \
    --format='{start-date}T{start-time}|{end-date}T{end-time}|{title}|{location}|{all-day}' \
    today 7d 2>/dev/null \
    | jq -R -s 'split("\n") | map(select(length>0)) | map(split("|")) | map(select(length>=5)) | map({
        summary: .[2],
        start: .[0],
        end: .[1],
        date: (.[0] | split("T")[0]),
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
# Age of HEAD: the drift alert only fires once the divergence has persisted
# 12h — otherwise every script-only/HM-only commit cries wolf until the next
# routine rebuild.
HEAD_TS=$(git -C "${NIXOS_REPO}" log -1 --format=%ct 2>/dev/null || echo "")
HEAD_AGE_H=0
[ -n "${HEAD_TS}" ] && HEAD_AGE_H=$(( ( $(date +%s) - HEAD_TS ) / 3600 ))
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
# coredumpctl exits 1 when there are NO coredumps — don't let pipefail kill us.
CORE_24H=$({ "${COREDUMPCTL}" list --since "-24h" --no-pager -q 2>/dev/null || true; } | wc -l | tr -d ' ')
DRIFT_JSON=$(jq -n \
  --arg head "${HEAD_REV}" \
  --arg deployed "${DEPLOYED_REV}" \
  --argjson unpushed "${UNPUSHED:-0}" \
  --argjson dirty "${DIRTY:-0}" \
  --argjson reboot_pending "${REBOOT_PENDING}" \
  --argjson generations "${GEN_COUNT:-0}" \
  --argjson coredumps_24h "${CORE_24H:-0}" \
  --argjson head_age_hours "${HEAD_AGE_H:-0}" '
  { head_rev: (if $head == "" then null else $head end)
  , deployed_rev: (if $deployed == "" then null else $deployed end)
  , deployed_matches_head: (if $head == "" or $deployed == "" then null else ($head == $deployed) end)
  , unpushed_commits: $unpushed
  , dirty_files: $dirty
  , reboot_pending: $reboot_pending
  , generations: $generations
  , coredumps_24h: $coredumps_24h
  , head_age_hours: $head_age_hours
  }' 2>/dev/null || echo '{}')
echo "${DRIFT_JSON}" | jq empty 2>/dev/null || DRIFT_JSON='{}'

# -- alerts: computed from what we actually gathered (CLAUDE.md rules subset) --
ALERTS_JSON=$(jq -n \
  --argjson failed "${SERVICES_FAILED}" \
  --argjson failed_units "${FAILED_UNITS_JSON}" \
  --argjson worst "${WORST:-0}" \
  --argjson drift "${DRIFT_JSON}" '
  [ (if $failed > 0 then {level:"critical", section:"system", message:"\($failed) failed service(s): \($failed_units | join(", "))"} else empty end)
  , (if $worst >= 90 then {level:"critical", section:"system", message:"Storage at \($worst)% on a mount"} else empty end)
  , (if ($drift.reboot_pending // false) then {level:"warning", section:"config_drift", message:"Reboot pending: booted kernel differs from current generation"} else empty end)
  , (if ($drift.unpushed_commits // 0) > 0 then {level:"warning", section:"config_drift", message:"\($drift.unpushed_commits) unpushed commit(s) on ~/.nixos"} else empty end)
  , (if ($drift.deployed_matches_head == false and ($drift.head_age_hours // 0) >= 12) then {level:"warning", section:"config_drift", message:"Deployed system was not built from current HEAD (drift has persisted \($drift.head_age_hours)h)"} else empty end)
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

# -- weather: open-meteo (keyless, HTTPS) → Bozeman forecast. Best-effort: any
#    failure keeps the explicit "not gathered" placeholder instead of zeros. --
WX_JSON='{"location":"Bozeman, MT","current_temp_f":null,"high_f":null,"low_f":null,"conditions":"","precipitation_chance":null,"wind_mph":null,"outdoor_work_ok":true,"notes":"weather fetch failed"}'
WX_RAW=$("${CURL_BIN}" -s -m 15 "https://api.open-meteo.com/v1/forecast?latitude=45.6793&longitude=-111.0373&current=temperature_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America%2FDenver&forecast_days=1" 2>/dev/null || echo "")
if [ -n "${WX_RAW}" ] && echo "${WX_RAW}" | jq -e '.current.temperature_2m' >/dev/null 2>&1; then
  WX_JSON=$(echo "${WX_RAW}" | jq '
    def cond(c): if c == null then "Unknown"
      elif c == 0 then "Clear" elif c <= 2 then "Partly cloudy" elif c == 3 then "Overcast"
      elif c <= 48 then "Fog" elif c <= 57 then "Drizzle" elif c <= 67 then "Rain"
      elif c <= 77 then "Snow" elif c <= 82 then "Rain showers" elif c <= 86 then "Snow showers"
      else "Thunderstorm" end;
    {
      location: "Bozeman, MT",
      current_temp_f: .current.temperature_2m,
      high_f: .daily.temperature_2m_max[0],
      low_f: .daily.temperature_2m_min[0],
      conditions: cond(.daily.weather_code[0] // .current.weather_code),
      precipitation_chance: (.daily.precipitation_probability_max[0] // 0),
      wind_mph: ((.current.wind_speed_10m // 0) | round),
      outdoor_work_ok: (((.daily.temperature_2m_max[0] // 50) >= 20)
        and ((.current.wind_speed_10m // 0) <= 30)
        and ((.daily.precipitation_probability_max[0] // 0) < 60)),
      notes: ""
    }' 2>/dev/null || echo "${WX_JSON}")
  echo "${WX_JSON}" | jq empty 2>/dev/null || WX_JSON='{"location":"Bozeman, MT","outdoor_work_ok":true,"notes":"weather fetch failed"}'
fi

# -- backup: borg unit status via systemctl show (same unit hwc_storage_status
#    reads). archive_count/total_size need repo access — left null here. --
BACKUP_JSON='{}'
BK_UNIT="borgbackup-job-hwc-backup"
BK_RESULT=$("${SYSTEMCTL}" show "${BK_UNIT}.service" -p Result --value 2>/dev/null || echo "")
BK_EXITCODE=$("${SYSTEMCTL}" show "${BK_UNIT}.service" -p ExecMainStatus --value 2>/dev/null || echo "")
BK_LAST_RAW=$("${SYSTEMCTL}" show "${BK_UNIT}.service" -p ExecMainExitTimestamp --value 2>/dev/null || echo "")
BK_NEXT_RAW=$("${SYSTEMCTL}" show "${BK_UNIT}.timer" -p NextElapseUSecRealtime --value 2>/dev/null || echo "")
BK_LAST=""; [ -n "${BK_LAST_RAW}" ] && BK_LAST=$(date -Iseconds -d "${BK_LAST_RAW}" 2>/dev/null || echo "")
BK_NEXT=""; [ -n "${BK_NEXT_RAW}" ] && BK_NEXT=$(date -Iseconds -d "${BK_NEXT_RAW}" 2>/dev/null || echo "")
if [ -n "${BK_RESULT}" ]; then
  BK_STATUS="error"
  if [ "${BK_RESULT}" = "success" ] && [ "${BK_EXITCODE:-1}" = "0" ]; then BK_STATUS="success"; fi
  BACKUP_JSON=$(jq -n \
    --arg status "${BK_STATUS}" --arg unit "${BK_UNIT}" \
    --arg last "${BK_LAST}" --arg next "${BK_NEXT}" --arg result "${BK_RESULT}" '
    { exit_status: $status, unit: $unit, service_result: $result
    , last_run: (if $last == "" then null else $last end)
    , next_scheduled: (if $next == "" then null else $next end)
    , archive_count: null, total_size: null }' 2>/dev/null || echo '{}')
  echo "${BACKUP_JSON}" | jq empty 2>/dev/null || BACKUP_JSON='{}'
  if [ "${BK_STATUS}" = "error" ]; then
    ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq --arg r "${BK_RESULT}" '. + [{level:"critical",section:"backup",message:("Borg backup unit result: " + $r)}]' 2>/dev/null || echo "${ALERTS_JSON}")
  elif [ -n "${BK_LAST}" ]; then
    BK_AGE_H=$(( ( $(date +%s) - $(date -d "${BK_LAST}" +%s 2>/dev/null || date +%s) ) / 3600 ))
    if [ "${BK_AGE_H}" -gt 26 ] 2>/dev/null; then
      ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq --argjson h "${BK_AGE_H}" '. + [{level:"warning",section:"backup",message:"Last backup ran \($h)h ago (>26h)"}]' 2>/dev/null || echo "${ALERTS_JSON}")
    fi
  fi
fi

# -- backup: postgres dump unit, same pattern as borg (02:35 nightly) --
PG_UNIT="postgresql-db-backup"
PG_RESULT=$("${SYSTEMCTL}" show "${PG_UNIT}.service" -p Result --value 2>/dev/null || echo "")
PG_EXITCODE=$("${SYSTEMCTL}" show "${PG_UNIT}.service" -p ExecMainStatus --value 2>/dev/null || echo "")
PG_LAST_RAW=$("${SYSTEMCTL}" show "${PG_UNIT}.service" -p ExecMainExitTimestamp --value 2>/dev/null || echo "")
PG_LAST=""; [ -n "${PG_LAST_RAW}" ] && PG_LAST=$(date -Iseconds -d "${PG_LAST_RAW}" 2>/dev/null || echo "")
if [ -n "${PG_RESULT}" ]; then
  PG_STATUS="error"
  if [ "${PG_RESULT}" = "success" ] && [ "${PG_EXITCODE:-1}" = "0" ]; then PG_STATUS="success"; fi
  BACKUP_JSON=$(echo "${BACKUP_JSON}" | jq \
    --arg status "${PG_STATUS}" --arg unit "${PG_UNIT}" --arg last "${PG_LAST}" --arg result "${PG_RESULT}" '
    . + { postgres: { exit_status: $status, unit: $unit, service_result: $result
        , last_run: (if $last == "" then null else $last end) } }' 2>/dev/null || echo "${BACKUP_JSON}")
  echo "${BACKUP_JSON}" | jq empty 2>/dev/null || BACKUP_JSON='{}'
  if [ "${PG_STATUS}" = "error" ]; then
    ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq --arg r "${PG_RESULT}" '. + [{level:"critical",section:"backup",message:("Postgres backup unit result: " + $r)}]' 2>/dev/null || echo "${ALERTS_JSON}")
  fi
fi

# -- ops digest: what happened SINCE THE PREVIOUS EVENING, from data already on
#    the box. The live systemctl snapshot above can't see a service that
#    crashed at 2am and auto-restarted; these sources can. Every pipeline head
#    is ||-true-guarded — pipefail + "no data" must never kill the briefing. --
JOURNALCTL="/run/current-system/sw/bin/journalctl"; [ -x "${JOURNALCTL}" ] || JOURNALCTL="journalctl"
OPS_SINCE=$(date -d 'yesterday 17:00' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d 00:00:00')

# Service-failure EVENTS from the notify wrapper's log (crash→restart visible).
# Log lines look like: [2026-07-07 21:12:41] Service failure: postgresql
SVC_FAIL_JSON=$({ grep -h '^\[20' /var/log/hwc/notifications/service-failures.log 2>/dev/null || true; } \
  | awk -v since="${OPS_SINCE}" -F'[][]' '$2 >= since && index($0, "Service failure: ") { split($0, a, "Service failure: "); print $2 "|" a[2] }' \
  | jq -R -s 'split("\n") | map(select(length>0)) | map(split("|") | {time: .[0], service: .[1]})' 2>/dev/null || echo '[]')
echo "${SVC_FAIL_JSON}" | jq empty 2>/dev/null || SVC_FAIL_JSON='[]'

# Uptime Kuma probe failures, deduped per monitor:
#   ... [MONITOR] WARN: Monitor #46 'Ollama': Failing: connect ECONNREFUSED ...
KUMA_FAIL_JSON=$({ "${JOURNALCTL}" SYSLOG_IDENTIFIER=uptime-kuma --since "${OPS_SINCE}" --no-pager -q 2>/dev/null || true; } \
  | { grep -F '[MONITOR] WARN' || true; } \
  | awk -F"'" 'NF >= 3 { print $2 }' \
  | sort | uniq -c \
  | awk '{ n=$1; $1=""; sub(/^ /, ""); print n "|" $0 }' \
  | jq -R -s 'split("\n") | map(select(length>0)) | map(split("|") | {monitor: .[1], failed_probes: (.[0]|tonumber)}) | sort_by(-.failed_probes)' 2>/dev/null || echo '[]')
echo "${KUMA_FAIL_JSON}" | jq empty 2>/dev/null || KUMA_FAIL_JSON='[]'

# Top journal error sources — catches silent crash-loops (the vdirsyncer
# every-15-min failure ran for hours with nothing surfacing it). podman-*
# units are EXCLUDED: containers write INFO logs to stderr, which the journal
# stamps priority=err — authentik alone "errors" 2400×/day that way, drowning
# real signal. Container breakage surfaces via Kuma + service_failures instead.
# OPS_ERR_FLOOR: drop units with a trivial one-off count (single activation
# blips like init.scope ×3, run-*.scope ×4) — a crash-loop clears this easily.
OPS_ERR_FLOOR=5
ERR_TOP_JSON=$({ "${JOURNALCTL}" -p err --since "${OPS_SINCE}" --no-pager -q -o json 2>/dev/null || true; } \
  | jq -s --argjson floor "${OPS_ERR_FLOOR}" 'map(._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER // "kernel") | map(select(startswith("podman-") | not)) | group_by(.) | map({unit: .[0], errors: length}) | map(select(.errors >= $floor)) | sort_by(-.errors) | .[:5]' 2>/dev/null || echo '[]')
echo "${ERR_TOP_JSON}" | jq empty 2>/dev/null || ERR_TOP_JSON='[]'

# Prometheus: scrape targets down + disk days-to-full forecast (predictive
# beats the static df percent). Both best-effort against loopback :9090.
PROM_URL="http://127.0.0.1:9090"
PROM_DOWN_JSON=$("${CURL_BIN}" -sG -m 10 "${PROM_URL}/api/v1/query" --data-urlencode 'query=up == 0' 2>/dev/null \
  | jq '[.data.result[]? | {job: (.metric.job // "?"), instance: (.metric.instance // "?")}]' 2>/dev/null || echo '[]')
echo "${PROM_DOWN_JSON}" | jq empty 2>/dev/null || PROM_DOWN_JSON='[]'
DISK_FORECAST_JSON=$("${CURL_BIN}" -sG -m 10 "${PROM_URL}/api/v1/query" \
  --data-urlencode 'query=node_filesystem_avail_bytes{mountpoint=~"/|/mnt/hot|/mnt/media"} / - deriv(node_filesystem_avail_bytes{mountpoint=~"/|/mnt/hot|/mnt/media"}[24h]) / 86400' 2>/dev/null \
  | jq '[.data.result[]? | {mount: (.metric.mountpoint // "?"), days_to_full: (.value[1] | tonumber? // null)}
        | select(.days_to_full != null and .days_to_full > 0 and .days_to_full < 365)
        | .days_to_full |= round] | sort_by(.days_to_full)' 2>/dev/null || echo '[]')
echo "${DISK_FORECAST_JSON}" | jq empty 2>/dev/null || DISK_FORECAST_JSON='[]'

# Nightly-builds gauntlet: cards that landed in _finished/ since yesterday
# evening (the 01:30 run completes hours before the 6am briefing).
NB_DIR="/home/eric/900_vaults/brain/_inbox/nightly_builds/_finished"
NB_JSON=$({ find "${NB_DIR}" -mindepth 1 -maxdepth 1 -newermt "${OPS_SINCE}" -printf '%f\n' 2>/dev/null || true; } \
  | jq -R -s 'split("\n") | map(select(length>0)) | sort' 2>/dev/null || echo '[]')
echo "${NB_JSON}" | jq empty 2>/dev/null || NB_JSON='[]'

OPS_JSON=$(jq -n \
  --arg since "${OPS_SINCE}" \
  --argjson svc "${SVC_FAIL_JSON}" \
  --argjson kuma "${KUMA_FAIL_JSON}" \
  --argjson errs "${ERR_TOP_JSON}" \
  --argjson down "${PROM_DOWN_JSON}" \
  --argjson disk "${DISK_FORECAST_JSON}" \
  --argjson nb "${NB_JSON}" '
  { since: $since
  , service_failures: $svc
  , kuma_failing: $kuma
  , journal_errors_top: $errs
  , prometheus_targets_down: $down
  , disk_forecast: $disk
  , nightly_builds_finished: $nb
  }' 2>/dev/null || echo '{}')
echo "${OPS_JSON}" | jq empty 2>/dev/null || OPS_JSON='{}'

# Ops alerts (append, same pattern as website/backup)
ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq \
  --argjson svc "${SVC_FAIL_JSON}" \
  --argjson kuma "${KUMA_FAIL_JSON}" \
  --argjson down "${PROM_DOWN_JSON}" \
  --argjson disk "${DISK_FORECAST_JSON}" '
  . + (if ($svc | length) > 0 then [{level:"warning", section:"ops",
        message:"\($svc | length) service failure event(s) since yesterday evening: \($svc | map(.service) | unique | join(", "))"}] else [] end)
    + (if ($kuma | length) > 0 then [{level:"warning", section:"ops",
        message:"Uptime Kuma: \($kuma | length) monitor(s) failing probes: \($kuma | map(.monitor) | join(", "))"}] else [] end)
    + (if ($down | length) > 0 then [{level:"warning", section:"ops",
        message:"\($down | length) Prometheus target(s) down: \($down | map(.job) | unique | join(", "))"}] else [] end)
    + (if ($disk | map(select(.days_to_full <= 14)) | length) > 0 then [{level:"critical", section:"ops",
        message:"Disk filling fast: \($disk | map(select(.days_to_full <= 14)) | map("\(.mount) full in ~\(.days_to_full)d") | join(", "))"}] else [] end)
  ' 2>/dev/null || echo "${ALERTS_JSON}")
echo "${ALERTS_JSON}" | jq empty 2>/dev/null || ALERTS_JSON='[]'

# -- assemble briefing.json atomically: build .tmp, validate, then mv --
if jq -n \
  --arg now "$(date -Iseconds)" \
  --arg overall "${OVERALL}" \
  --arg sys_state "${SYS_STATE}" \
  --argjson cal "${CAL_JSON}" \
  --argjson storage "${STORAGE_JSON}" \
  --argjson services_active "${SERVICES_ACTIVE}" \
  --argjson services_failed "${SERVICES_FAILED}" \
  --argjson failed_units "${FAILED_UNITS_JSON}" \
  --argjson containers "${CONTAINERS_RUNNING}" \
  --argjson unread "${UNREAD}" \
  --argjson inbox_unread "${INBOX_UNREAD}" \
  --argjson mail_delta "${MAIL_DELTA}" \
  --argjson ops "${OPS_JSON}" \
  --argjson alerts "${ALERTS_JSON}" \
  --argjson drift "${DRIFT_JSON}" \
  --argjson website "${WEBSITE_JSON}" \
  --argjson weather "${WX_JSON}" \
  --argjson backup "${BACKUP_JSON}" '
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
        failed_units: $failed_units,
        containers_running: $containers,
        storage: $storage
      },
      mail: { healthy: true, unread: $unread, inbox_unread: $inbox_unread,
              unread_delta: $mail_delta,
              summary: ("\($inbox_unread) inbox unread"
                + (if $mail_delta != null then " (\(if $mail_delta >= 0 then "+" else "" end)\($mail_delta) since last run)" else "" end)) },
      ops: $ops,
      website: $website,
      weather: $weather,
      comms: { source: "none", items: [] },
      weekly_snapshot: {},
      backup: $backup,
      tasks: { due_today: [], due_this_week: [], overdue: [] },
      recent_documents: { items: [] }
    },
    alerts: $alerts,
    notes: "System/mail/calendar/weather/backup gathered locally; jobs/leads/overdue/tasks via gateway (Step 1b)."
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

# ── Step 1b: Live business data via the local MCP gateway ────────────────────
# JobTread jobs/leads/overdue + CalDAV tasks, fetched by gather-live.mjs over
# loopback JSON-RPC (:6200/mcp) — no Claude, no permission prompts. Best-effort:
# gather errors surface as dashboard alerts; sections it couldn't fetch keep
# the Step-1 placeholders.
log "STEP 1b: Live gather via gateway..."
LIVE_JSON=$(timeout 120 node "${AGENT_DIR}/gather-live.mjs" 2>>"${LOG_FILE}" || echo "")
if [ -n "${LIVE_JSON}" ] && echo "${LIVE_JSON}" | jq empty 2>/dev/null && [ -f "${OUTPUT_DIR}/briefing.json" ]; then
  if jq --argjson live "${LIVE_JSON}" '
      .sections = (.sections * ($live.sections // {}))
      | .alerts += ($live.alerts // [])
      | .alerts += [($live.errors // [])[] | {level:"warning", section:"gather", message:("live gather failed: " + .section + " — " + .message)}]
    ' "${OUTPUT_DIR}/briefing.json" > "${OUTPUT_DIR}/briefing.json.tmp" 2>>"${LOG_FILE}" \
    && jq empty "${OUTPUT_DIR}/briefing.json.tmp" 2>/dev/null; then
    mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
    LIVE_SUMMARY=$(echo "${LIVE_JSON}" | jq -r '"jobs: \(.sections.jobs.active // [] | length) · leads: \(.sections.leads.new_count // "?") · overdue: \(.sections.overdue.count // "?") · task buckets: \((.sections.tasks.overdue // [] | length) + (.sections.tasks.due_today // [] | length) + (.sections.tasks.due_this_week // [] | length)) · errors: \(.errors | length)"' 2>/dev/null || echo "?")
    log "STEP 1b: OK (${LIVE_SUMMARY})"
  else
    log "STEP 1b: ERROR merging live data — keeping Step 1 briefing"
    rm -f "${OUTPUT_DIR}/briefing.json.tmp"
  fi
else
  log "STEP 1b: WARN gather-live.mjs produced no valid JSON — placeholders kept"
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
      # Extract the JSON object with node (on the unit PATH), not a sed line
      # range: the old '/^{/,/^}$/' range broke on single-line JSON, fenced
      # output, and postamble — the recurring "invalid JSON from claude"
      # (2026-07-08). Try, in order: whole output · fenced block · first "{"
      # to last "}".
      TRIAGE_CLEAN=$(echo "${TRIAGE_RAW}" | node -e '
        const s = require("fs").readFileSync(0, "utf8");
        const tryParse = (t) => { try { return JSON.stringify(JSON.parse(t)); } catch { return null; } };
        let r = tryParse(s);
        if (!r) { const m = s.match(/```(?:json)?\s*([\s\S]*?)```/); if (m) r = tryParse(m[1]); }
        if (!r) { const a = s.indexOf("{"), b = s.lastIndexOf("}"); if (a >= 0 && b > a) r = tryParse(s.slice(a, b + 1)); }
        if (r) process.stdout.write(r); else process.exit(1);
      ' 2>/dev/null) || TRIAGE_CLEAN=""
      if [ -n "${TRIAGE_CLEAN}" ] && echo "${TRIAGE_CLEAN}" | jq empty 2>/dev/null; then
        echo "${TRIAGE_CLEAN}" > "${MAIL_TRIAGE_JSON}"
        U=$(echo "${TRIAGE_CLEAN}" | jq '.stats.urgent_count' 2>/dev/null || echo "?")
        R=$(echo "${TRIAGE_CLEAN}" | jq '.stats.review_count' 2>/dev/null || echo "?")
        N=$(echo "${TRIAGE_CLEAN}" | jq '.stats.noise_count'  2>/dev/null || echo "?")
        log "mail-triage: OK (${U} urgent, ${R} review, ${N} noise)"
      else
        # Keep the FULL raw output for diagnosis — 200 chars was never enough
        # to see why parsing failed.
        echo "${TRIAGE_RAW}" > "${AGENT_DIR}/logs/mail-triage-raw.log"
        log "WARN: Mail triage returned invalid JSON — full raw saved to logs/mail-triage-raw.log; first 200 chars:"
        log "$(echo "${TRIAGE_RAW}" | head -c 200)"
        write_empty_triage "invalid JSON from claude (raw saved to logs/mail-triage-raw.log)"
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
# Only the MORNING run emails (timer may also fire midday/evening to refresh
# the dashboard — those must not re-send). FORCE_EMAIL=1 overrides for testing.
MSMTP_BIN="$(command -v msmtp || echo /etc/profiles/per-user/eric/bin/msmtp)"
HOUR_NOW=$(date +%H)
if [ "${FORCE_EMAIL:-0}" != "1" ] && [ "${HOUR_NOW#0}" -ge 9 ] 2>/dev/null; then
  log "STEP 5: SKIP (refresh run at ${HOUR_NOW}:xx — email only sent on the pre-9am run)"
elif [ -f "${OUTPUT_DIR}/briefing.json" ] && [ -x "${MSMTP_BIN}" ]; then
  log "STEP 5: Emailing briefing..."
  # Slot-stamped: normally only the pre-9am run emails, but a FORCE_EMAIL
  # midday/evening send should not masquerade as the morning one.
  SLOT="Morning"
  if [ "${HOUR_NOW#0}" -ge 15 ] 2>/dev/null; then SLOT="Evening"
  elif [ "${HOUR_NOW#0}" -ge 11 ] 2>/dev/null; then SLOT="Midday"; fi
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
        + " · generations: " + ((.sections.config_drift.generations // 0) | tostring)
        + " · coredumps 24h: " + ((.sections.config_drift.coredumps_24h // 0) | tostring)
      else "" end)
    + (if .sections.system then
        sec("SYSTEM")
        + "services: " + ((.sections.system.services_active // 0) | tostring) + " active / "
        + ((.sections.system.services_failed // 0) | tostring) + " failed · containers: "
        + ((.sections.system.containers_running // 0) | tostring) + " running"
        + ((.sections.system.storage // []) | map("\n  " + .mount + ": " + ((.percent // 0) | tostring) + "% used, " + (.available // "?") + " free") | join(""))
        + (if .sections.backup.exit_status then
            "\n  backup: borg " + .sections.backup.exit_status
            + (if .sections.backup.postgres then " · postgres " + .sections.backup.postgres.exit_status else "" end)
          else "" end)
      else "" end)
    + (if .sections.ops then
        (.sections.ops as $o |
        (if (($o.service_failures // []) | length) > 0
          or (($o.kuma_failing // []) | length) > 0
          or (($o.prometheus_targets_down // []) | length) > 0
          or (($o.journal_errors_top // []) | length) > 0
          or (($o.disk_forecast // []) | length) > 0 then
          sec("OVERNIGHT OPS (since " + ($o.since // "?") + ")")
          + (($o.service_failures // []) | map("\n  ! service failed: " + .service + " @ " + .time) | join(""))
          + (($o.kuma_failing // []) | map("\n  ~ kuma: " + .monitor + " (" + (.failed_probes | tostring) + " failed probes)") | join(""))
          + (($o.prometheus_targets_down // []) | map("\n  ~ target down: " + .job + " @ " + .instance) | join(""))
          + (($o.journal_errors_top // []) | map("\n  · journal errors: " + .unit + " ×" + (.errors | tostring)) | join(""))
          + (($o.disk_forecast // [])[:3] | map("\n  · " + .mount + " full in ~" + (.days_to_full | tostring) + "d at current growth") | join(""))
        else "" end)
        + (if (($o.nightly_builds_finished // []) | length) > 0 then
            sec("BUILT OVERNIGHT")
            + (($o.nightly_builds_finished // []) | map("  · " + .) | join("\n"))
          else "" end))
      else "" end)
    + (if (.sections.calendar.events // []) | length > 0 then
        sec("THIS WEEK")
        + ([.sections.calendar.events[] | "  " + (.date // ((.start // "") | split("T")[0]) // "")
            + " " + (if .allDay then "all-day" else ((.start // "") | split("T")[1] // "") end)
            + "  " + (.summary // "")
            + (if .location then " — " + .location else "" end)] | join("\n"))
      else "" end)
    + (if (.sections.tasks // {}) | ((.overdue // []) + (.due_today // []) + (.due_this_week // [])) | length > 0 then
        sec("TASKS")
        + ((((.sections.tasks.overdue // []) | map("  ! OVERDUE " + (.due_date // "") + "  " + .name))
          + ((.sections.tasks.due_today // []) | map("  · today  " + .name))
          + ((.sections.tasks.due_this_week // []) | map("  · " + (.due_date // "") + "  " + .name))) | join("\n"))
      else "" end)
    + (if (.sections.leads.items // []) | length > 0 then
        sec("LEADS (" + ((.sections.leads.items | length) | tostring) + ")")
        + ([.sections.leads.items[] | "  " + .name
            + (if (.job_type // "") != "" then " — " + .job_type else "" end)
            + " (" + (.days_old | tostring) + "d old)"] | join("\n"))
      else "" end)
    + (if (.sections.overdue.count // 0) > 0 then
        sec("OVERDUE INVOICES — $" + ((.sections.overdue.total_amount // 0) | round | tostring))
        + ([.sections.overdue.items[] | "  $" + ((.amount // 0) | round | tostring) + "  " + (.job_name // .name)
            + (if .days_past_due then " (" + (.days_past_due | tostring) + "d past due)" else "" end)] | join("\n"))
      else "" end)
    + (if (.sections.jobs.active // []) | length > 0 then
        sec("ACTIVE JOBS (" + ((.sections.jobs.active | length) | tostring) + ")")
        + ([.sections.jobs.active[] | "  #" + (.number // "?") + " " + .name + " — " + (.phase // "?") + " / " + (.status // "?")] | join("\n"))
      else "" end)
    # mail_triage buckets live under .buckets.* — the old .mail_triage.urgent
    # path never existed, which is why the email stopped carrying a mail
    # summary (2026-07-08).
    + (if .mail_triage then
        sec("MAIL")
        + "urgent: " + ((.mail_triage.buckets.urgent // []) | length | tostring)
        + " · review: " + ((.mail_triage.buckets.review // []) | length | tostring)
        + " · noise: " + ((.mail_triage.buckets.noise // []) | length | tostring)
        + (if .sections.mail.summary then " · " + .sections.mail.summary else "" end)
        + (if .mail_triage.error then "\n  triage error: " + .mail_triage.error else "" end)
        + (((.mail_triage.buckets.urgent // [])[:5]) | map("\n  ! " + (.from_name // .from_address // "?") + ": " + (.subject // "?")
            + (if .summary then "\n      " + .summary else "" end)) | join(""))
        + (((.mail_triage.buckets.review // [])[:5]) | map("\n  · " + (.from_name // .from_address // "?") + ": " + (.subject // "?")) | join(""))
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

  # HTML render — the part mail clients actually show. Every section header
  # links to the system it reports on (JobTread / Grafana / Kuma / Umami /
  # dashboard) and every job, lead and invoice deep-links into JobTread.
  # The plain-text render above rides along as the multipart fallback.
  EMAIL_HTML=$(jq -r \
    --arg slot "${SLOT}" \
    --arg dash "https://briefing.hwc.iheartwoodcraft.com" \
    --arg jt "https://app.jobtread.com" \
    --arg grafana "https://grafana.hwc.iheartwoodcraft.com" \
    --arg kuma "https://uptime-kuma.hwc.iheartwoodcraft.com" \
    --arg stats "https://stats.iheartwoodcraft.com" \
    --arg repo "https://github.com/eriqueo/nixos-hwc" '
    def h: tostring | @html;
    def link(u; t): "<a href=\"" + u + "\" style=\"color:#b07d3f;text-decoration:none\">" + t + "</a>";
    def card(title; url; linktext; body):
      "<div style=\"background:#ffffff;border:1px solid #e6e1d8;border-radius:10px;padding:14px 18px;margin:0 0 12px\">"
      + "<div style=\"font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:#8a8378;margin-bottom:8px\">"
      + title
      + (if url != "" then "<span style=\"float:right;text-transform:none;letter-spacing:0\">" + link(url; linktext + " &rarr;") + "</span>" else "" end)
      + "</div>" + body + "</div>";
    def item(s): "<div style=\"padding:3px 0;font-size:14px;line-height:1.45;color:#2d2a26\">" + s + "</div>";
    def meta(s): "<span style=\"color:#8a8378;font-size:13px\">" + s + "</span>";
    def aurl(s):
      if s == "ops" then $kuma
      elif s == "leads" or s == "overdue" or s == "jobs" then $jt
      elif s == "website" then $stats
      elif s == "system" or s == "backup" then $grafana
      elif s == "config_drift" then $repo
      else $dash end;

    .sections as $s |
    "<div style=\"margin:0;padding:18px 10px;background:#f4f1ec\">"
    + "<div style=\"max-width:640px;margin:0 auto;font-family:-apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif\">"

    + "<div style=\"padding:6px 2px 14px\">"
    + "<div style=\"font-size:20px;font-weight:700;color:#2d2a26\">" + ($slot|h) + " Briefing</div>"
    + "<div style=\"font-size:13px;color:#8a8378;margin-top:2px\">" + ((.generated_at // "" | split("T")[0])|h)
    + " &nbsp;&middot;&nbsp; " + link($dash; "open dashboard") + "</div></div>"

    + (if (.alerts // []) | length > 0 then
        (.alerts | map(
          (if .level == "critical" then ["#fdecea", "#b3261e"] else ["#fdf6e3", "#7a5d10"] end) as $c |
          "<div style=\"background:" + $c[0] + ";color:" + $c[1] + ";border-radius:8px;padding:9px 12px;margin:0 0 8px;font-size:13.5px;line-height:1.4\">"
          + "<strong>" + ((.section // "")|h) + "</strong> &middot; " + ((.message // "")|h)
          + " &nbsp;" + link(aurl(.section // ""); "view")
          + "</div>") | join(""))
      else card("Alerts"; ""; ""; item("No alerts. All green.")) end)

    + (if $s.system then
        card("System"; $grafana; "Grafana";
          item(((($s.system.services_active // 0)|tostring)|h) + " services &middot; "
            + ((($s.system.services_failed // 0)|tostring)|h) + " failed &middot; "
            + ((($s.system.containers_running // 0)|tostring)|h) + " containers")
          + (($s.system.failed_units // []) | map(item("<span style=\"color:#b3261e\">&#10007; " + (.|h) + "</span>")) | join(""))
          + (($s.system.storage // []) | map(item((.mount|h) + " " + meta(((.percent // 0)|tostring) + "% used"))) | join(""))
          + (if $s.backup.exit_status then
              item("backup: borg " + (($s.backup.exit_status // "?")|h)
                + (if $s.backup.postgres then " &middot; postgres " + (($s.backup.postgres.exit_status // "?")|h) else "" end))
            else "" end))
      else "" end)

    + (if $s.ops then ($s.ops as $o |
        (($o.service_failures // []) | length) as $nsvc |
        (($o.kuma_failing // []) | length) as $nkuma |
        (($o.journal_errors_top // []) | length) as $nerr |
        (($o.prometheus_targets_down // []) | length) as $ndown |
        (($o.nightly_builds_finished // []) | length) as $nnb |
        card("Overnight Ops &middot; since " + ((($o.since // "")[5:16])|h); $kuma; "Uptime Kuma";
          (if ($nsvc + $nkuma + $nerr + $ndown + $nnb) == 0 then item(meta("Quiet night — no failures, no probe drops, no errors")) else
            (($o.service_failures // []) | map(item("<span style=\"color:#b3261e\">&#10007; " + (.service|h) + "</span> " + meta("failed @ " + ((.time // "")[11:16])))) | join(""))
            + (($o.kuma_failing // []) | map(item("~ " + (.monitor|h) + " " + meta(((.failed_probes|tostring)|h) + " failed probes"))) | join(""))
            + (($o.prometheus_targets_down // []) | map(item("~ target down: " + (.job|h) + " " + meta((.instance // "")|h))) | join(""))
            + (($o.journal_errors_top // []) | map(item((.unit|h) + " " + meta(((.errors|tostring)|h) + " journal errors"))) | join(""))
            + (if $nnb > 0 then item("<strong>Built overnight:</strong> " + (($o.nightly_builds_finished // []) | map(h) | join(", "))) else "" end)
          end)
          + (($o.disk_forecast // [])[:3] | map(item((.mount|h) + " " + meta("full in ~" + ((.days_to_full|tostring)|h) + "d at current growth"))) | join(""))))
      else "" end)

    + (if ($s.calendar.events // []) | length > 0 then
        card("This Week"; ""; "";
          ($s.calendar.events | map(
            item(meta(((.date // ((.start // "") | split("T")[0]))|h)
                + " " + (if .allDay then "all-day" else (((.start // "") | split("T")[1] // "")|h) end)) + " &nbsp;"
              + (.summary|h)
              + (if (.location // "") | startswith("http") then " &middot; " + link(.location; "join link")
                 elif (.location // "") != "" then " " + meta((.location|h)) else "" end))) | join("")))
      else "" end)

    + (if ($s.tasks // {}) | ((.overdue // []) + (.due_today // []) + (.due_this_week // [])) | length > 0 then
        card("Tasks"; $dash; "dashboard";
          (($s.tasks.overdue // []) | map(item("<span style=\"color:#b3261e;font-weight:600\">OVERDUE</span> " + meta(((.due_date // "")|h)) + " &nbsp;" + (.name|h))) | join(""))
          + (($s.tasks.due_today // []) | map(item("<strong>today</strong> &nbsp;" + (.name|h))) | join(""))
          + (($s.tasks.due_this_week // []) | map(item(meta(((.due_date // "")|h)) + " &nbsp;" + (.name|h))) | join("")))
      else "" end)

    + (if ($s.leads.items // []) | length > 0 then
        card("Leads (" + (($s.leads.items | length | tostring)|h) + ")"; $jt; "JobTread";
          ($s.leads.items | map(
            item((if .url then link(.url; (.name|h)) else (.name|h) end)
              + (if (.job_type // "") != "" then " " + meta((.job_type|h)) else "" end)
              + " " + meta(((.days_old|tostring)|h) + "d old"))) | join("")))
      else "" end)

    + (if ($s.overdue.count // 0) > 0 then
        card("Overdue Invoices &middot; $" + ((($s.overdue.total_amount // 0) | round | tostring)|h); $jt; "JobTread";
          ($s.overdue.items | map(
            item("<strong>$" + (((.amount // 0) | round | tostring)|h) + "</strong> &nbsp;"
              + (if .url then link(.url; ((.job_name // .name)|h)) else ((.job_name // .name)|h) end)
              + (if .days_past_due then " " + meta(((.days_past_due|tostring)|h) + "d past due") else "" end))) | join("")))
      else "" end)

    + (if ($s.jobs.active // []) | length > 0 then
        card("Active Jobs (" + (($s.jobs.active | length | tostring)|h) + ")"; $jt; "JobTread";
          ($s.jobs.active | map(
            item(meta("#" + ((.number // "?")|h)) + " &nbsp;"
              + (if .url then link(.url; (.name|h)) else (.name|h) end)
              + " " + meta(((.phase // "?")|h) + " / " + ((.status // "?")|h)))) | join("")))
      else "" end)

    + (if .mail_triage then
        card("Mail"; $dash; "triage";
          item("urgent " + ((.mail_triage.buckets.urgent // []) | length | tostring)
            + " &middot; review " + ((.mail_triage.buckets.review // []) | length | tostring)
            + " &middot; noise " + ((.mail_triage.buckets.noise // []) | length | tostring)
            + (if $s.mail.summary then " &middot; " + meta(($s.mail.summary|h)) else "" end))
          + (if .mail_triage.error then item("<span style=\"color:#b3261e\">triage error: " + (.mail_triage.error|h) + "</span>") else "" end)
          + (((.mail_triage.buckets.urgent // [])[:5]) | map(
              item("<span style=\"color:#b3261e;font-weight:600\">!</span> " + ((.from_name // .from_address // "?")|h) + ": " + ((.subject // "?")|h)
                + (if .summary then "<br><span style=\"color:#8a8378;font-size:13px;padding-left:14px\">" + (.summary|h) + "</span>" else "" end))) | join(""))
          + (((.mail_triage.buckets.review // [])[:5]) | map(
              item(meta("&middot;") + " " + ((.from_name // .from_address // "?")|h) + ": " + ((.subject // "?")|h))) | join("")))
      else "" end)

    + (if $s.website and ($s.website | length > 0) then
        card("Website"; $stats; "Umami";
          item(((($s.website.visitors_24h // 0)|tostring)|h) + " visitors 24h &middot; "
            + ((($s.website.visitors_7d // 0)|tostring)|h) + " visitors / "
            + ((($s.website.pageviews_7d // 0)|tostring)|h) + " views 7d")
          + item("calculator leads: " + ((($s.website.leads_24h // 0)|tostring)|h) + " today &middot; "
            + ((($s.website.leads_7d // 0)|tostring)|h) + " this week")
          + (($s.website.top_pages_7d // [])[:3] | map(item(meta((.url|h) + " — " + ((.views|tostring)|h) + " views"))) | join("")))
      else "" end)

    + "<div style=\"text-align:center;padding:10px 0 4px;font-size:12px;color:#8a8378\">"
    + link($dash; "dashboard") + " &nbsp;&middot;&nbsp; " + link($grafana; "grafana")
    + " &nbsp;&middot;&nbsp; " + link($kuma; "uptime kuma") + " &nbsp;&middot;&nbsp; " + link($jt; "jobtread")
    + " &nbsp;&middot;&nbsp; " + link($stats; "analytics")
    + "</div></div></div>"
  ' "${OUTPUT_DIR}/briefing.json" 2>>"${LOG_FILE}") || EMAIL_HTML=""
  if [ -n "${EMAIL_BODY}" ]; then
    ALERT_COUNT=$(jq -r '(.alerts // []) | length' "${OUTPUT_DIR}/briefing.json" 2>/dev/null || echo "?")
    SUBJECT="${SLOT} Briefing $(date +%Y-%m-%d)"
    [ "${ALERT_COUNT}" != "0" ] && SUBJECT="${SUBJECT} — ${ALERT_COUNT} alert(s)"
    # From office@, NOT eric@: self-sent mail (eric→eric) gets Proton's
    # sent+auto-archive treatment and never shows in the Inbox (found 2026-07-06,
    # first live run). office@ is an alias on the same bridge; lands in Inbox.
    # multipart/alternative: HTML is what clients show; the plain render is the
    # fallback (and what notmuch/aerc searches). If the HTML render failed,
    # degrade to plain-only rather than skipping the send.
    BOUNDARY="hwc-briefing-$(date +%s)"
    if [ -n "${EMAIL_HTML}" ]; then
      MSG=$(printf 'Subject: %s\nFrom: office@iheartwoodcraft.com\nTo: eric@iheartwoodcraft.com\nMIME-Version: 1.0\nContent-Type: multipart/alternative; boundary="%s"\n\n--%s\nContent-Type: text/plain; charset=utf-8\n\n%s\n\n--%s\nContent-Type: text/html; charset=utf-8\n\n%s\n\n--%s--\n' \
        "${SUBJECT}" "${BOUNDARY}" "${BOUNDARY}" "${EMAIL_BODY}" "${BOUNDARY}" "${EMAIL_HTML}" "${BOUNDARY}")
    else
      log "WARN: HTML render failed — sending plain-text only"
      MSG=$(printf 'Subject: %s\nFrom: office@iheartwoodcraft.com\nTo: eric@iheartwoodcraft.com\n\n%s\n' \
        "${SUBJECT}" "${EMAIL_BODY}")
    fi
    if printf '%s\n' "${MSG}" | "${MSMTP_BIN}" -a proton-office eric@iheartwoodcraft.com 2>>"${LOG_FILE}"; then
      log "OK: Briefing emailed (${SLOT}, html: $([ -n "${EMAIL_HTML}" ] && echo yes || echo no))"
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
