#!/usr/bin/env bash
# Shared human-facing output. Source this file; it performs no network probes.
# Kept beside the nine consumers: quicknet cannot own their presentation policy.

report_init() {
  local title=$1 purpose=$2 effect=$3 usage=$4 arg
  shift 4
  REPORT_DETAILS=0
  REPORT_ARGS=()
  REPORT_CURRENT='startup'
  REPORT_TLDR_SHOWN=0
  REPORT_CONTEXT=''
  REPORT_TLDR_FILE=''
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
  # ANSI roles inherit the terminal's configured HWC palette.
  if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    BLUE=$'\033[34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
  fi
  for arg in "$@"; do
    case "$arg" in
      --details) REPORT_DETAILS=1 ;;
      -h|--help)
        printf '%s\nPurpose: %s\nEffect: %s\n\nUsage: bash %s %s\n' \
          "$title" "$purpose" "$effect" "${BASH_SOURCE[1]##*/}" "$usage"
        printf '%s\n' '  --details   Show full evidence instead of short excerpts.' \
          '  --help      Explain the tool without running checks.'
        return 2
        ;;
      *) REPORT_ARGS+=("$arg") ;;
    esac
  done
  printf '\n%s%s%s\nPurpose: %s\nEffect: %s\n' "$BOLD" "$title" "$NC" "$purpose" "$effect"
  printf '%s\n' 'Results describe these probes only. A skipped or failed probe is not proof of an outage.'
  set -E
  trap 'report_stopped "$?" "$LINENO"' ERR
  trap 'report_exit "$?"' EXIT
}

report_heading() { REPORT_CURRENT=$*; printf '\n%s%s%s\n' "$BOLD" "$*" "$NC"; }
report_section() {
  report_heading "$1"
  printf '  Checking: %s\n  Meaning:  %s\n' "$2" "$3"
  [[ -z ${4:-} ]] || printf '  Next:     %s\n' "$4"
  return 0
}
report_result() {
  local color=$NC
  case "$1" in PASS) color=$GREEN;; CHECK|UNKNOWN|SKIP) color=$YELLOW;; FAIL) color=$RED;; esac
  printf '  %s[%s]%s %s\n' "$color" "$1" "$NC" "$2"
}
ok(){ report_result PASS "$*"; }
success(){ ok "$@"; }
warn(){ report_result CHECK "$*"; }
fail(){ report_result FAIL "$*"; }
error(){ fail "$@"; }
info(){ printf '  %s\n' "$*"; }
explain(){ printf '  Meaning: %s\n' "$*"; }
hdr(){ report_heading "$@"; }
bold(){ report_heading "$@"; }
section(){ report_heading "$@"; }

# Consume the entire stream so truncation cannot cause SIGPIPE in a probe.
# This is presentation only: never feed these excerpts into result parsers.
report_evidence() {
  awk -v full="$REPORT_DETAILS" '
    { if (full || NR <= 16) print "    " $0 }
    END { if (!full && NR > 16) printf "    ... %d more lines; use --details for full evidence.\n", NR-16 }
  '
}
report_stopped() {
  local rc=$1 line=$2
  printf '\n[FAIL] Check stopped in: %s (exit %s, line %s).\n' "$REPORT_CURRENT" "$rc" "$line" >&2
  printf 'Meaning: This run is incomplete; it does not establish that the network is broken.\n' >&2
  printf 'Next: Review the error above. Rerun with --details and check required tools with net-tools toolscan.\n' >&2
}

# Presentation is shared; each script owns its findings. No new probes here.
report_tldr() {
  REPORT_TLDR_SHOWN=1
  REPORT_CURRENT=TLDR
  report_tldr_text "$@"
  if [[ -n ${REPORT_TLDR_FILE:-} ]]; then
    # Saved text stays plain even when the terminal uses colors.
    (RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''; report_tldr_text "$@") >> "$REPORT_TLDR_FILE"
  fi
}
report_tldr_text() {
  printf '\n%sTLDR%s\n' "$BOLD" "$NC"
  report_result "$1" "$2"
  printf '  Because: %s\n  Next:    %s\n  Limits:  %s\n' "$3" "$4" "$5"
}
report_exit() {
  local rc=$1
  if (( REPORT_TLDR_SHOWN == 0 )); then
    report_tldr UNKNOWN 'The run ended before a full conclusion.' \
      "Last section: $REPORT_CURRENT; exit code: $rc. ${REPORT_CONTEXT:-}" \
      'Read the last error above. Check prerequisites with net-tools toolscan; rerun the selected tool with --details.' \
      'Unfinished checks are untested; this is not proof of a network outage.'
  fi
}

# Router/public/system-DNS states: yes, no, unknown. Browser check additionally
# accepts unexpected/skipped; no response is never called a confirmed portal.
report_connection_tldr() {
  local router=$1 public=$2 dns=$3 alternate=$4 browser=$5 next_tool=$6 matrix_missing=${7:-0}
  local basis="Router reply: $router; public reply: $public; system DNS answer: $dns; browser check: $browser."
  local limits='These are short samples, not a speed test or security audit. Untested sites, IPv6 and intermittent faults remain unchecked.'
  if [[ $browser == unexpected ]]; then
    report_tldr CHECK 'Browser access needs attention.' "$basis" \
      'Open a plain HTTP page in your browser and inspect any login redirect. If none appears, compare another device and your VPN/proxy settings.' "$limits"
  elif [[ $public == yes && $dns == no ]]; then
    if [[ $alternate == yes ]]; then
      report_tldr CHECK 'Configured DNS needs attention; public DNS answered.' "$basis" \
        'Inspect resolvectl status and the active connection DNS settings. Compare the DNS table before changing a resolver.' "$limits"
    else
      report_tldr CHECK 'DNS needs attention; public services answered.' "$basis" \
        "Compare configured and public DNS with $next_tool. Check browser login requirements before changing DNS." "$limits"
    fi
  elif [[ $public != yes ]]; then
    if [[ $router != yes ]]; then
      report_tldr UNKNOWN 'Router and public access are unconfirmed.' "$basis" \
        'Check the active adapter, WiFi association and address. Compare another device on the same network before restarting networking.' "$limits"
    else
      report_tldr UNKNOWN 'Public access is unconfirmed; the router answered.' "$basis" \
        'Compare another device on this WiFi. Inspect browser login and VPN settings; if both devices fail, check the router WAN status.' "$limits"
    fi
  elif [[ $dns != yes ]]; then
    report_tldr UNKNOWN 'Public services answered; DNS remains untested.' "$basis" \
      "Check dig availability with net-tools toolscan, then rerun $next_tool." "$limits"
  elif [[ $router != yes ]]; then
    report_tldr CHECK 'Public access and DNS passed; router probes are inconclusive.' "$basis" \
      'If an app still fails, test that app or site. Do not reset the router solely because it ignores diagnostic probes.' "$limits"
  elif (( matrix_missing > 0 )); then
    report_tldr CHECK 'Basic probes passed; some DNS comparison lookups returned no address.' \
      "$basis DNS matrix lookups without answers: $matrix_missing." \
      'Review the DNS table for the affected resolver and name. Repeat that lookup before changing settings; system DNS did answer.' "$limits"
  else
    report_tldr PASS 'Basic connection probes passed; no fault appeared in those checks.' "$basis" \
      'No connection setting change is indicated. If a problem persists, test the affected app/site or run net-tools homewifi-audit for signal checks. Rerun during a dropout.' "$limits"
  fi
}

# A successful dig exit can still carry NXDOMAIN or an empty answer.
report_dns_answer() {
  local answer
  answer=$(timeout 3 dig +time=1 +tries=1 +short "$@" A 2>/dev/null) || return 1
  awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {found=1} END {exit !found}' <<< "$answer"
}

report_port_legend() {
  explain 'open = a service answered; closed = the host refused it; filtered = no clear answer. An open port is not a confirmed vulnerability.'
}
report_path_legend() {
  explain 'Compare loss at the destination. Loss at one earlier hop alone may be limited diagnostic replies. Three probes are too few to measure reliability.'
}
