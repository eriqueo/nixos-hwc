#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=network-report.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/network-report.sh"
report_init 'Home WiFi checks' 'Inspect signal strength, nearby access points, router services, DNS latency and packet size.' \
  'Sends radio and LAN probes; scans router services and may request sudo.' '[--details]' "$@" || exit 0
set -- "${REPORT_ARGS[@]}"


have(){ command -v "$1" >/dev/null 2>&1; }

# ---------- Requirements (best-effort) ----------
for t in ip nmap dig; do have "$t" || { fail "Missing '$t'"; exit 2; }; done
have iw || warn "iw not found (radio/channel checks reduced)"
have arp-scan || true
have iperf3 || true

# ---------- Discover ----------
DEF="$(ip route show default | head -n1 || true)"
IFACE="$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$DEF")"
GW="$(awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<<"$DEF")"
CIDR="$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | head -1 || true)"
[[ -z "${IFACE:-}" || -z "${GW:-}" || -z "${CIDR:-}" ]] && { fail "No default route or IPv4 address"; exit 1; }
IP="${CIDR%%/*}"
SUB24="$(cut -d. -f1-3 <<<"$IP").0/24"
NMAP_FAST=(-Pn --max-retries 1 --host-timeout 8s -T4)

hdr "Home WiFi probe results"
echo "IFACE=$IFACE  IP=$IP  GW=$GW  LAN=$SUB24  $(date)"

# ---------- Status buckets ----------
RADIO_STATUS="unknown"      # good | moderate | weak | notwifi | unknown
CHANNEL_CROWD="unknown"     # clear | moderate | crowded | unknown
ROUTER_RISK=0               # 0 ok | 1 risky service found
ROUTER_FLAGS=()             # messages for risky services
EGRESS_STATUS="unknown"     # ok | blocked
DNS_LAT_MSG="unknown"       # fast | moderate | slow | unknown
DNS_TIMES=()                # ms values to show
MTU_STATUS="unknown"        # 1500 | 1492 | unsure
LAN_COUNT="n/a"

# ---------- 1) Radio & Link ----------
report_section "1. WiFi signal and nearby access points" "Read signal strength and count nearby strong access points." "Less negative dBm is stronger. Nearby AP counts do not measure channel airtime." "Compare signal from another room before changing router channels."
if [[ "$IFACE" =~ ^wl ]] && have iw; then
  iw dev "$IFACE" link 2>/dev/null | report_evidence || true

  # RSSI classification
  RSSI="$(iw dev "$IFACE" link 2>/dev/null | awk '/signal:/ {print $2}' || true)"
  if [[ -n "${RSSI:-}" ]]; then
    if awk -v r="$RSSI" 'BEGIN{exit !(r>-60)}'; then
      RADIO_STATUS="good"
    elif awk -v r="$RSSI" 'BEGIN{exit !(r>-70)}'; then
      RADIO_STATUS="moderate"
    else
      RADIO_STATUS="weak"
    fi
  fi

  # Channel crowding: count strong neighbors (signal > -65 dBm)
  STRONG_NEI=0
  if IW_SCAN=$(iw dev "$IFACE" scan 2>/dev/null); then
    STRONG_NEI="$(awk '
      /^BSS /{sig=""}
      /signal:/ {gsub(/dBm/,""); sig=$2}
      /^[[:space:]]*SSID:/ { if (sig != "" && sig+0 > -65) c++ }
      END{print c+0}
    ' <<< "$IW_SCAN" 2>/dev/null || echo 0)"
    if   (( STRONG_NEI <= 2 )); then CHANNEL_CROWD="clear"
    elif (( STRONG_NEI <= 5 )); then CHANNEL_CROWD="moderate"
    else CHANNEL_CROWD="crowded"; fi
  else
    CHANNEL_CROWD="unknown"
  fi
else
  RADIO_STATUS="notwifi"
  warn "Interface isn’t Wi-Fi or 'iw' missing; skipping radio analysis"
fi

# ---------- 2) Router Surface (safe scan) ----------
report_section "2. Router services" "Probe common ports and run discovery scripts on the router." "Open services expand the router surface; this does not confirm a vulnerability." "Review unexpected services and firmware in the router settings."
report_port_legend
sudo nmap "${NMAP_FAST[@]}" --top-ports 100 --open --script "default,safe,discovery" "$GW" | report_evidence || warn "Router scan failed or timed out; results are incomplete."

# Flag risky services (FTP/Telnet/CWMP/UPnP hints)
if sudo nmap "${NMAP_FAST[@]}" -p 21 "$GW" | grep -qE '21/tcp\s+open'; then
  ROUTER_RISK=1; ROUTER_FLAGS+=("FTP (21/tcp) open — disable")
fi
if sudo nmap "${NMAP_FAST[@]}" -p 23 "$GW" | grep -qE '23/tcp\s+open'; then
  ROUTER_RISK=1; ROUTER_FLAGS+=("Telnet (23/tcp) open — disable")
fi
if sudo nmap "${NMAP_FAST[@]}" -p 7547 "$GW" | grep -qE '7547/tcp\s+open'; then
  ROUTER_RISK=1; ROUTER_FLAGS+=("TR-069/CWMP (7547/tcp) open — ensure auth/firmware or disable")
fi
# (We avoid loud UDP SSDP scans; if you care, run a focused check later.)

# ---------- 3) LAN Inventory ----------
report_section "3. Visible LAN devices" "Discover local device addresses and vendor hints." "Vendor names identify the network chip maker, not necessarily the device brand. Quiet devices can be missed."
if have arp-scan; then
  sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null \
    | awk 'match($0,/^([0-9.]+)[ \t]+(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})[ \t]+(.+)$/,m){printf "  %-15s %-17s %s\n", m[1], m[2], m[4]}' \
    | report_evidence || warn 'Discovery did not complete.'
  LAN_COUNT="$(sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null | awk '/^[0-9]+\.[0-9]+/{n++} END{print n+0}' || echo unknown)"
else
  warn "arp-scan missing; using quick ping sweep"
  sudo nmap -sn "$SUB24" --host-timeout 5s | report_evidence || warn 'Discovery did not complete.'
  LAN_COUNT="$(sudo nmap -sn "$SUB24" --host-timeout 5s 2>/dev/null | awk '/Nmap scan report/{n++} END{print n+0}' || echo unknown)"
fi

# ---------- 4) Egress & DNS ----------
report_section "4. Public access and DNS delay" "Probe public TCP ports and time two public DNS lookups." "A TCP reply confirms that service; DNS timings are a small sample, not a benchmark."
PUB_OUT="$(sudo nmap "${NMAP_FAST[@]}" -p 53,80,443 1.1.1.1 8.8.8.8 2>&1 || true)"
printf '%s\n' "$PUB_OUT" | report_evidence
if awk '$1 ~ /^(53|80|443)\/tcp$/ && $2 == "open" {found=1} END{exit !found}' <<< "$PUB_OUT"; then
  EGRESS_STATUS=ok
else
  EGRESS_STATUS=unknown
fi

dns_latency_ms() {
  local s="$1" d="$2" response
  response=$(timeout 3 dig @"$s" +time=1 +tries=1 +stats "$d" A 2>/dev/null) || return 1
  awk '$4 == "A" && $5 ~ /^[0-9]+\./ {answer=1} /Query time:/ {ms=$4}
    END {if(answer && ms ~ /^[0-9]+$/) print ms; else exit 1}' <<< "$response"
}
if [[ "$EGRESS_STATUS" == "ok" ]]; then
  for s in 1.1.1.1 8.8.8.8; do
    t="$(dns_latency_ms "$s" google.com || true)"
    if [[ -n "${t:-}" ]]; then DNS_TIMES+=("$s:$t ms"); fi
  done
  # Classify by the best time we observed
  best=9999
  for kv in "${DNS_TIMES[@]}"; do
    val="${kv##*:}"; val="${val% ms}"
    [[ "$val" =~ ^[0-9]+$ ]] && (( val < best )) && best="$val"
  done
  if   (( best <= 20 )); then DNS_LAT_MSG="fast"
  elif (( best <= 60 )); then DNS_LAT_MSG="moderate"
  elif (( best < 9999 )); then DNS_LAT_MSG="slow"
  else DNS_LAT_MSG="unknown"; fi
fi

# ---------- 5) MTU sanity ----------
report_section "5. Packet size (MTU)" "Send non-fragmenting ping packets sized for 1500 and 1492 bytes." "A reply gives a tested lower bound. No reply may mean ping filtering, not a packet-size fault." "Do not change WAN MTU from this result alone."
if ping -M do -s 1472 -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
  MTU_STATUS="1500"
elif ping -M do -s 1464 -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
  MTU_STATUS="1492"
else
  MTU_STATUS="unsure"
fi
echo "Packet size that answered: $MTU_STATUS"

# ---------- Explanations ----------
explain_radio(){
  hdr "Explanation — Radio & Link"
  case "$RADIO_STATUS" in
    good)     ok "Signal is strong (>-60 dBm); throughput is not measured here."; echo "Tip: compare signal in the rooms you use.";;
    moderate) warn "Signal is moderate (-60..-70 dBm)."; echo "Tip: move AP closer, reduce walls, or add a wired AP/mesh."; ;;
    weak)     fail "Signal is weak (<-70 dBm)."; echo "Tip: relocate AP, add wired backhaul, or use a less crowded channel."; ;;
    notwifi)  warn "Radio analysis skipped (not Wi-Fi or 'iw' missing).";;
    *)        warn "Radio status unknown."; ;;
  esac
  case "$CHANNEL_CROWD" in
    clear)    ok "Few strong access points were seen nearby; channel congestion is unmeasured.";;
    moderate) warn "Several strong access points were seen; compare their channels before changing yours."; echo "Tip: try another channel or 5/6 GHz band if supported.";;
    crowded)  warn "Many strong access points were seen; this does not establish congestion on your channel."; echo "Tip: pick a cleaner channel; limit 80 MHz widths unless DFS is clean."; ;;
    *)        ;;
  esac
}

explain_router(){
  hdr "Explanation — Router Surface"
  if (( ROUTER_RISK == 0 )); then
    info "No selected service probe reported FTP, Telnet or CWMP open; scan failures can hide services."
    echo "Keep admin HTTPS-only and LAN-only; keep firmware updated; disable WPS."
  else
    warn "Services to review:"
    for f in "${ROUTER_FLAGS[@]}"; do echo "  - $f"; done
    echo "Action: disable legacy services (FTP/Telnet), restrict management to LAN over HTTPS, update firmware."
  fi
}

explain_egress_dns(){
  hdr "Explanation — Egress & DNS"
  case "$EGRESS_STATUS" in
    ok)
      ok "At least one tested public service port answered."
      if [[ "$DNS_LAT_MSG" == "fast" ]]; then
        echo "DNS is fast (resolver replies quickly)."
      elif [[ "$DNS_LAT_MSG" == "moderate" ]]; then
        warn "DNS is okay but not great. Consider a local cache (unbound) for snappier name lookups."
      elif [[ "$DNS_LAT_MSG" == "slow" ]]; then
        warn "DNS is slow. Try switching resolvers or adding a local caching resolver."
      else
        warn "DNS latency unknown (timeouts or tool limits)."
      fi
      echo "Observed: ${DNS_TIMES[*]:-n/a}"
      ;;
    blocked)
      fail "Common outbound ports appear filtered. This would break normal browsing."
      echo "If this is your home network, check router firewall rules and parental controls."
      ;;
    *) warn "Egress status unknown." ;;
  esac
}

explain_mtu(){
  hdr "Explanation — MTU"
  case "$MTU_STATUS" in
    1500) ok "A 1500-byte non-fragmenting packet answered on the tested path.";;
    1492) info "The 1492-byte probe answered; the 1500-byte probe did not."; echo "Meaning: This does not identify PPPoE or prove an exact MTU.";;
    *)    warn "MTU unconfirmed. Ping filtering can make both probes fail."; ;;
  esac
}

explain_lan(){
  hdr "Explanation — LAN Inventory"
  echo "Devices detected on LAN (approx): $LAN_COUNT"
  if [[ "$LAN_COUNT" =~ ^[0-9]+$ ]]; then
    if (( LAN_COUNT <= 5 )); then
      ok "Normal small-home footprint."
    elif (( LAN_COUNT <= 20 )); then
      warn "Medium device count—keep firmware updated and segment IoT if possible."
    else
      warn "Large LAN—consider VLANs/guest networks and stronger monitoring."
    fi
  fi
}

state_of_parts(){
  hdr "State of the system’s parts (plain English)"
  echo "- Radio link: $RADIO_STATUS (channel: $CHANNEL_CROWD)"
  echo "- Selected router service flags: $ROUTER_RISK (0 does not prove security)"
  echo "- Internet egress: $EGRESS_STATUS"
  echo "- DNS: $DNS_LAT_MSG (times: ${DNS_TIMES[*]:-n/a})"
  echo "- MTU: $MTU_STATUS"
  echo "- LAN devices: $LAN_COUNT"
  echo
  local basis="Signal: $RADIO_STATUS; public access: $EGRESS_STATUS; public DNS timing: $DNS_LAT_MSG; selected service flags: $ROUTER_RISK; packet size reply: $MTU_STATUS."
  local limits='Nearby AP counts do not prove congestion. Public DNS timing does not test system DNS. Router probes are LAN-only; no finding does not prove security.'
  if [[ $RADIO_STATUS == weak ]]; then
    report_tldr CHECK 'Weak WiFi signal is a lead to investigate.' "$basis" \
      'Move nearer your access point and rerun net-tools homewifi-audit. Compare the signal and the actual app performance before changing channels.' "$limits"
  elif (( ROUTER_RISK > 0 )); then
    report_tldr CHECK 'Selected router services need review.' "$basis" \
      "Review ${ROUTER_FLAGS[*]} in the router settings. Confirm each service is needed and restricted before disabling it." "$limits"
  elif [[ $EGRESS_STATUS != ok ]]; then
    report_tldr UNKNOWN 'Public access is unconfirmed.' "$basis" \
      'Run net-tools advnetcheck to separate router, public access and DNS results. Compare another device on this WiFi.' "$limits"
  elif [[ $RADIO_STATUS == moderate ]]; then
    report_tldr CHECK 'Public access answered; WiFi signal is moderate.' "$basis" \
      'If speed or stability is poor, compare nearer the access point and test a wired connection. Keep settings until the comparison identifies a cause.' "$limits"
  elif [[ $RADIO_STATUS != good || $DNS_LAT_MSG == unknown || $MTU_STATUS != 1500 ]]; then
    report_tldr UNKNOWN 'Public access answered; some WiFi or path checks remain inconclusive.' "$basis" \
      'Review the untested radio, DNS timing or packet-size section above. Use net-tools advnetcheck if browsing fails; do not change MTU from silence alone.' "$limits"
  elif [[ $DNS_LAT_MSG == slow ]]; then
    report_tldr CHECK 'Signal is strong; sampled public DNS replies were slow.' "$basis" \
      'Repeat the DNS timing check before changing resolvers. Use net-tools advnetcheck to compare with your configured DNS.' "$limits"
  else
    report_tldr PASS 'Signal and sampled public access look usable.' "$basis" \
      'No setting change is indicated by these samples. If speed remains poor, compare a wired connection or measure LAN throughput with an iperf3 server.' "$limits"
  fi

}

# ---------- Print explanations ----------
explain_radio
explain_router
explain_egress_dns
explain_mtu
explain_lan
state_of_parts

# ---------- Optional throughput hint ----------
if have iperf3; then
  echo
  echo "Throughput test (optional, needs a server on LAN):"
  echo "  iperf3 -s                      # on a LAN host"
  echo "  iperf3 -c <LAN-IP> -R          # downstream test"
fi
