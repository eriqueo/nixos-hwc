#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=network-report.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/network-report.sh"
report_init 'Household security audit' 'Discover devices, inspect service ports and optionally run vulnerability, credential and WiFi tests.' \
  'Intrusive options remain interactive; credential tests can lock accounts and deauth can disconnect clients.' '[--details]' "$@" || exit 0
set -- "${REPORT_ARGS[@]}"


# ===== Owner-only intrusive LAN + Wi-Fi audit (interactive toggles) =====
# Tools used (install what you need):
#  - nmap, ip, awk, sed, grep
#  - arp-scan (optional)
#  - dig (optional)
#  - aircrack-ng suite: airmon-ng, airodump-ng, aireplay-ng (Wi-Fi)
#  - reaver (wash) for WPS *discovery* (no attack)
#  - suricata, zeek (optional, to run in parallel)
#
# Output saved under ./reports/<timestamp>/

have(){ command -v "$1" >/dev/null 2>&1; }

# ---------- Preflight ----------
for t in ip nmap awk sed grep; do have "$t" || { fail "Missing '$t'"; exit 2; }; done
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
DEF="$(ip route show default | head -n1 || true)"
IFACE="$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$DEF")"
CIDR_SELF="$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | head -1 || true)"
[[ -z "${IFACE:-}" || -z "${CIDR_SELF:-}" ]] && { fail "No default route or IPv4 address"; exit 1; }
IP_SELF="${CIDR_SELF%%/*}"
SUB24_DEFAULT="$(cut -d. -f1-3 <<<"$IP_SELF").0/24"

# ---------- Interactive menu ----------
INTRUSIVE=0        # nmap intrusive/vuln NSE
BRUTE=0            # nmap brute/auth NSE
DO_UDP=1           # scan top UDP ports
CUSTOM_SUBNET="$SUB24_DEFAULT"
RUN_SURI=0         # run Suricata in parallel
RUN_ZEEK=0         # run Zeek in parallel
DO_WIFI=0          # enable Wi-Fi features
WIFI_WPA_SCAN=0    # airodump scan + optional handshake capture
WIFI_WPS_DISC=0    # wash WPS discovery (no attack)
WIFI_DEAUTH=0      # aireplay deauth to trigger handshake (DANGEROUS)
MON_IF=""          # monitor interface if created

echo
report_section "Choose the checks" "Select the target network and optional tests." "UDP finds different services; vulnerability scripts probe known weaknesses; credential scripts try logins." "Leave an option off to skip it. Full raw results are saved under reports/."
echo "Detected IFACE: $IFACE   My IP: $IP_SELF   Default target: $SUB24_DEFAULT"
read -r -p "Target subnet [$SUB24_DEFAULT]: " ans || true
CUSTOM_SUBNET="${ans:-$SUB24_DEFAULT}"

read -r -p "Scan top UDP ports too? (y/N): " ans || true
[[ "$ans" =~ ^[Yy]$ ]] && DO_UDP=1 || DO_UDP=0

read -r -p "Enable intrusive/vuln NSE scripts? (N/y): " ans || true
[[ "$ans" =~ ^[Yy]$ ]] && INTRUSIVE=1 || INTRUSIVE=0

read -r -p "Enable brute/auth NSE scripts? (N/y)  [tries default creds/passwords]: " ans || true
[[ "$ans" =~ ^[Yy]$ ]] && BRUTE=1 || BRUTE=0

if (( HAVE_SURICATA==1 || HAVE_ZEEK==1 )); then
  read -r -p "Run IDS in parallel (Suricata/Zeek) while scanning? (y/N): " ans || true
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    (( HAVE_SURICATA==1 )) && read -r -p "  • Suricata? (y/N): " a && [[ "$a" =~ ^[Yy]$ ]] && RUN_SURI=1
    (( HAVE_ZEEK==1 )) && read -r -p "  • Zeek? (y/N): " a && [[ "$a" =~ ^[Yy]$ ]] && RUN_ZEEK=1
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

# ---------- Output directory ----------
TS="$(date +'%Y%m%d-%H%M%S')"
OUTDIR="reports/$TS"
mkdir -p "$OUTDIR"
ok "Reports will be saved to: $OUTDIR"
echo

# ---------- Helper to clean up monitor mode / IDS ----------
cleanup(){
  if [[ -n "${MON_IF:-}" ]]; then
    hdr "Cleanup: stopping monitor mode ($MON_IF)"
    airmon-ng stop "$MON_IF" >/dev/null 2>&1 || true
    MON_IF=""
  fi
  if [[ -f "$OUTDIR/suricata.pid" ]]; then
    kill "$(cat "$OUTDIR/suricata.pid")" 2>/dev/null || true
  fi
  if [[ -f "$OUTDIR/zeek.pid" ]]; then
    kill "$(cat "$OUTDIR/zeek.pid")" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------- Launch IDS (optional) ----------
start_suricata(){
  (( HAVE_SURICATA==1 )) || return 0
  hdr "Starting Suricata (IDS) on $IFACE"
  mkdir -p "$OUTDIR/suricata"
  # Run with default rules if present; otherwise start with built-in.
  sudo suricata -i "$IFACE" -l "$OUTDIR/suricata" >/dev/null 2>&1 &
  echo $! > "$OUTDIR/suricata.pid"
  ok "Suricata started. Logs: $OUTDIR/suricata/eve.json (jq -c . | less)"
}

start_zeek(){
  (( HAVE_ZEEK==1 )) || return 0
  hdr "Starting Zeek (network telemetry) on $IFACE"
  mkdir -p "$OUTDIR/zeek"
  ( cd "$OUTDIR/zeek" && sudo zeek -i "$IFACE" ) >/dev/null 2>&1 &
  echo $! > "$OUTDIR/zeek.pid"
  ok "Zeek started. Logs: $OUTDIR/zeek/*.log (conn.log, dns.log, http.log...)"
}

if (( RUN_SURI==1 )); then start_suricata; fi
if (( RUN_ZEEK==1 )); then start_zeek; fi

# ---------- Stage 0: Host discovery ----------
report_section "1. Discover target devices" "Send host discovery probes to $CUSTOM_SUBNET." "A discovered host answered these probes. No hosts can mean filtering, isolation, a wrong range or a failed scan." "Check the selected adapter and subnet if no hosts appear."
LIVE_LIST="$OUTDIR/live-hosts.txt"
if have arp-scan; then
  sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null > "$OUTDIR/arp-scan.txt" || true
  awk 'match($0,/^([0-9.]+)[ \t]+(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})/,m){print m[1]}' "$OUTDIR/arp-scan.txt" | sort -u > "$LIVE_LIST"
fi
if [[ ! -s "$LIVE_LIST" ]]; then
  sudo nmap -sn -T4 --max-retries 1 --host-timeout 8s "$CUSTOM_SUBNET" -oA "$OUTDIR/pingscan" >/dev/null
  awk '/^Host:/ && /Status: Up/ {print $2}' "$OUTDIR/pingscan.gnmap" | tr -d '()' | sort -u > "$LIVE_LIST"
fi
if [[ ! -s "$LIVE_LIST" ]]; then
  warn "No targets answered discovery; the security audit did not run."
  info "Next: check net-tools quicknet and inspect $OUTDIR/pingscan.nmap or arp-scan.txt with --details."
  exit 1
fi
COUNT=$(wc -l < "$LIVE_LIST" | tr -d ' ')
ok "Discovered $COUNT host(s) → $LIVE_LIST"

# ---------- Stage 1: Full TCP sweep (-p-) ----------
report_section "2. TCP service ports" "Probe all TCP ports on the discovered targets." "Open ports show exposed services, not confirmed flaws. The 15-second host limit can leave the scan incomplete."
report_port_legend
NMAP_BASE=(-Pn --defeat-rst-ratelimit --min-rate 600 --max-retries 1 --host-timeout 15s -T4)
sudo nmap "${NMAP_BASE[@]}" -sS -p- -iL "$LIVE_LIST" -oA "$OUTDIR/tcp-all" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."

# ---------- Stage 2: Service/OS fingerprint ----------
report_section "3. Service and OS identification" "Ask services for version hints and estimate device operating systems." "Fingerprints can be wrong or missing. Confirm device identity in its own settings before acting."
sudo nmap "${NMAP_BASE[@]}" -sS -sV -O --reason --version-all -iL "$LIVE_LIST" -oA "$OUTDIR/tcp-svcos" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."

# ---------- Stage 3: Top UDP ports (optional) ----------
if (( DO_UDP==1 )); then
  report_section "4. UDP services" "Probe the 50 most common UDP ports." "open|filtered means no clear answer; UDP often stays silent. It is not proof a service is open."
  sudo nmap "${NMAP_BASE[@]}" -sU --top-ports 50 --defeat-icmp-ratelimit -iL "$LIVE_LIST" -oA "$OUTDIR/udp-top50" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."
fi

# ---------- Stage 4: Protocol-focused NSE (safe/discovery) ----------
report_section "5. Service discovery scripts" "Run discovery scripts and HTTP, TLS, SMB and SNMP checks." "These can reveal titles, certificates and shares. Discovery categories can still send active requests." "Review unexpected services, anonymous shares and outdated device firmware."
SAFE_SCRIPTS="default,safe,discovery"
sudo nmap "${NMAP_BASE[@]}" -sS -sV --script "$SAFE_SCRIPTS" -iL "$LIVE_LIST" -oA "$OUTDIR/nse-safe" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."

report_section "Web services and encryption" "Inspect HTTP headers, methods, authentication hints and TLS ciphers." "A title identifies a page; a weak-cipher hint needs confirmation in the saved report. This stage includes default-account checks."
# HTTP/HTTPS detail
sudo nmap "${NMAP_BASE[@]}" -p 80,8080,8000,443,8443,8888 \
  --script "http-title,http-headers,http-methods,http-server-header,http-enum,http-auth,http-default-accounts,ssl-cert,ssl-enum-ciphers" \
  -iL "$LIVE_LIST" -oA "$OUTDIR/nse-http" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."

report_section "File sharing (SMB)" "Inspect Windows-style sharing capabilities and shares." "A visible share is not necessarily readable without login. Review access on the target device."
# SMB
sudo nmap "${NMAP_BASE[@]}" -p 445,139 \
  --script "smb-os-discovery,smb2-security-mode,smb2-capabilities,smb-enum-shares,smb-protocols,smb2-time" \
  -iL "$LIVE_LIST" -oA "$OUTDIR/nse-smb" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."

report_section "Management services (SNMP)" "Inspect management information when a service responds." "Accessible management data can expose device details. This existing probe targets TCP 161; UDP SNMP is only covered by optional UDP scans."
# SNMP
sudo nmap "${NMAP_BASE[@]}" -p 161 --script "snmp-info,snmp-interfaces" -iL "$LIVE_LIST" -oA "$OUTDIR/nse-snmp" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."

# ---------- Stage 5: Intrusive/vuln/brute (gated) ----------
if (( INTRUSIVE==1 )); then
  report_section "6. Vulnerability probes" "Run the selected intrusive and vulnerability script categories." "A positive script finding is a lead to verify, not proof of exploitation. No finding is not a clean bill of health." "Confirm the affected service, patch level and matching finding in nse-intrusive.nmap."
  sudo nmap "${NMAP_BASE[@]}" -sS -sV --script "intrusive,vuln" -iL "$LIVE_LIST" -oA "$OUTDIR/nse-intrusive" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."
fi
if (( BRUTE==1 )); then
  report_section "7. Credential and authentication tests" "Run brute-force and authentication scripts on responding services." "A reported valid credential needs review; failed attempts can lock accounts. An interrupted scan does not prove passwords are strong." "Change confirmed weak/default credentials and inspect target authentication logs."
  sudo nmap "${NMAP_BASE[@]}" -sS -sV --script "brute,auth" -iL "$LIVE_LIST" -oA "$OUTDIR/nse-brute" 2>&1 | report_evidence || warn "Scan did not complete; inspect its saved report."
fi

if (( INTRUSIVE == 0 )); then report_result SKIP 'Vulnerability script category not selected.'; fi
if (( BRUTE == 0 )); then report_result SKIP 'Credential script category not selected (web default-account probes still ran).'; fi
if (( DO_UDP == 0 )); then report_result SKIP 'UDP service scan not selected.'; fi
if (( DO_WIFI == 0 )); then report_result SKIP 'WiFi monitor/capture tests not selected.'; fi

# ---------- Stage 7: Wi-Fi (optional) ----------
wifi_start_monitor(){
  (( HAVE_AIRMON==1 )) || { warn "airmon-ng not found"; return 1; }
  hdr "Wi-Fi: enabling monitor mode (will temporarily disrupt Wi-Fi on $IFACE)"
  sudo airmon-ng check kill >/dev/null 2>&1 || true
  sudo airmon-ng start "$IFACE" >/tmp/_airmon 2>&1 || true
  MON_IF="$(awk '/monitor mode vif/ {print $NF} /monitor mode enabled/ {print $2}' /tmp/_airmon | tail -1)"
  if [[ -z "${MON_IF:-}" ]]; then
    # common naming convention IFACEmon
    MON_IF="${IFACE}mon"
  fi
  if ip link show "$MON_IF" >/dev/null 2>&1; then ok "Monitor IF: $MON_IF"; else fail "Failed to create monitor IF"; return 1; fi
}

wifi_scan_wpa(){
  (( WIFI_WPA_SCAN==1 && HAVE_AIRODUMP==1 )) || return 0
  report_section "WiFi access points and handshake capture" "Observe access point announcements and authentication traffic." "A saved capture does not prove a handshake was captured or a password was recovered." "Inspect the capture in Wireshark or aircrack-ng."
  mkdir -p "$OUTDIR/wifi"
  timeout 20 sudo airodump-ng "$MON_IF" --band abg --output-format csv,pcap \
    --write "$OUTDIR/wifi/airodump" >/dev/null 2>&1 || true
  info "Capture attempt finished. Inspect files matching $OUTDIR/wifi/airodump*; a timeout or error may leave incomplete data."
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
      sudo airodump-ng --bssid "$B" --channel "$CH" -w "$OUTDIR/wifi/handshake" "$MON_IF" >/dev/null 2>&1 &
      DUMP_PID=$!
      sleep 2
      if [[ -n "${C:-}" ]]; then
        sudo aireplay-ng -0 "${N:-5}" -a "$B" -c "$C" "$MON_IF" || true
      else
        sudo aireplay-ng -0 "${N:-5}" -a "$B" "$MON_IF" || true
      fi
      sleep 5; kill "$DUMP_PID" 2>/dev/null || true
      ok "Handshake capture attempt done. Check $OUTDIR/wifi/handshake*.pcap"
    fi
  fi
}

wifi_wps_discovery(){
  (( WIFI_WPS_DISC==1 && HAVE_WASH==1 )) || return 0
  report_section "WiFi WPS discovery" "Read WPS advertisements; this stage does not attack a PIN." "WPS enabled is a configuration finding. Locked status does not guarantee security." "Disable unused WPS in your router settings."
  mkdir -p "$OUTDIR/wifi"
  timeout 30 sudo wash -i "$MON_IF" -2 -s -g -j > "$OUTDIR/wifi/wps.json" 2>/dev/null || true
  info "WPS probe finished. Inspect $OUTDIR/wifi/wps.json; an empty file means no usable result."
  echo "• If 'WPS Locked' is false and WPS enabled, disable WPS on the AP."
}

if (( DO_WIFI==1 )); then
  wifi_start_monitor || true
  [[ -n "${MON_IF:-}" ]] && wifi_scan_wpa
  [[ -n "${MON_IF:-}" ]] && wifi_wps_discovery
fi

# ---------- Summary ----------
report_section "Security findings summary" "Collect service and script findings from saved reports." "No matching line means no recorded finding, not a passed security audit. Skipped and failed checks remain untested." "Use the file and line references below to confirm each finding before changing the device."
SUMMARY="$OUTDIR/summary.txt"
{
  echo "Intrusive LAN + Wi-Fi Audit — $TS"
  echo "Targets: $CUSTOM_SUBNET  (hosts: $COUNT)"
  echo
  echo "Telnet/FTP: cleartext services; review and disable if unused."
  grep -HnE '23/tcp\s+open|21/tcp\s+open' "$OUTDIR"/* 2>/dev/null || true
  echo
  echo "SMB/shares: review who can access files; port 445 alone is not a flaw."
  grep -HnE '445/tcp\s+open' "$OUTDIR"/* 2>/dev/null || true
  grep -Hn 'smb-enum-shares' "$OUTDIR"/* 2>/dev/null || true
  echo
  echo "SNMP: review management exposure and authentication."
  grep -HnE '161/(udp|tcp)\s+open' "$OUTDIR"/* 2>/dev/null || true
  echo
  echo "TLS hints: review the matching cipher and protocol in nse-http.nmap."
  grep -HnE '(RC4|MD5|NULL|EXPORT|LOW)' "$OUTDIR"/nse-http.nmap 2>/dev/null || true
  echo
  echo "Positive vulnerability leads: verify script details and device firmware."
  grep -HnE '(^|[^[:alpha:]])VULNERABLE([^[:alpha:]]|$)' "$OUTDIR"/*.nmap 2>/dev/null | awk '!/NOT VULNERABLE/' || true
  echo
  if [[ -d "$OUTDIR/wifi" ]]; then
    echo "# Wi-Fi artifacts:"
    ls -1 "$OUTDIR/wifi" 2>/dev/null || true
  fi
} > "$SUMMARY"
cat "$SUMMARY" | report_evidence

echo
info "Audit attempts finished. Full evidence: $OUTDIR | Summary: $SUMMARY"
echo "If you started Suricata/Zeek, their logs are under $OUTDIR/suricata and $OUTDIR/zeek."
echo "This script will stop monitor mode and IDS on exit."
