#!/usr/bin/env bash
# Shared human-facing output. Source this file; it performs no network probes.
# Kept beside the nine consumers: quicknet cannot own their presentation policy.

report_init() {
  local title=$1 purpose=$2 effect=$3 usage=$4 arg
  shift 4
  REPORT_DETAILS=0
  REPORT_ARGS=()
  REPORT_CURRENT='startup'
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
