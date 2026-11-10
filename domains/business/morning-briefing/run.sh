#!/usr/bin/env bash
# domains/business/morning-briefing/run.sh
#
# Step 1: local sources → output/briefing.json
# Step 2: notmuch → resident Laya → output/mail-triage.json
# Step 3: jq merge → .mail_triage injected into briefing.json
# Step 4: atomically publish output/briefing.json for Caddy

set -euo pipefail

host_exec() {
  if [ -n "${BRIEFING_HOST:-}" ]; then
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "${BRIEFING_HOST}" "$(printf '%q ' "$@")"
  else
    "$@"
  fi
}

# systemd may exit nonzero while returning a useful Result; an absent Result
# means no backup evidence, rather than an invented successful run.
backup_unit_status() {
  local unit="$1" result exitcode last_raw last=""
  result=$(host_exec "${SYSTEMCTL}" show "${unit}.service" -p Result --value 2>/dev/null || true)
  exitcode=$(host_exec "${SYSTEMCTL}" show "${unit}.service" -p ExecMainStatus --value 2>/dev/null || true)
  last_raw=$(host_exec "${SYSTEMCTL}" show "${unit}.service" -p ExecMainExitTimestamp --value 2>/dev/null || true)
  [ -n "${last_raw}" ] && last=$(date -Iseconds -d "${last_raw}" 2>/dev/null || true)
  jq -n --arg unit "${unit}" --arg result "${result}" --arg exitcode "${exitcode}" --arg last "${last}" '
    if $result == "" then {} else
      {exit_status:(if $result == "success" and $exitcode == "0" then "success" else "error" end),
       unit:$unit, service_result:$result, last_run:(if $last == "" then null else $last end)}
    end'
}

acquire_briefing_lock() {
  exec {BRIEFING_LOCK_FD}>"$1" || return 2
  "${FLOCK_BIN:-/run/current-system/sw/bin/flock}" -n -E 75 "${BRIEFING_LOCK_FD}"
}

main() {
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${AGENT_DIR}/output"
DASHBOARD_DIR="${AGENT_DIR}/dashboard"
LOG_FILE="${AGENT_DIR}/logs/run.log"
LOCK_FILE="${BRIEFING_LOCK_FILE:-/tmp/morning-briefing.lock}"

mkdir -p "${OUTPUT_DIR}" "${DASHBOARD_DIR}" "${AGENT_DIR}/logs"

log() { echo "$(date -Iseconds) $*" >> "${LOG_FILE}"; }

# The open descriptor owns the lock; it is released on process exit, without
# stale PID reuse or a check/write race. Busy runs leave the current run alone.
if acquire_briefing_lock "${LOCK_FILE}"; then
  :
else
  lock_rc=$?
  if [ "${lock_rc}" -eq 75 ]; then
    log "SKIP: Previous run still active"
    return 0
  fi
  log "ERROR: cannot acquire briefing lock (exit ${lock_rc})"
  return "${lock_rc}"
fi

log "START"
cd "${AGENT_DIR}"

log "STEP 1: Gathering deterministic data locally (no Claude / no MCP)..."
STEP1_START=$(date +%s)

# Gather directly as eric so the headless service never depends on interactive
# tool approvals. Laya handles mail through its bounded local socket. JobTread
# jobs and invoices use PAVE; tasks use the loopback gateway below.

SYSTEMCTL="/run/current-system/sw/bin/systemctl"; [ -x "${SYSTEMCTL}" ] || SYSTEMCTL="systemctl"

# Host-health probes (systemctl, df, journal, failure log, VPN status) describe
# the media/storage host. Since service split wave 2 the briefing runs on
# hwc-work, so BRIEFING_HOST (hwc.business.morningBriefing.hostHealthFrom) runs
# them there over ssh; unset = this host. `-n` keeps ssh off stdin — one call
# sits inside a `while read` loop. printf %q keeps each argument one word
# through the remote shell.
# Permanent by design: journal, VPN and backup details remain source-owned.
# A central green probe cannot replace them; five sampled SSH reads total 0.73 s.

KHAL_BIN="/etc/profiles/per-user/eric/bin/khal"

# -- system: service counts + overall state (systemctl is read-only/always-safe) --
SERVICES_ACTIVE=$(host_exec "${SYSTEMCTL}" list-units --type=service --state=running --no-legend 2>/dev/null | wc -l | tr -d ' ' || echo 0)
# Failed unit NAMES, not just a count — "1 failed service(s)" with no name is
# an alert you can't act on (2026-07-08 usability pass).
FAILED_UNITS_JSON=$(host_exec "${SYSTEMCTL}" list-units --type=service --state=failed --no-legend --plain 2>/dev/null \
  | awk '{print $1}' | jq -R -s 'split("\n") | map(select(length>0))' 2>/dev/null || echo '[]')
echo "${FAILED_UNITS_JSON}" | jq empty 2>/dev/null || FAILED_UNITS_JSON='[]'
# Eric's USER units too (hwc-tracker, tracker-relay, mail-health, agent-state-sync
# all run under `systemd --user`). The system scan above cannot see them, so
# mail-health sat failed on hwc-work with no card (2026-10-10). Names carry a
# `user:` prefix so the alert says which manager to inspect. Needs the user bus;
# when it is unreachable (ssh without a session) the list is simply empty.
FAILED_USER_UNITS_JSON=$(XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
  host_exec "${SYSTEMCTL}" --user list-units --type=service --state=failed --no-legend --plain 2>/dev/null \
  | awk '{print "user:" $1}' | jq -R -s 'split("\n") | map(select(length>5))' 2>/dev/null || echo '[]')
echo "${FAILED_USER_UNITS_JSON}" | jq empty 2>/dev/null || FAILED_USER_UNITS_JSON='[]'
FAILED_UNITS_JSON=$(jq -nc --argjson a "${FAILED_UNITS_JSON}" --argjson b "${FAILED_USER_UNITS_JSON}" '$a + $b')
SERVICES_FAILED=$(echo "${FAILED_UNITS_JSON}" | jq 'length')
# Containers = running podman-*.service units (works as eric; podman ps would
# need the root socket). The dashboard used to render literal "undefined" here.
CONTAINERS_RUNNING=$(host_exec "${SYSTEMCTL}" list-units --type=service --state=running --no-legend --plain 'podman-*' 2>/dev/null | wc -l | tr -d ' ' || echo 0)
[ -n "${CONTAINERS_RUNNING}" ] || CONTAINERS_RUNNING=0
# NB: `is-system-running` EXITS NON-ZERO when not "running" (e.g. "degraded"),
# so a `|| echo` fallback would fire ON TOP of the real output and concatenate
# ("degraded\nunknown"). Capture the output, swallow the exit with `|| true`,
# then default only if it came back empty.
SYS_STATE=$(host_exec "${SYSTEMCTL}" is-system-running 2>/dev/null) || true
[ -n "${SYS_STATE}" ] || SYS_STATE="unknown"
[ -n "${SERVICES_ACTIVE}" ] || SERVICES_ACTIVE=0
[ -n "${SERVICES_FAILED}" ] || SERVICES_FAILED=0

# -- storage: df for the key mounts → [{mount, percent}] --
STORAGE_JSON=$(host_exec df -h --output=target,pcent / /mnt/hot /mnt/media 2>/dev/null \
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
  # khal's output is captured first: under pipefail a failing khal used to let
  # jq print {events:[]} AND fire the `|| echo` fallback, leaving two JSON
  # documents that `jq empty` accepts and --argjson rejects, so the whole
  # briefing assembly failed (hwc-work, 2026-09-25).
  KHAL_OUT=$("${KHAL_BIN}" list \
    --format='{start-date}T{start-time}|{end-date}T{end-time}|{title}|{location}|{all-day}' \
    today 7d 2>/dev/null) || KHAL_OUT=""
  CAL_JSON=$(printf '%s' "${KHAL_OUT}" \
    | jq -R -s 'split("\n") | map(select(length>0)) | map(split("|")) | map(select(length>=5)) | map({
        summary: .[2],
        start: .[0],
        end: .[1],
        date: (.[0] | split("T")[0]),
        location: (if .[3] == "" then null else .[3] end),
        allDay: (.[4] | ascii_downcase == "true")
      }) | { events: . }' 2>/dev/null || echo '{"events": []}')
  echo "${CAL_JSON}" | jq -e 'type == "object"' >/dev/null 2>&1 || CAL_JSON='{"events": []}'
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
BACKUP_JSON=$(backup_unit_status "${BK_UNIT}")
BK_STATUS=$(jq -r '.exit_status // empty' <<<"${BACKUP_JSON}")
if [ -n "${BK_STATUS}" ]; then
  BK_RESULT=$(jq -r '.service_result' <<<"${BACKUP_JSON}")
  BK_LAST=$(jq -r '.last_run // empty' <<<"${BACKUP_JSON}")
  BK_NEXT_RAW=$(host_exec "${SYSTEMCTL}" show "${BK_UNIT}.timer" -p NextElapseUSecRealtime --value 2>/dev/null || true)
  BK_NEXT=""; [ -n "${BK_NEXT_RAW}" ] && BK_NEXT=$(date -Iseconds -d "${BK_NEXT_RAW}" 2>/dev/null || true)
  BACKUP_JSON=$(jq --arg next "${BK_NEXT}" '. + {next_scheduled:(if $next == "" then null else $next end), archive_count:null, total_size:null}' <<<"${BACKUP_JSON}")
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
PG_JSON=$(backup_unit_status "${PG_UNIT}")
PG_STATUS=$(jq -r '.exit_status // empty' <<<"${PG_JSON}")
if [ -n "${PG_STATUS}" ]; then
  PG_RESULT=$(jq -r '.service_result' <<<"${PG_JSON}")
  BACKUP_JSON=$(jq --argjson postgres "${PG_JSON}" '. + {postgres:$postgres}' <<<"${BACKUP_JSON}")
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
SVC_FAIL_JSON=$({ host_exec grep -h '^\[20' /var/log/hwc/notifications/service-failures.log 2>/dev/null || true; } \
  | awk -v since="${OPS_SINCE}" -F'[][]' '$2 >= since && index($0, "Service failure: ") { split($0, a, "Service failure: "); print $2 "|" a[2] }' \
  | jq -R -s 'split("\n") | map(select(length>0)) | map(split("|") | {time: .[0], service: .[1]})' 2>/dev/null || echo '[]')
echo "${SVC_FAIL_JSON}" | jq empty 2>/dev/null || SVC_FAIL_JSON='[]'
# Annotate each failure event with whether the unit is active NOW. A crash
# systemd (or the gluetun self-heal) already recovered is history, not an
# incident — 2026-07-12 the orchestrated VPN-stack restart reported
# "2 service failure event(s)" for units that were healthy, indistinguishable
# from a real outage. Recovered vs still-down get separate alerts below.
SVC_FAIL_ANNOTATED=$(echo "${SVC_FAIL_JSON}" | jq -r '.[] | [.time, .service] | @tsv' 2>/dev/null \
  | while IFS=$'\t' read -r t s; do
      [ -n "${s}" ] || continue
      state=$(host_exec "${SYSTEMCTL}" is-active "${s}" 2>/dev/null) || true
      jq -cn --arg time "${t}" --arg service "${s}" --arg state "${state:-unknown}" \
        '{time:$time, service:$service, active_now:($state=="active")}'
    done | jq -s '.' 2>/dev/null || echo '')
if [ -n "${SVC_FAIL_ANNOTATED}" ] && echo "${SVC_FAIL_ANNOTATED}" | jq empty 2>/dev/null; then
  SVC_FAIL_JSON="${SVC_FAIL_ANNOTATED}"
fi

# Service liveness from the declarative blackbox probes (probe-services-*,
# ~37 services, each with a human `service` label) — replaced the Uptime Kuma
# journal scrape when Kuma was decommissioned (2026-07-09). Two views merged
# per service: down RIGHT NOW (probe_success == 0) and >1% downtime over 24h.
PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
SVC_DOWN_NOW=$("${CURL_BIN}" -sG -m 10 "${PROM_URL}/api/v1/query" \
  --data-urlencode 'query=probe_success{job=~"probe-services-.*"} == 0' 2>/dev/null \
  | jq '[.data.result[]? | {service: (.metric.service // .metric.instance // "?")}]' 2>/dev/null || echo '[]')
echo "${SVC_DOWN_NOW}" | jq empty 2>/dev/null || SVC_DOWN_NOW='[]'
SVC_FLAKY=$("${CURL_BIN}" -sG -m 10 "${PROM_URL}/api/v1/query" \
  --data-urlencode 'query=(1 - avg_over_time(probe_success{job=~"probe-services-.*"}[24h])) * 100 > 1' 2>/dev/null \
  | jq '[.data.result[]? | {service: (.metric.service // .metric.instance // "?"), pct: (.value[1] | tonumber? // 0 | round)}]' 2>/dev/null || echo '[]')
echo "${SVC_FLAKY}" | jq empty 2>/dev/null || SVC_FLAKY='[]'
SERVICES_DOWN_JSON=$(jq -n --argjson now "${SVC_DOWN_NOW}" --argjson flaky "${SVC_FLAKY}" '
  ($now | map(.service)) as $downset |
  ($flaky | map({service, down_now: (.service as $x | $downset | index($x) != null), downtime_pct_24h: .pct})) as $f |
  ($f | map(.service)) as $flakyset |
  ($now | map(select(.service as $x | ($flakyset | index($x)) == null))
        | map({service, down_now: true, downtime_pct_24h: null})) as $extra |
  ($f + $extra) | sort_by(-(.downtime_pct_24h // 100))' 2>/dev/null || echo '[]')
echo "${SERVICES_DOWN_JSON}" | jq empty 2>/dev/null || SERVICES_DOWN_JSON='[]'

# Top journal error sources — catches silent crash-loops (the vdirsyncer
# every-15-min failure ran for hours with nothing surfacing it). podman-*
# units are EXCLUDED: containers write INFO logs to stderr, which the journal
# stamps priority=err — authentik alone "errors" 2400×/day that way, drowning
# real signal. Container breakage surfaces via probes + service_failures instead.
# OPS_ERR_FLOOR: drop units with a trivial one-off count (single activation
# blips like init.scope ×3, run-*.scope ×4) — a crash-loop clears this easily.
OPS_ERR_FLOOR=5
ERR_TOP_JSON=$({ host_exec "${JOURNALCTL}" -p err --since "${OPS_SINCE}" --no-pager -q -o json 2>/dev/null || true; } \
  | jq -s --argjson floor "${OPS_ERR_FLOOR}" 'map(._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER // "kernel") | map(select(startswith("podman-") | not)) | group_by(.) | map({unit: .[0], errors: length}) | map(select(.errors >= $floor)) | sort_by(-.errors) | .[:5]' 2>/dev/null || echo '[]')
echo "${ERR_TOP_JSON}" | jq empty 2>/dev/null || ERR_TOP_JSON='[]'

# Prometheus: scrape targets down + disk days-to-full forecast (predictive
# beats the static df percent). Both best-effort against loopback :9090.
PROM_DOWN_JSON=$("${CURL_BIN}" -sG -m 10 "${PROM_URL}/api/v1/query" --data-urlencode 'query=up == 0' 2>/dev/null \
  | jq '[.data.result[]? | {job: (.metric.job // "?"), instance: (.metric.instance // "?")}]' 2>/dev/null || echo '[]')
echo "${PROM_DOWN_JSON}" | jq empty 2>/dev/null || PROM_DOWN_JSON='[]'
DISK_FORECAST_JSON=$("${CURL_BIN}" -sG -m 10 "${PROM_URL}/api/v1/query" \
  --data-urlencode 'query=node_filesystem_avail_bytes{mountpoint=~"/|/mnt/hot|/mnt/media"} / - deriv(node_filesystem_avail_bytes{mountpoint=~"/|/mnt/hot|/mnt/media"}[24h]) / 86400' 2>/dev/null \
  | jq '[.data.result[]? | {mount: (.metric.mountpoint // "?"), days_to_full: (.value[1] | tonumber? // null)}
        | select(.days_to_full != null and .days_to_full > 0 and .days_to_full < 365)
        | .days_to_full |= round] | sort_by(.days_to_full)' 2>/dev/null || echo '[]')
echo "${DISK_FORECAST_JSON}" | jq empty 2>/dev/null || DISK_FORECAST_JSON='[]'

# VPN tunnels: each gluetun instance's health state machine publishes
# status.json (see domains/networking/gluetun — hwc.networking.gluetun.stateRoot).
# The check alerts ONLY on transitions, so a tunnel that went degraded at 21:00
# and is still degraded at 06:00 has been silent all night by design; this is
# where that silence gets a voice. A 33-hour outage in Aug 2026 went unactioned
# behind 43 identical alerts — the fix is one alert there and the standing state
# here, not more alerts.
VPN_JSON=$({ host_exec sh -c 'cat /var/lib/hwc/gluetun/*/status.json' 2>/dev/null || true; } \
  | jq -s 'map({instance, state, reason, forwarded_port, restart_count,
                degraded_since, last_check})' 2>/dev/null || echo '[]')
echo "${VPN_JSON}" | jq empty 2>/dev/null || VPN_JSON='[]'

# Nightly-builds gauntlet: cards that landed in _finished/ since yesterday
# evening (the 01:30 run completes hours before the 6am briefing).
NB_DIR="/home/eric/900_vaults/brain/_inbox/nightly_builds/_finished"
NB_JSON=$({ find "${NB_DIR}" -mindepth 1 -maxdepth 1 -newermt "${OPS_SINCE}" -printf '%f\n' 2>/dev/null || true; } \
  | jq -R -s 'split("\n") | map(select(length>0)) | sort' 2>/dev/null || echo '[]')
echo "${NB_JSON}" | jq empty 2>/dev/null || NB_JSON='[]'

OPS_JSON=$(jq -n \
  --arg since "${OPS_SINCE}" \
  --argjson svc "${SVC_FAIL_JSON}" \
  --argjson probes "${SERVICES_DOWN_JSON}" \
  --argjson errs "${ERR_TOP_JSON}" \
  --argjson down "${PROM_DOWN_JSON}" \
  --argjson disk "${DISK_FORECAST_JSON}" \
  --argjson vpn "${VPN_JSON}" \
  --argjson nb "${NB_JSON}" '
  { since: $since
  , service_failures: $svc
  , services_down: $probes
  , journal_errors_top: $errs
  , prometheus_targets_down: $down
  , disk_forecast: $disk
  , vpn_tunnels: $vpn
  , nightly_builds_finished: $nb
  }' 2>/dev/null || echo '{}')
echo "${OPS_JSON}" | jq empty 2>/dev/null || OPS_JSON='{}'

ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq \
  --argjson svc "${SVC_FAIL_JSON}" \
  --argjson probes "${SERVICES_DOWN_JSON}" \
  --argjson down "${PROM_DOWN_JSON}" \
  --argjson vpn "${VPN_JSON}" \
  --argjson disk "${DISK_FORECAST_JSON}" '
  . + (($vpn | map(select(.state == "failed"))) as $vfailed
       | if ($vfailed | length) > 0 then [{level:"critical", section:"ops",
        message:"VPN auto-recovery EXHAUSTED: \($vfailed | map("\(.instance) (\(.reason)) — \(.restart_count) restarts, down \((now - .degraded_since) / 3600 | floor)h") | join("; ")) — the download stack has no egress until this is fixed"}] else [] end)
    + (($vpn | map(select(.state == "degraded"))) as $vdeg
       | if ($vdeg | length) > 0 then [{level:"warning", section:"ops",
        message:"VPN degraded and self-healing: \($vdeg | map("\(.instance) (\(.reason)), down \((now - .degraded_since) / 60 | floor)m") | join("; "))"}] else [] end)
    + (($vpn | map(select(.state == "healthy" and ((now - .last_check) > 3600)))) as $vstale
       | if ($vstale | length) > 0 then [{level:"warning", section:"ops",
        message:"VPN health check has not run in over an hour: \($vstale | map(.instance) | join(", ")) — the monitor itself may be dead"}] else [] end)
    + (($svc | map(select(.active_now == false))) as $dead
       | if ($dead | length) > 0 then [{level:"critical", section:"ops",
        message:"\($dead | length) service(s) failed overnight and are STILL DOWN: \($dead | map(.service) | unique | join(", ")) — systemctl status <unit>"}] else [] end)
    + (($svc | map(select(.active_now != false))) as $rec
       | if ($rec | length) > 0 then [{level:"info", section:"ops",
        message:"\($rec | length) service(s) crashed and auto-recovered overnight (no action unless recurring): \($rec | map(.service) | unique | join(", "))"}] else [] end)
    + (if ($probes | map(select(.down_now)) | length) > 0 then [{level:"critical", section:"ops",
        message:"\($probes | map(select(.down_now)) | length) service(s) failing liveness probes NOW: \($probes | map(select(.down_now)) | map(.service) | join(", "))"}] else [] end)
    + (if ($probes | map(select(.down_now | not)) | length) > 0 then [{level:"warning", section:"ops",
        message:"Flaky overnight (>1% downtime, up now): \($probes | map(select(.down_now | not)) | map("\(.service) (\(.downtime_pct_24h)%)") | join(", "))"}] else [] end)
    + (if ($down | length) > 0 then [{level:"warning", section:"ops",
        message:"\($down | length) Prometheus target(s) down: \($down | map(.job) | unique | join(", "))"}] else [] end)
    + (if ($disk | map(select(.days_to_full <= 14)) | length) > 0 then [{level:"critical", section:"ops",
        message:"Disk filling fast: \($disk | map(select(.days_to_full <= 14)) | map("\(.mount) full in ~\(.days_to_full)d") | join(", "))"}] else [] end)
  ' 2>/dev/null || echo "${ALERTS_JSON}")
echo "${ALERTS_JSON}" | jq empty 2>/dev/null || ALERTS_JSON='[]'

# -- refinery: the refinement-engine board, triaged like mail. Reads the item
#    store directly (one .md per Item, canonical JSON in a fenced block) — a
#    local file read, no service round-trip. Buckets: action = parked/failed/
#    ready-to-promote (needs Eric), active = in-flight pipeline work, hopper =
#    raw ideas. gather-refinery.mjs emits {} on any failure, so it never breaks
#    the briefing; the section simply renders empty. --
REFINERY_ITEMS_DIR="${REFINERY_ITEMS_DIR:-/var/lib/refinery/items}"
REFINERY_JSON=$(REFINERY_ITEMS_DIR="${REFINERY_ITEMS_DIR}" node "${AGENT_DIR}/gather-refinery.mjs" 2>>"${LOG_FILE}" || echo '{}')
echo "${REFINERY_JSON}" | jq empty 2>/dev/null || REFINERY_JSON='{}'
# Alert only on FAILED items — parked is normal "waiting on a decision", not an
# error; a broken gate/executor run is what's worth surfacing.
REFINERY_FAILED=$(echo "${REFINERY_JSON}" | jq '[.stages.action[]? | select(.state=="failed")] | length' 2>/dev/null || echo 0)
if [ "${REFINERY_FAILED:-0}" -gt 0 ] 2>/dev/null; then
  ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq --argjson n "${REFINERY_FAILED}" '. + [{level:"warning",section:"refinery",message:"\($n) refinery item(s) in a failed state"}]' 2>/dev/null || echo "${ALERTS_JSON}")
  echo "${ALERTS_JSON}" | jq empty 2>/dev/null || ALERTS_JSON='[]'
fi

# -- agents: the agent-workspace ledger (~/800_agents). `ws ledger --json` is the
#    one producer of these facts AND of the rendered line, so this brief and the
#    MCP morning-brief tool print the same text. {} on any failure, like refinery.
#    Alerts: downloads/agent grew >100 MB in a week; the watchdog's arm date
#    passed with no accepted replay (it stays note-taking; design v4.2 fix 1). --
WS_BIN="${WS_BIN:-/etc/profiles/per-user/eric/bin/ws}"
AGENTS_JSON=$("${WS_BIN}" ledger --json 2>>"${LOG_FILE}" || echo '{}')
echo "${AGENTS_JSON}" | jq -e 'type == "object"' >/dev/null 2>&1 || AGENTS_JSON='{}'
AGENTS_ALERTS=$(echo "${AGENTS_JSON}" | jq -c '
  [ (if .downloads.red then {level:"warning",section:"agents",
      message:"downloads/agent grew \(.downloads.growthBytes / 1048576 | floor) MB this week (limit 100 MB)"} else empty end),
    (if .guard.armOverdue then {level:"warning",section:"agents",
      message:"The watchdog passed its arm date (\(.guard.armDate)) with no accepted replay, so it is still only taking notes"} else empty end) ]' 2>/dev/null || echo '[]')
ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq --argjson a "${AGENTS_ALERTS}" '. + $a' 2>/dev/null || echo "${ALERTS_JSON}")
echo "${ALERTS_JSON}" | jq empty 2>/dev/null || ALERTS_JSON='[]'

# -- projects: the tracker hub on this host. /api/attention is the one ranked
#    list of what waits on Eric (decide, in person by place, unsorted, owed by an
#    agent); /api/portfolio adds overdue products and the live-product cap.
#    gather-projects.mjs groups, it derives nothing, and emits {} on any failure.
#    The same list is one hwc-notify message on the `projects` topic, so it
#    reaches Discord as well as this page; the dispatcher dedupes by title
#    within a day. --
PROJECTS_JSON=$(TRACKER_URL="${TRACKER_URL:-http://127.0.0.1:8765}" timeout 30 node "${AGENT_DIR}/gather-projects.mjs" 2>>"${LOG_FILE}" || echo '{}')
echo "${PROJECTS_JSON}" | jq empty 2>/dev/null || PROJECTS_JSON='{}'
PROJECT_ALERTS=$(echo "${PROJECTS_JSON}" | jq -c '
  [ (if (.counts.overdue // 0) > 0 then {level:"warning",section:"projects",
      message:"\(.counts.overdue) project(s) past their review date: \(.overdue | map(.title) | join(", "))"} else empty end),
    (if (.counts.decide // 0) > 0 then {level:"warning",section:"projects",
      message:"\(.counts.decide) decision(s) wait on you: \(.decide | map("\(.title) \(.card // "")") | join(", "))"} else empty end),
    (if (.counts.inPerson // 0) > 0 then {level:"warning",section:"projects",
      message:"\(.counts.inPerson) errand(s) at \(.inPerson | map(.where) | join(", "))"} else empty end),
    (if (.counts.unsorted // 0) > 0 then {level:"warning",section:"projects",
      message:"\(.counts.unsorted) wait(s) on you that no agent has sorted: \(.unsorted | map("\(.title) (\(.days // 0)d)") | join(", "))"} else empty end),
    (if (.cap.over // false) then {level:"warning",section:"projects",
      message:"\(.cap.products) live products exceed the cap of \(.cap.limit); park or finish one"} else empty end) ]' 2>/dev/null || echo '[]')
ALERTS_JSON=$(echo "${ALERTS_JSON}" | jq --argjson a "${PROJECT_ALERTS}" '. + $a' 2>/dev/null || echo "${ALERTS_JSON}")
echo "${ALERTS_JSON}" | jq empty 2>/dev/null || ALERTS_JSON='[]'
if [ "$(echo "${PROJECTS_JSON}" | jq -r '.actionable // false')" = true ] && [ -n "${HWC_NOTIFY_URL:-}" ]; then
  NOTIFY_PAYLOAD=$(echo "${PROJECTS_JSON}" | jq -c --arg day "$(date +%F)" '
    {topic:"projects", title:"[tracker] \($day) projects digest", priority:3, source:"morning-briefing", tags:["tracker"],
     body:(([ (.overdue[] | "overdue \(.days)d: \(.title)"),
             (.decide[] | "decide: \(.title) \(.card // "") — \(.ask)"),
             (.inPerson[] | .where as $where | .items[] | "at \($where): \(.title) — \(.ask)"),
             (.unsorted[] | "waiting on you \(.days // 0)d: \(.title) — \(.ask)"),
             (if .cap.over then "\(.cap.products) live products over the cap of \(.cap.limit)" else empty end) ]
           | .[:10] | join("\n")) + "\n" + .url)}')
  curl -fsS --max-time 10 -X POST -H 'content-type: application/json' -d "${NOTIFY_PAYLOAD}" "${HWC_NOTIFY_URL}/notify" >/dev/null 2>>"${LOG_FILE}" \
    || log "WARN: projects digest notification failed"
fi

# -- research: research-scout's review lane. How many articles wait for Eric to
#    read, the top few, and the standing themes report over the takeaways he has
#    already written. Loopback REST to the unified server (:8422/api/<tool>) —
#    NOT MCP, for the same permission reason every other gather here is local.
#    Reads the lessons snapshot with generate:false, so the briefing never
#    spends an LLM call. gather-research.mjs emits {} on any failure. --
RESEARCH_JSON=$(timeout 30 node "${AGENT_DIR}/gather-research.mjs" 2>>"${LOG_FILE}" || echo '{}')
echo "${RESEARCH_JSON}" | jq empty 2>/dev/null || RESEARCH_JSON='{}'

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
  --argjson backup "${BACKUP_JSON}" \
  --argjson refinery "${REFINERY_JSON}" \
  --argjson agents "${AGENTS_JSON}" \
  --argjson research "${RESEARCH_JSON}" \
  --argjson projects "${PROJECTS_JSON}" '
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
      refinery: $refinery,
      agents: $agents,
      research: $research,
      projects: $projects,
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

# One Laya runner owns classification, tags, human locks, and the case ledger.
# The same idempotent path serves the briefing and the intraday timer.
log "STEP 2: Mail triage (triage-mail.sh baseline)..."
STEP2_START=$(date +%s)
if "${AGENT_DIR}/triage-mail.sh" baseline; then
  log "STEP 2: OK"
else
  log "WARN: triage-mail.sh baseline reported failure (see [triage-baseline] log lines)"
fi
STEP2_END=$(date +%s)
log "STEP 2: completed in $((STEP2_END - STEP2_START))s"

# hwc_today (gateway) derives the ranked action queue from the briefing just
# written (incl. mail triage) + its dismiss state; inject it as sections.today
# so the dashboard and email render it statically. Best-effort: {} on failure
# and the TODAY block simply doesn't render.
TODAY_JSON=$(timeout 30 node "${AGENT_DIR}/gather-today.mjs" 2>>"${LOG_FILE}" || echo '{}')
echo "${TODAY_JSON}" | jq empty 2>/dev/null || TODAY_JSON='{}'
if [ "$(echo "${TODAY_JSON}" | jq '.items? | length' 2>/dev/null || echo 0)" -gt 0 ] 2>/dev/null; then
  if jq --argjson today "${TODAY_JSON}" '.sections.today = $today' \
      "${OUTPUT_DIR}/briefing.json" > "${OUTPUT_DIR}/briefing.json.tmp" 2>>"${LOG_FILE}" \
      && jq empty "${OUTPUT_DIR}/briefing.json.tmp" 2>/dev/null; then
    mv "${OUTPUT_DIR}/briefing.json.tmp" "${OUTPUT_DIR}/briefing.json"
    log "STEP 2c: OK Today queue injected ($(echo "${TODAY_JSON}" | jq '.items | length') items)"
  else
    rm -f "${OUTPUT_DIR}/briefing.json.tmp"
    log "STEP 2c: WARN today injection produced invalid JSON — briefing kept without it"
  fi
else
  log "STEP 2c: today queue empty or gateway unreachable — skipped"
fi

if [ -f "${OUTPUT_DIR}/briefing.json" ]; then
  if "${AGENT_DIR}/triage-mail.sh" publish; then
    log "OK: Published to dashboard/"
  else
    log "ERROR: Dashboard publish failed"
  fi
fi
# Today-queue agent reports: serve output/reports/ through the dashboard vhost
# (same symlink pattern as briefing.json).
mkdir -p "${OUTPUT_DIR}/reports" "${OUTPUT_DIR}/dispatch"
[ -L "${DASHBOARD_DIR}/reports" ] || ln -sfn "${OUTPUT_DIR}/reports" "${DASHBOARD_DIR}/reports"

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
  render_email() {
    jq -r --arg format "$1" --arg slot "${SLOT}" \
      --slurpfile policy "${AGENT_DIR}/dashboard/view-policy.json" \
      -f "${AGENT_DIR}/email.jq" "${OUTPUT_DIR}/briefing.json"
  }
  EMAIL_BODY=$(render_email plain 2>>"${LOG_FILE}") || EMAIL_BODY=""
  EMAIL_HTML=$(render_email html 2>>"${LOG_FILE}") || EMAIL_HTML=""

  if [ -n "${EMAIL_BODY}" ]; then
    NEEDS_COUNT=$(jq -r '[((.sections.today.items // []) | length), 5] | min' "${OUTPUT_DIR}/briefing.json" 2>/dev/null || echo 0)
    ALERT_COUNT=$(jq -r '(.alerts // []) | length' "${OUTPUT_DIR}/briefing.json" 2>/dev/null || echo 0)
    SUBJECT="${SLOT} Briefing $(date +%Y-%m-%d)"
    if [ "${NEEDS_COUNT}" -gt 0 ] 2>/dev/null; then
      SUBJECT="${SUBJECT} — ${NEEDS_COUNT} need you"
    elif [ "${ALERT_COUNT}" -gt 0 ] 2>/dev/null; then
      SUBJECT="${SUBJECT} — ${ALERT_COUNT} to watch"
    fi
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

}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
