#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=network-report.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/network-report.sh"
report_init 'WiFi radio survey and capture' 'Observe access points, WPS advertisements and packet samples; optionally collect IDS logs.' \
  'Enables monitor mode and interrupts this computer WiFi; cleanup attempts to restore networking.' '[-i IFACE] [--channel CH] [--band all|5] [--ids none|suricata|zeek|both] [--details]' "$@" || exit 0
set -- "${REPORT_ARGS[@]}"


# Safe-by-default Wi-Fi survey:
# - Monitor mode ON → wash survey/scan → airodump survey (CSV+PCAP)
# - Optional IDS (Suricata/Zeek)
# - No deauth. (You can do that separately once you’ve identified your AP.)
#
# Usage examples:
#   sudo ./wifi_survey.sh                          # autodetect iface, all bands
#   sudo ./wifi_survey.sh -i wlp9s0f0              # explicit iface
#   sudo ./wifi_survey.sh --channel 149            # focus on ch 149 for WPS
#   sudo ./wifi_survey.sh --ids suricata           # run Suricata in parallel
#   sudo ./wifi_survey.sh --ids both               # Suricata+Zeek
#
# Notes:
# - This script temporarily stops wpa_supplicant/NetworkManager while in monitor mode.
# - It cleans up and restores your Wi-Fi on exit.

# ---------- args ----------
IFACE=""
FOCUS_CHANNEL=""
IDS_MODE="none"     # none|suricata|zeek|both
BAND="all"          # all|5   (affects wash scans only)

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--iface) IFACE="${2:-}"; shift 2;;
    --channel)  FOCUS_CHANNEL="${2:-}"; shift 2;;
    --ids)      IDS_MODE="${2:-}"; shift 2;;
    --band)     BAND="${2:-}"; shift 2;;   # all|5
    -h|--help)
      sed -n '1,80p' "$0" | sed -n '1,80p'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

ts() { date +"%Y%m%d_%H%M%S"; }
TSTAMP="$(ts)"
OUTDIR="$(pwd)/wifi_report_${TSTAMP}"
mkdir -p "$OUTDIR"/{wifi,ids}

log()   { printf "%s\n" "$*"; }
run() {
  local rc=0
  if (( REPORT_DETAILS )); then info "Command: $*"; fi
  eval "$@" || rc=$?
  if (( rc == 124 )); then info "Capture time window ended; inspect the saved sample."; return 0; fi
  if (( rc != 0 )); then warn "This stage failed (exit $rc); its result is incomplete."; fi
  return "$rc"
}

report_section "Preparation" "Find the WiFi adapter and capture tools." "Monitor mode listens to radio frames; the normal WiFi connection will pause." "Use Ctrl-C to stop; cleanup then attempts to restore networking."
# ---------- preflight ----------
# Create reaver state dir once (wash needs it)
if [[ ! -d /var/db/reaver-wps-1.4 ]]; then
  run "sudo install -d -m 0755 /var/db/reaver-wps-1.4"
fi

# Find wireless iface if not specified
if [[ -z "$IFACE" ]]; then
  IFACE="$(iw dev | awk '/Interface/{print $2; exit}')"
fi
[[ -n "$IFACE" ]] || { warn "No wireless interface found."; exit 1; }
ok "Wireless iface: $IFACE"

# ---------- cleanup trap ----------
MON_IF=""
PIDS=()   # IDS PIDs

cleanup() {
  set +e
  if [[ -n "$MON_IF" ]]; then
    run "sudo airmon-ng stop $MON_IF"
  fi
  # Kill IDS if running
  if [[ ${#PIDS[@]} -gt 0 ]]; then
    run "sudo kill ${PIDS[*]} >/dev/null 2>&1 || true"
  fi
  run "sudo systemctl restart NetworkManager wpa_supplicant"
}
trap cleanup EXIT

report_section "1. Enable radio monitoring" "Stop conflicting WiFi services and enable monitor mode." "This computer may lose network access during the survey."
# ---------- enter monitor mode ----------
run "sudo airmon-ng check kill"
run "sudo airmon-ng start $IFACE"

# Detect the monitor interface name robustly
if ip link show "${IFACE}mon" >/dev/null 2>&1; then
  MON_IF="${IFACE}mon"
else
  MON_IF="$(iw dev | awk 'name && $1=="type" && $2=="monitor"{print name} {if($1=="Interface") name=$2}')"
fi

[[ -n "$MON_IF" ]] || { warn "Could not determine monitor interface"; exit 1; }
ok "Monitor iface: $MON_IF"

# ---------- optional IDS ----------
case "$IDS_MODE" in
  suricata)
    run "sudo suricata -i $MON_IF -l \"$OUTDIR/ids/suricata\" &"
    PIDS+=($!)
    ;;
  zeek)
    run "mkdir -p \"$OUTDIR/ids/zeek\" && (cd \"$OUTDIR/ids/zeek\" && sudo zeek -i $MON_IF &) "
    PIDS+=($!)
    ;;
  both)
    run "sudo suricata -i $MON_IF -l \"$OUTDIR/ids/suricata\" &"; PIDS+=($!)
    run "mkdir -p \"$OUTDIR/ids/zeek\" && (cd \"$OUTDIR/ids/zeek\" && sudo zeek -i $MON_IF &) "
    PIDS+=($!)
    ;;
  none) : ;;
  *) warn "Unknown IDS mode '$IDS_MODE' (use: none|suricata|zeek|both)";;
esac

report_section "2. WPS advertisements" "Observe WPS announcements, then send discovery probes for 30 seconds per pass." "Enabled WPS is a router setting to review. This survey does not recover a PIN or password."
# ---------- WPS survey/scan ----------
# Survey (passive)
WASH_BAND_FLAG=""
[[ "$BAND" == "5" ]] && WASH_BAND_FLAG="-5"

run "sudo timeout 30 wash -i $MON_IF -u $WASH_BAND_FLAG | tee \"$OUTDIR/wifi/wps_survey.txt\""

# Scan (active probes)
if [[ -n "$FOCUS_CHANNEL" ]]; then
  run "sudo timeout 30 wash -i $MON_IF -s -c $FOCUS_CHANNEL $WASH_BAND_FLAG | tee \"$OUTDIR/wifi/wps_scan_ch${FOCUS_CHANNEL}.txt\""
else
  run "sudo timeout 30 wash -i $MON_IF -s $WASH_BAND_FLAG | tee \"$OUTDIR/wifi/wps_scan.txt\""
fi

report_section "3. Access points and encryption" "Capture announcements for 25 seconds and save CSV/packet data." "OPN is open WiFi; WEP is obsolete; WPA2/WPA3 identify advertised security, not password strength."
# ---------- WPA inventory (passive), CSV+PCAP ----------
run "sudo timeout 25 airodump-ng $MON_IF --band abg --output-format csv,pcap --write \"$OUTDIR/wifi/wifi_survey\""

report_section "4. Packet sample" "Capture up to 40 frames within eight seconds." "A nonempty packet file shows observed traffic, not a security pass or a successful handshake."
# ---------- monitor sanity capture ----------
run "sudo timeout 8 tcpdump -I -i $MON_IF -c 40 -w \"$OUTDIR/wifi/monitor_sample.pcap\""

# ---------- quick summary ----------
SUMMARY="$OUTDIR/SUMMARY.txt"
{
  echo "Wi-Fi Survey Summary — $TSTAMP"
  echo "Interface: $IFACE   Monitor: $MON_IF"
  echo "Output dir: $OUTDIR"
  echo

  # Airodump CSV present?
  CSV="$(ls -1 $OUTDIR/wifi/wifi_survey-*.csv 2>/dev/null | head -1 || true)"
  if [[ -n "${CSV:-}" ]]; then
    echo "AP counts by encryption (from airodump CSV):"
    # CSV fields: BSSID, First time seen, Last time seen, channel, speed, privacy, cipher, auth, power, beacons, IV, LAN IP, ID-length, ESSID, Key
    awk -F, 'NR>1 && $1 ~ /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {gsub(/ /,"",$6); enc=$6; enc=(enc==""?"UNK":enc); cnt[enc]++} END{for(k in cnt) printf "  %-8s %d\n", k, cnt[k]}' "$CSV" | sort
    echo
    echo "AP counts by channel:"
    awk -F, 'NR>1 && $1 ~ /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {ch=$4; gsub(/ /,"",ch); if(ch~/^[0-9]+$/) cnt[ch]++} END{for(k in cnt) printf "  ch%-3s %d\n", k, cnt[k]}' "$CSV" | sort -n -k1.3
    echo
  else
    echo "No airodump CSV found to summarize."
    echo
  fi

  echo "Files of interest:"
  ls -1 "$OUTDIR"/wifi | sed 's/^/  wifi\//'
  if [[ -d "$OUTDIR/ids/suricata" ]]; then
    echo "  ids/suricata/eve.json"
  fi
  if [[ -d "$OUTDIR/ids/zeek" ]]; then
    echo "  ids/zeek/* (conn.log,dns.log,ssl.log,...)"
  fi
  echo

  echo "Interpretation:"
  echo "  - wash_* : Look for columns \"WPS\" and \"Lck\" → Disable WPS if WPS=Yes and Lck=No on your AP."
  echo "  - wifi_survey-01.csv : \"privacy/cipher/auth\" show OPN/WEP/WPA2/WPA3 and modes (CCMP/SAE)."
  echo "  - Channel counts : compare nearby channels; counts do not measure airtime or prove congestion."
  echo "  - monitor_sample.pcap : inspect in Wireshark to confirm usable frames were captured."
  if [[ "$IDS_MODE" != "none" ]]; then
    echo "  - Suricata/Zeek logs : see flows/alerts during the scan."
  fi

  echo
  echo "Recommendations:"
  echo "  • If WPS enabled: disable it on the router."
  echo "  • Prefer WPA3-SAE (or WPA2-CCMP if WPA3 not available); never use WEP."
  echo "  • Pick a less congested channel (from the channel summary)."
  echo "  • For handshake verification on YOUR AP:"
  echo "      aircrack-ng $OUTDIR/wifi/wifi_survey-01.cap"
} > "$SUMMARY"

report_heading "WiFi survey summary"
cat "$SUMMARY" | report_evidence
info "Full summary: $SUMMARY"
info "Next: inspect your access point security and channels in the summary; cleanup runs when this script exits."
