#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- UI ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
say(){ printf "%b%s%b\n" "$1" "$2" "$NC"; }
ok(){ say "$GREEN" "OK  - $1"; }
warn(){ say "$YELLOW" "WARN- $1"; }
fail(){ say "$RED" "FAIL- $1"; }
hdr(){ printf "\n${BOLD}%s${NC}\n" "$1"; }
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

hdr "🏠 Home Wi-Fi Audit (owner-safe)"
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
hdr "📡 Radio & Link"
if [[ "$IFACE" =~ ^wl ]] && have iw; then
  iw dev "$IFACE" link 2>/dev/null | sed 's/^/  /' || true

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
  if iw dev "$IFACE" scan >/tmp/_iwscan 2>/dev/null; then
    STRONG_NEI="$(awk '
      /^BSS /{sig=""}
      /signal:/ {gsub(/dBm/,""); sig=$2}
      /^SSID:/ { if (sig != "" && sig+0 > -65) c++ }
      END{print c+0}
    ' /tmp/_iwscan 2>/dev/null || echo 0)"
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
hdr "🛡️  Router Surface (safe scan)"
sudo nmap "${NMAP_FAST[@]}" --top-ports 100 --open --script "default,safe,discovery" "$GW" | sed -n '1,160p'

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
hdr "🧭 LAN Inventory (owner network)"
if have arp-scan; then
  sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null \
    | awk 'match($0,/^([0-9.]+)[ \t]+(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})[ \t]+(.+)$/,m){printf "  %-15s %-17s %s\n", m[1], m[2], m[4]}' \
    | head -40
  LAN_COUNT="$(sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null | grep -cE '^[0-9]+\.[0-9]+')"
else
  warn "arp-scan missing; using quick ping sweep"
  sudo nmap -sn "$SUB24" --host-timeout 5s | grep -E 'Nmap scan report|MAC Address' | sed 's/^/  /' | head -40
  LAN_COUNT="$(sudo nmap -sn "$SUB24" --host-timeout 5s 2>/dev/null | grep -c 'Nmap scan report' || echo 0)"
fi

# ---------- 4) Egress & DNS ----------
hdr "🌍 Egress & DNS"
PUB_OUT="$(sudo nmap "${NMAP_FAST[@]}" -p 53,80,443 1.1.1.1 8.8.8.8 2>/dev/null | sed -n '1,120p')"
echo "$PUB_OUT"
if grep -qE '53/tcp\s+filtered'  <<<"$PUB_OUT" && \
   grep -qE '80/tcp\s+filtered'  <<<"$PUB_OUT" && \
   grep -qE '443/tcp\s+filtered' <<<"$PUB_OUT"; then
  EGRESS_STATUS="blocked"
else
  EGRESS_STATUS="ok"
fi

dns_latency_ms() {
  local s="$1" d="$2"
  timeout 3 dig @"$s" +time=1 +tries=1 +stats "$d" A 2>/dev/null | awk '/Query time:/{print $4}'
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
hdr "📦 MTU sanity"
if ping -M do -s 1472 -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
  MTU_STATUS="1500"
elif ping -M do -s 1464 -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
  MTU_STATUS="1492"
else
  MTU_STATUS="unsure"
fi
echo "Likely working MTU: $MTU_STATUS"

# ---------- Explanations ----------
explain_radio(){
  hdr "Explanation — Radio & Link"
  case "$RADIO_STATUS" in
    good)     ok "Signal is strong (>-60 dBm). Expect stable throughput."; echo "Tip: keep using this AP/channel.";;
    moderate) warn "Signal is moderate (-60..-70 dBm)."; echo "Tip: move AP closer, reduce walls, or add a wired AP/mesh."; ;;
    weak)     fail "Signal is weak (<-70 dBm)."; echo "Tip: relocate AP, add wired backhaul, or use a less crowded channel."; ;;
    notwifi)  warn "Radio analysis skipped (not Wi-Fi or 'iw' missing).";;
    *)        warn "Radio status unknown."; ;;
  esac
  case "$CHANNEL_CROWD" in
    clear)    ok "Channel looks clear (few strong neighboring APs).";;
    moderate) warn "Channel is moderately crowded."; echo "Tip: try another channel or 5/6 GHz band if supported.";;
    crowded)  fail "Channel is crowded (many strong neighbors)."; echo "Tip: pick a cleaner channel; limit 80 MHz widths unless DFS is clean."; ;;
    *)        ;;
  esac
}

explain_router(){
  hdr "Explanation — Router Surface"
  if (( ROUTER_RISK == 0 )); then
    ok "No obvious risky services found on the router."
    echo "Keep admin HTTPS-only and LAN-only; keep firmware updated; disable WPS."
  else
    fail "Risky services detected:"
    for f in "${ROUTER_FLAGS[@]}"; do echo "  - $f"; done
    echo "Action: disable legacy services (FTP/Telnet), restrict management to LAN over HTTPS, update firmware."
  fi
}

explain_egress_dns(){
  hdr "Explanation — Egress & DNS"
  case "$EGRESS_STATUS" in
    ok)
      ok "Outbound traffic is allowed."
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
    1500) ok "Standard Ethernet MTU is working (no fragmentation expected).";;
    1492) warn "Path behaves like PPPoE (1492)."; echo "Set WAN MTU accordingly to avoid fragmentation (router setting).";;
    *)    warn "MTU unclear. If you see odd hangs on large transfers, try lowering MTU on WAN and retest."; ;;
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
  echo "- Router surface: $([[ $ROUTER_RISK -eq 0 ]] && echo safe || echo needs hardening)"
  echo "- Internet egress: $EGRESS_STATUS"
  echo "- DNS: $DNS_LAT_MSG (times: ${DNS_TIMES[*]:-n/a})"
  echo "- MTU: $MTU_STATUS"
  echo "- LAN devices: $LAN_COUNT"
  echo
  # Overall steer
  if [[ "$RADIO_STATUS" == "good" && "$CHANNEL_CROWD" != "crowded" && $ROUTER_RISK -eq 0 && "$EGRESS_STATUS" == "ok" ]]; then
    ok "Overall: solid home Wi-Fi posture."
    echo "Improvements: add local DNS cache, wire heavy devices, keep firmware current."
  else
    warn "Overall: see explanations above for targeted fixes."
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
