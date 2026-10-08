#!/usr/bin/env bash
# Reports belong to the invoking user; redirects intentionally run outside sudo.
# shellcheck disable=SC2024
set -Eeuo pipefail

# shellcheck source=network-report.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/network-report.sh"
report_init 'Household security audit' 'Discover devices, inspect service ports and optionally run vulnerability, credential and WiFi tests.' \
  'Intrusive options remain interactive; credential tests can lock accounts and deauth can disconnect clients.' '[audit|discover] [--details]' "$@" || exit 0
set -- "${REPORT_ARGS[@]}"



# ===== Owner-only intrusive LAN + Wi-Fi audit (interactive toggles) =====
# Tools used (install what you need):
#  - nmap, ip, awk, python3, rg, sudo, coreutils
#  - arp-scan (optional)
#  - dig (optional)
#  - aircrack-ng suite: airmon-ng, airodump-ng, aireplay-ng (Wi-Fi)
#  - reaver (wash) for WPS *discovery* (no attack)
#  - suricata, zeek (optional, to run in parallel)
#
# Usage: bash wifibrute.sh [audit|discover]
# Output: private ./reports/<timestamp>.<unique>/; user-managed, replaceable.
# Scans are non-retriable here; partial results are retained for inspection.

have(){ command -v "$1" >/dev/null 2>&1; }

# One command vocabulary; discovery never runs the audit stages.
MODE=${1:-audit}
case "$MODE" in
  audit|discover) [[ $# -le 1 ]] || { fail "Expected one command"; exit 2; } ;;
  -h|--help) echo "Usage: bash $0 [audit|discover]"; exit 0 ;;
  *) fail "Unknown command: $MODE (use audit or discover)"; exit 2 ;;
esac

# Parse once at the input boundary; return canonical CIDR and local/routed scope.
parse_target(){
  python3 - "$1" "$2" <<'PY'
import ipaddress, sys
try:
    target = ipaddress.IPv4Network(sys.argv[1], strict=False)
    local = ipaddress.IPv4Network(sys.argv[2], strict=False)
    if target.num_addresses > 4096:
        raise ValueError('Range exceeds 4096 addresses; choose a /20 or smaller range')
    print(target, 'local' if target.subnet_of(local) else 'routed')
except ValueError as error:
    print(error, file=sys.stderr)
    sys.exit(2)
PY
}

# ---------- Preflight ----------
for t in ip nmap awk python3 rg sudo timeout mktemp tee sort tr wc id chown; do have "$t" || { fail "Missing '$t'"; exit 2; }; done
have arp-scan || warn "arp-scan not found (will fall back to nmap -sn for discovery)"
have dig || true

# Wi-Fi tooling (optional)
HAVE_AIRMON=0; have airmon-ng && HAVE_AIRMON=1
HAVE_AIRODUMP=0; have airodump-ng && HAVE_AIRODUMP=1
HAVE_AIREPLAY=0; have aireplay-ng && HAVE_AIREPLAY=1
HAVE_WASH=0; have wash && HAVE_WASH=1

# IDS tooling (optional)
HAVE_SURICATA=0; have suricata && HAVE_SURICATA=1
HAVE_ZEEK=0; have zeek && HAVE_ZEEK=1

# ---------- Discover interface / subnet ----------
DEF="$(ip -4 route show default | awk 'NR==1{print}')"
IFACE="$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$DEF")"
[[ -n "$IFACE" ]] || { fail "No IPv4 default route"; exit 1; }
CIDR_SELF="$(ip -4 -o addr show dev "$IFACE" scope global | awk 'NR==1{print $4}')"
[[ -z "${IFACE:-}" || -z "${CIDR_SELF:-}" ]] && { fail "No default route or IPv4 address"; exit 1; }
IP_SELF="${CIDR_SELF%%/*}"
DEFAULT_SUBNET="$(python3 - "$CIDR_SELF" <<'PY'
import ipaddress, sys
print(ipaddress.IPv4Interface(sys.argv[1]).network)
PY
)"

# ---------- Interactive menu ----------
INTRUSIVE=0        # nmap intrusive/vuln NSE
BRUTE=0            # nmap brute/auth NSE
DO_UDP=1           # scan top UDP ports
CUSTOM_SUBNET="$DEFAULT_SUBNET"
RUN_SURI=0         # run Suricata in parallel
RUN_ZEEK=0         # run Zeek in parallel
DO_WIFI=0          # enable Wi-Fi features
WIFI_WPA_SCAN=0    # airodump scan + optional handshake capture
WIFI_WPS_DISC=0    # wash WPS discovery (no attack)
WIFI_DEAUTH=0      # aireplay deauth to trigger handshake (DANGEROUS)
MON_IF=""          # monitor interface if created
MON_START_ATTEMPTED=0
DUMP_PID=""
IDS_NAMES=()
IDS_PIDS=()

echo
report_section "Choose the checks" "Select the target network and optional tests." "UDP finds different services; vulnerability scripts probe known weaknesses; credential scripts try logins." "Leave an option off to skip it. Full raw results are saved under reports/."
echo "Detected IFACE: $IFACE   My IP: $IP_SELF   Default target: $DEFAULT_SUBNET"
read -r -p "Target IPv4 subnet [$DEFAULT_SUBNET]: " ans || { fail "Input closed; cancelled"; exit 2; }
TARGET_INFO=$(parse_target "${ans:-$DEFAULT_SUBNET}" "$CIDR_SELF") || { fail "Invalid target"; exit 2; }
read -r CUSTOM_SUBNET TARGET_SCOPE <<<"$TARGET_INFO"

if [[ "$MODE" == audit ]]; then

read -r -p "Scan top UDP ports too? (y/N): " ans || true
[[ "$ans" =~ ^[Yy]$ ]] && DO_UDP=1 || DO_UDP=0

read -r -p "Enable intrusive/vuln NSE scripts? (N/y): " ans || true
[[ "$ans" =~ ^[Yy]$ ]] && INTRUSIVE=1 || INTRUSIVE=0

read -r -p "Enable brute/auth NSE scripts? (N/y)  [tries default creds/passwords]: " ans || true
[[ "$ans" =~ ^[Yy]$ ]] && BRUTE=1 || BRUTE=0

if (( HAVE_SURICATA==1 || HAVE_ZEEK==1 )); then
  read -r -p "Run IDS in parallel (Suricata/Zeek) while scanning? (y/N): " ans || true
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    if (( HAVE_SURICATA==1 )); then
      read -r -p "  • Suricata? (y/N): " a || true
      [[ "$a" =~ ^[Yy]$ ]] && RUN_SURI=1
    fi
    if (( HAVE_ZEEK==1 )); then
      read -r -p "  • Zeek? (y/N): " a || true
      [[ "$a" =~ ^[Yy]$ ]] && RUN_ZEEK=1
    fi
  fi
fi
if (( HAVE_AIRMON==1 )); then
  read -r -p "Enable Wi-Fi tests (requires aircrack-ng)? (y/N): " ans || true
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    DO_WIFI=1
    read -r -p "  • WPA scan/handshake capture (non-deauth)? (y/N): " a || true
    [[ "$a" =~ ^[Yy]$ ]] && WIFI_WPA_SCAN=1
    if (( HAVE_WASH==1 )); then
      read -r -p "  • WPS discovery (wash) [no attack]? (y/N): " a || true
      [[ "$a" =~ ^[Yy]$ ]] && WIFI_WPS_DISC=1
    fi
    if (( HAVE_AIREPLAY==1 )); then
      echo "  ⚠ Deauth forces clients to reconnect (disruptive). Only on YOUR network."
      read -r -p "  • Use deauth to trigger handshake capture? (N/y): " a || true
      [[ "$a" =~ ^[Yy]$ ]] && WIFI_DEAUTH=1
    fi
  fi
fi
fi # audit setup

# ---------- Output directory ----------
TS="$(date +'%Y%m%d-%H%M%S')"
umask 077
mkdir -p reports
# Atomic reservation prevents simultaneous runs from sharing reports or PIDs.
OUTDIR=$(mktemp -d "reports/$TS.XXXXXX")
OUTDIR="$(cd "$OUTDIR" && pwd)"
REPORT_OWNER="$(id -u):$(id -g)"
FAILURES=0
STAGES="$OUTDIR/stages.tsv"
printf '# format-version: 1\nstage\tstatus\texit_code\n' > "$STAGES"
ok "Reports will be saved to: $OUTDIR"
echo

# ---------- Helper to clean up monitor mode / IDS ----------
stop_job(){
  local name=$1 pid=$2 rc=0 status=stopped
  if kill -0 "$pid" 2>/dev/null; then
    sudo -n kill "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then sudo -n kill -KILL "$pid" 2>/dev/null || true; fi
  else
    status=ended
  fi
  wait "$pid" 2>/dev/null || rc=$?
  if [[ "$status" == ended ]] && (( rc != 0 )); then
    FAILURES=$((FAILURES + 1))
    status=failed
    warn "$name exited (code $rc); inspect $OUTDIR/$name.log"
  fi
  printf '%s\t%s\t%s\n' "$name" "$status" "$rc" >> "$STAGES"
}

release_resources(){
  # A signal can arrive during setup, before MON_IF has been assigned.
  if (( MON_START_ATTEMPTED==1 )) && [[ -z "$MON_IF" ]]; then
    local candidate
    for candidate in "${IFACE}mon" "$IFACE"; do
      if iw dev "$candidate" info 2>/dev/null | rg -q 'type monitor'; then MON_IF=$candidate; break; fi
    done
  fi
  if [[ -n "${MON_IF:-}" ]]; then
    hdr "Cleanup: stopping monitor mode ($MON_IF)"
    if ! sudo -n timeout -k 2s 10s airmon-ng stop "$MON_IF" >> "$OUTDIR/airmon.log" 2>&1; then
      FAILURES=$((FAILURES + 1))
      warn "Could not stop monitor mode; inspect $OUTDIR/airmon.log"
    fi
    MON_IF=""
  fi
  MON_START_ATTEMPTED=0
  local i
  for i in "${!IDS_PIDS[@]}"; do stop_job "${IDS_NAMES[$i]}" "${IDS_PIDS[$i]}"; done
  IDS_PIDS=()
  IDS_NAMES=()
  if [[ -n "$DUMP_PID" ]]; then stop_job handshake "$DUMP_PID"; DUMP_PID=""; fi
  # Radio captures and IDS logs are also written by privileged tools. Restore
  # ownership only inside this run's atomically reserved directory, no symlinks.
  if ! sudo -n chown -hR -- "$REPORT_OWNER" "$OUTDIR"; then
    FAILURES=$((FAILURES + 1))
    warn "Could not restore report ownership; inspect $OUTDIR as root"
  fi
}
cleanup(){
  local rc=$?
  trap - EXIT
  release_resources
  if (( rc == 0 && FAILURES > 0 )); then rc=1; fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sudo -v || { fail "Administrator access failed"; exit 2; }

# Nmap exit zero does not imply a complete scan: host deadlines can skip targets.
# Each stage has a wall deadline; at the limit TERM then KILL, retain logs, no retry.
scan_complete(){
  python3 - "$1" <<'PY'
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
    finished = root.find('runstats/finished')
    complete = (finished is not None and finished.get('exit') == 'success'
                and not any(host.get('timedout') == 'true' for host in root.findall('host')))
except (OSError, ET.ParseError):
    complete = False
sys.exit(0 if complete else 1)
PY
}

scan(){
  local name=$1 deadline=$2 rc=0 status=ok
  shift 2
  # Reserve output files as the report owner before privileged Nmap opens them.
  # Otherwise umask 077 produces root-owned files the parser cannot read.
  local format
  for format in nmap gnmap xml; do : > "$OUTDIR/$name.$format"; done
  sudo -n timeout -k 5s "$deadline" nmap "$@" -oA "$OUTDIR/$name" 2>&1 | tee "$OUTDIR/$name.log" | report_evidence || rc=$?
  if (( rc != 0 )); then
    status=failed
  elif ! scan_complete "$OUTDIR/$name.xml"; then
    status=incomplete
  fi
  printf '%s\t%s\t%s\n' "$name" "$status" "$rc" >> "$STAGES"
  if [[ "$status" != ok ]]; then
    FAILURES=$((FAILURES + 1))
    warn "$name $status (exit $rc); inspect $OUTDIR/$name.log and $STAGES"
    return 1
  fi
}

# ---------- Launch IDS (optional) ----------
start_suricata(){
  (( HAVE_SURICATA==1 )) || return 0
  hdr "Starting Suricata (IDS) on $IFACE"
  mkdir -p "$OUTDIR/suricata"
  # Run with default rules if present; otherwise start with built-in.
  sudo -n timeout -k 5s 30m suricata -i "$IFACE" -l "$OUTDIR/suricata" > "$OUTDIR/suricata.log" 2>&1 &
  echo $! > "$OUTDIR/suricata.pid"
  IDS_NAMES+=(suricata)
  IDS_PIDS+=("$!")
  ok "Suricata launched (30 minute limit). Inspect $OUTDIR/suricata.log and $OUTDIR/suricata/eve.json"
}

start_zeek(){
  (( HAVE_ZEEK==1 )) || return 0
  hdr "Starting Zeek (network telemetry) on $IFACE"
  mkdir -p "$OUTDIR/zeek"
  ( cd "$OUTDIR/zeek" && exec sudo -n timeout -k 5s 30m zeek -i "$IFACE" ) > "$OUTDIR/zeek.log" 2>&1 &
  echo $! > "$OUTDIR/zeek.pid"
  IDS_NAMES+=(zeek)
  IDS_PIDS+=("$!")
  ok "Zeek launched (30 minute limit). Inspect $OUTDIR/zeek.log and $OUTDIR/zeek/"
}

if (( RUN_SURI==1 )); then start_suricata; fi
if (( RUN_ZEEK==1 )); then start_zeek; fi

# ---------- Stage 0: Host discovery ----------
report_section "1. Discover target devices" "Send host discovery probes to $CUSTOM_SUBNET." "A discovered host answered these probes. No hosts can mean filtering, isolation, a wrong range or a failed scan." "Check the selected adapter and subnet if no hosts appear."
LIVE_LIST="$OUTDIR/live-hosts.txt"
if [[ "$TARGET_SCOPE" == local ]] && have arp-scan; then
  if sudo -n timeout -k 5s 60s arp-scan --interface "$IFACE" "$CUSTOM_SUBNET" > "$OUTDIR/arp-scan.txt" 2> "$OUTDIR/arp-scan.log"; then
    awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/ {print $1}' "$OUTDIR/arp-scan.txt" | sort -u > "$LIVE_LIST"
  else
    warn "ARP discovery failed; trying Nmap. Inspect $OUTDIR/arp-scan.log"
  fi
fi
if [[ ! -s "$LIVE_LIST" ]]; then
  scan pingscan 120s -sn -n -T3 --max-retries 2 --host-timeout 15s "$CUSTOM_SUBNET" || { fail "Discovery failed; inspect $STAGES"; exit 1; }
  [[ -f "$OUTDIR/pingscan.gnmap" ]] || { fail "Discovery result missing"; exit 1; }
  awk '/^Host: / && /Status: Up/{print $2}' "$OUTDIR/pingscan.gnmap" | sort -u > "$LIVE_LIST"
fi
if [[ ! -s "$LIVE_LIST" ]]; then fail "No live hosts found; inspect $OUTDIR/pingscan.nmap and check the target or client isolation"; exit 1; fi
COUNT=$(wc -l < "$LIVE_LIST" | tr -d ' ')
ok "Discovered $COUNT host(s) → $LIVE_LIST"
if [[ "$MODE" == discover ]]; then exit 0; fi

# ---------- Stage 1: Full TCP sweep (-p-) ----------
report_section "2. TCP service ports" "Probe all TCP ports on the discovered targets." "Open ports show exposed services, not confirmed flaws. Host and stage deadlines can leave the scan incomplete."
NMAP_BASE=(-Pn -n --max-retries 2 --host-timeout 5m --script-timeout 60s -T3)
scan tcp-all 20m "${NMAP_BASE[@]}" -sS -p- -iL "$LIVE_LIST" || true

# ---------- Stage 2: Service/OS fingerprint ----------
report_section "3. Service and OS identification" "Ask services for version hints and estimate device operating systems." "Fingerprints can be wrong or missing. Confirm device identity in its own settings before acting."
scan tcp-svcos 20m "${NMAP_BASE[@]}" -sS -sV -O --reason --version-all -iL "$LIVE_LIST" || true

# ---------- Stage 3: Top UDP ports (optional) ----------
if (( DO_UDP==1 )); then
  report_section "4. UDP services" "Probe the 50 most common UDP ports." "open|filtered means no clear answer; UDP often stays silent. It is not proof a service is open."
  scan udp-top50 20m "${NMAP_BASE[@]}" -sU --top-ports 50 -iL "$LIVE_LIST" || true
fi

# ---------- Stage 4: Protocol-focused NSE (safe/discovery) ----------
report_section "5. Service discovery scripts" "Run discovery scripts and HTTP, TLS, SMB and SNMP checks." "These can reveal titles, certificates and shares. Discovery categories can still send active requests." "Review unexpected services, anonymous shares and outdated device firmware."
SAFE_SCRIPTS="(default or safe or discovery) and not (intrusive or brute or auth or dos or exploit or external or broadcast or fuzzer)"
scan nse-safe 20m "${NMAP_BASE[@]}" -sS -sV --script "$SAFE_SCRIPTS" -iL "$LIVE_LIST" || true

report_section "Web services and encryption" "Inspect HTTP headers, methods and TLS ciphers." "Weak-cipher hints need confirmation in nse-http.nmap. Credential probes run only when selected."
# HTTP/HTTPS detail
HTTP_SCRIPTS="http-title,http-headers,http-methods,http-server-header,ssl-cert,ssl-enum-ciphers"
(( INTRUSIVE==1 )) && HTTP_SCRIPTS+=",http-enum"
(( BRUTE==1 )) && HTTP_SCRIPTS+=",http-auth,http-default-accounts"
scan nse-http 20m "${NMAP_BASE[@]}" -p 80,8080,8000,443,8443,8888 \
  --script "$HTTP_SCRIPTS" -iL "$LIVE_LIST" || true

report_section "File sharing (SMB)" "Inspect sharing capabilities; share enumeration follows the intrusive option." "A visible share is not necessarily readable without login. Review access on the target device."
# SMB
SMB_SCRIPTS="smb-os-discovery,smb2-security-mode,smb2-capabilities,smb-protocols,smb2-time"
(( INTRUSIVE==1 )) && SMB_SCRIPTS+=",smb-enum-shares"
scan nse-smb 20m "${NMAP_BASE[@]}" -p 445,139 \
  --script "$SMB_SCRIPTS" \
  -iL "$LIVE_LIST" || true

report_section "Management services (SNMP)" "Probe UDP 161 for management information." "Accessible management data can expose device details; review authentication and scope."
# SNMP
scan nse-snmp 20m "${NMAP_BASE[@]}" -sU -p 161 --script "snmp-info,snmp-interfaces" -iL "$LIVE_LIST" || true

# ---------- Stage 5: Intrusive/vuln/brute (gated) ----------
if (( INTRUSIVE==1 )); then
  report_section "6. Vulnerability probes" "Run the selected intrusive and vulnerability script categories." "A positive script finding is a lead to verify, not proof of exploitation. No finding is not a clean bill of health." "Confirm the affected service, patch level and matching finding in nse-intrusive.nmap."
  INTRUSIVE_SCRIPTS="intrusive or vuln"
  (( BRUTE==0 )) && INTRUSIVE_SCRIPTS="($INTRUSIVE_SCRIPTS) and not (brute or auth)"
  scan nse-intrusive 20m "${NMAP_BASE[@]}" -sS -sV --script "$INTRUSIVE_SCRIPTS" -iL "$LIVE_LIST" || true
fi
if (( BRUTE==1 )); then
  report_section "7. Credential and authentication tests" "Run brute-force and authentication scripts on responding services." "A reported valid credential needs review; failed attempts can lock accounts. An interrupted scan does not prove passwords are strong." "Change confirmed weak/default credentials and inspect target authentication logs."
  scan nse-brute 20m "${NMAP_BASE[@]}" -sS -sV --script "brute,auth" -iL "$LIVE_LIST" || true
fi

if (( INTRUSIVE == 0 )); then report_result SKIP 'Vulnerability script category not selected.'; fi
if (( BRUTE == 0 )); then report_result SKIP 'Credential script category not selected.'; fi
if (( DO_UDP == 0 )); then report_result SKIP 'Top-50 UDP scan not selected; the focused SNMP probe still runs.'; fi
if (( DO_WIFI == 0 )); then report_result SKIP 'WiFi monitor/capture tests not selected.'; fi

# ---------- Stage 7: Wi-Fi (optional) ----------
wifi_start_monitor(){
  (( HAVE_AIRMON==1 )) || { warn "airmon-ng not found"; return 1; }
  have iw || { warn "iw is needed to verify monitor mode"; return 1; }
  if iw dev "$IFACE" info | rg -q 'type monitor'; then
    warn "Interface is already in monitor mode; leaving it unchanged"
    return 1
  fi
  if iw dev "${IFACE}mon" info 2>/dev/null | rg -q 'type monitor'; then
    warn "Monitor interface already exists; leaving it unchanged"
    return 1
  fi
  hdr "Wi-Fi: enabling monitor mode (will temporarily disrupt Wi-Fi on $IFACE)"
  # Do not kill NetworkManager or unrelated supplicants across the machine.
  local rc=0 candidate
  MON_START_ATTEMPTED=1
  sudo -n timeout -k 5s 20s airmon-ng start "$IFACE" > "$OUTDIR/airmon.log" 2>&1 || rc=$?
  for candidate in "${IFACE}mon" "$IFACE"; do
    if iw dev "$candidate" info 2>/dev/null | rg -q 'type monitor'; then
      MON_IF=$candidate
      break
    fi
  done
  if (( rc != 0 )) || [[ -z "$MON_IF" ]]; then
    fail "Failed to enable monitor mode; inspect $OUTDIR/airmon.log"
    return 1
  fi
  ok "Monitor IF: $MON_IF"
}

wifi_scan_wpa(){
  (( WIFI_WPA_SCAN==1 && HAVE_AIRODUMP==1 )) || return 0
  report_section "WiFi access points and handshake capture" "Observe access point announcements and authentication traffic." "A saved capture does not prove a handshake was captured or a password was recovered." "Inspect the capture in Wireshark or aircrack-ng."
  mkdir -p "$OUTDIR/wifi"
  local rc=0
  sudo -n timeout -k 5s 20s airodump-ng "$MON_IF" --band abg --output-format csv,pcap \
    --write "$OUTDIR/wifi/airodump" > "$OUTDIR/wifi/airodump.log" 2>&1 || rc=$?
  # Reaching the capture window is expected; other exits are failures.
  if (( rc != 0 && rc != 124 )); then
    FAILURES=$((FAILURES + 1))
    warn "WPA capture failed (exit $rc); inspect $OUTDIR/wifi/airodump.log"
    return 0
  fi
  ok "Capture window ended. Inspect $OUTDIR/wifi/"
  echo "To target a specific BSSID/channel for handshake capture:"
  echo "  sudo airodump-ng --bssid <BSSID> --channel <CH> -w $OUTDIR/wifi/handshake $MON_IF"
  if (( WIFI_DEAUTH==1 && HAVE_AIREPLAY==1 )); then
    echo
    warn "Deauth is disruptive. Only on YOUR network."
    read -r -p "  Run deauth against a client now? (N/y): " a || true
    if [[ "$a" =~ ^[Yy]$ ]]; then
      read -r -p "   BSSID (AP MAC): " B || true
      read -r -p "   Client MAC (optional; press Enter to broadcast): " C || true
      read -r -p "   Channel (e.g., 6): " CH || true
      read -r -p "   Bursts (e.g., 5): " N || true
      [[ "$B" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ && "$CH" =~ ^[0-9]{1,3}$ && "${N:-5}" =~ ^[1-9][0-9]?$ ]] || { warn "Invalid BSSID, channel or burst count (1–99)"; return 0; }
      [[ -z "$C" || "$C" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || { warn "Invalid client MAC"; return 0; }
      sudo -n timeout -k 5s 30s airodump-ng --bssid "$B" --channel "$CH" -w "$OUTDIR/wifi/handshake" "$MON_IF" > "$OUTDIR/wifi/handshake.log" 2>&1 &
      DUMP_PID=$!
      sleep 2
      if [[ -n "${C:-}" ]]; then
        sudo -n timeout -k 5s 20s aireplay-ng -0 "${N:-5}" -a "$B" -c "$C" "$MON_IF" || { FAILURES=$((FAILURES + 1)); warn "Deauth failed"; }
      else
        sudo -n timeout -k 5s 20s aireplay-ng -0 "${N:-5}" -a "$B" "$MON_IF" || { FAILURES=$((FAILURES + 1)); warn "Deauth failed"; }
      fi
      sleep 5
      stop_job handshake "$DUMP_PID"
      DUMP_PID=""
      ok "Handshake capture attempt done. Check $OUTDIR/wifi/handshake*.pcap"
    fi
  fi
}

wifi_wps_discovery(){
  (( WIFI_WPS_DISC==1 && HAVE_WASH==1 )) || return 0
  report_section "WiFi WPS discovery" "Read WPS advertisements; this stage does not attack a PIN." "WPS enabled is a configuration finding. Locked status does not guarantee security." "Disable unused WPS in your router settings."
  mkdir -p "$OUTDIR/wifi"
  local rc=0
  sudo -n timeout -k 5s 30s wash -i "$MON_IF" -2 -s -g -j > "$OUTDIR/wifi/wps.json" 2> "$OUTDIR/wifi/wps.log" || rc=$?
  if (( rc != 0 && rc != 124 )); then FAILURES=$((FAILURES + 1)); warn "WPS discovery failed (exit $rc); inspect $OUTDIR/wifi/wps.log"; fi
  echo "WPS output: $OUTDIR/wifi/wps.json"
  echo "• If 'WPS Locked' is false and WPS enabled, disable WPS on the AP."
}

if (( DO_WIFI==1 )); then
  if wifi_start_monitor; then
    wifi_scan_wpa
    wifi_wps_discovery
  else
    FAILURES=$((FAILURES + 1))
    warn "Wi-Fi tests skipped because monitor setup failed"
  fi
fi

# ---------- Summary ----------
# Include cleanup and background failures in the result shown to the operator.
release_resources
report_section "Security findings summary" "Collect service and script findings from saved reports." "No matching line means no recorded finding, not a passed security audit. Skipped and failed checks remain untested." "Use the file and line references below to confirm each finding before changing the device."
SUMMARY="$OUTDIR/summary.txt"
{
  echo "Intrusive LAN + Wi-Fi Audit — $TS"
  echo "Targets: $CUSTOM_SUBNET  (hosts: $COUNT)"
  echo "Failed or incomplete stages: $FAILURES"
  cat "$STAGES"
  echo
  echo "Telnet/FTP: cleartext services; review and disable if unused."
  rg -n '23/tcp\s+open|21/tcp\s+open' "$OUTDIR"/*.nmap || true
  echo
  echo "SMB/shares: review access; port 445 alone is not a flaw."
  rg -n '445/tcp\s+open|smb-enum-shares' "$OUTDIR"/*.nmap || true
  echo
  echo "SNMP: review management exposure and authentication."
  rg -n '161/(udp|tcp)\s+open' "$OUTDIR"/*.nmap || true
  echo
  echo "TLS hints: review the matching cipher and protocol in nse-http.nmap."
  rg -n '(RC4|MD5|NULL|EXPORT|LOW)' "$OUTDIR"/nse-http.nmap || true
  echo
  echo "Positive vulnerability leads: verify script details and device firmware."
  rg -n '(^|[^[:alpha:]])VULNERABLE([^[:alpha:]]|$)' "$OUTDIR"/*.nmap | awk '!/NOT VULNERABLE/' || true
  echo
  if [[ -d "$OUTDIR/wifi" ]]; then
    echo "# Wi-Fi artifacts:"
    ls -1 "$OUTDIR/wifi" 2>/dev/null || true
  fi
} > "$SUMMARY"
cat "$SUMMARY" | report_evidence

echo
if (( FAILURES > 0 )); then
  warn "Audit has failed or incomplete stages. Inspect $SUMMARY"
else
  ok "Requested scans finished. Review $SUMMARY; this does not prove the network is secure."
fi
echo "If you started Suricata/Zeek, their logs are under $OUTDIR/suricata and $OUTDIR/zeek."
echo "Monitor and IDS cleanup attempted. Inspect any warnings above."
(( FAILURES == 0 ))
