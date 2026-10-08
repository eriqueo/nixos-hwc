#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=network-report.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/network-report.sh"
report_init 'Quick connection check' 'Check the router, public service ports, DNS and visible LAN devices.' \
  'Sends connectivity probes and may request sudo for scans.' '[--details]' "$@" || exit 0
set -- "${REPORT_ARGS[@]}"

have(){ command -v "$1" >/dev/null 2>&1; }
need(){ have "$1" || { fail "Missing '$1'"; exit 2; }; }

# --- deps ---
need ip
need nmap
have dig || warn "dig not found (DNS test will be skipped)"
have arp-scan || true
have arping || true

# --- discover ---
DEF="$(ip route show default | head -n1 || true)"
IFACE="$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$DEF")"
GW="$(awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<<"$DEF")"
CIDR="$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | head -1 || true)"
if [[ -z "${IFACE:-}" || -z "${GW:-}" || -z "${CIDR:-}" ]]; then
  fail "No default route or IPv4 address"
  exit 1
fi
IP="${CIDR%%/*}"
SUB24="$(cut -d. -f1-3 <<<"$IP").0/24"

# --- results we’ll explain later ---
GW_STATUS="unknown"         # icmp_ok | arp_only | unreachable
EGRESS_STATUS="unknown"     # ok | blocked
DNS_STATUS="skipped"        # ok | fail | skipped
LAN_PEERS="n/a"

info "Network adapter: $IFACE | Your address: $IP | Router: $GW"
info "Discovery range: $SUB24 (a /24 sample; not necessarily the full LAN)"

# === 1) Gateway reachability ===
report_section '1. Reach the router' 'Ping, then ARP if available.' \
  'A reply confirms a local path. No reply can also mean probe filtering.' 'Compare with another device before reconnecting WiFi.'
if ping -c1 -W1 "$GW" >/dev/null 2>&1; then
  ok "Gateway replies to ICMP"
  GW_STATUS="icmp_ok"
elif have arping && sudo arping -c1 -w2 "$GW" >/dev/null 2>&1; then
  warn "Gateway reachable by ARP (ICMP blocked)"
  GW_STATUS="arp_only"
else
  warn "Router reachability not confirmed by these probes"
  GW_STATUS="unreachable"
fi

# === 2) Public egress sanity (53/80/443) ===
report_section '2. Reach public services' 'TCP ports 53 (DNS), 80 (HTTP) and 443 (HTTPS) on two public hosts.' \
  'An open port confirms that connection; it does not test every website.' 'If no service answers, check VPN settings and any browser login page.'
report_port_legend
NMAP_OPTS=(-Pn --max-retries 1 --host-timeout 6s -T4)
PUB_OUT="$(sudo nmap "${NMAP_OPTS[@]}" -p 53,80,443 1.1.1.1 8.8.8.8 2>&1 || true)"
printf '%s\n' "$PUB_OUT" | report_evidence

# Decide egress: if all three ports appear filtered in the combined output → blocked
if awk '$1 ~ /^(53|80|443)\/tcp$/ && $2 == "open" {found=1} END {exit !found}' <<< "$PUB_OUT"; then
  EGRESS_STATUS="ok"
elif awk '$1 ~ /^(53|80|443)\/tcp$/ && $2 == "filtered" {n++} END {exit !(n >= 6)}' <<< "$PUB_OUT"; then
  EGRESS_STATUS="blocked"
else
  EGRESS_STATUS="unknown"
fi

# === 3) DNS quick test ===
report_section '3. Resolve a website name' 'Ask the configured resolver for google.com.' \
  'An address answer confirms this lookup. An empty answer does not count as success.' 'Compare configured and public DNS with net-tools advnetcheck.'
if have dig; then
  if report_dns_answer google.com; then
    DNS_STATUS="ok"
  else
    DNS_STATUS="fail"
  fi
fi

# === 4) LAN peers (quick count) ===
report_section '4. Discover local devices' 'Count ARP replies on the local network, if arp-scan is installed.' \
  'This is a snapshot. Quiet or isolated devices may not appear.'
if have arp-scan; then
  LAN_PEERS="$(sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null | awk '/^[0-9]+\.[0-9]+/{n++} END{print n+0}' || printf 'unknown')"
fi

# ---------- EXPLANATIONS PER CHECK ----------
explain_gateway(){
  hdr "Gateway (your router)"
  case "$GW_STATUS" in
    icmp_ok)
      ok "Your computer can talk to the router normally."
      echo "Meaning: Basic local connectivity is good. Wi-Fi association and IP/DHCP look fine."
      ;;
    arp_only)
      warn "Router seen at hardware level, but it ignores ping."
      echo "Meaning: The router answered locally. Ping filtering or loss is possible."
      ;;
    unreachable)
      warn "The router did not answer these probes."
      echo "Meaning: Reachability is unconfirmed. This alone does not prove a local connection failure."
      echo "Next: Reconnect Wi-Fi, renew DHCP, or try another SSID/hotspot."
      ;;
    *) warn "Gateway status unknown." ;;
  esac
}

explain_egress(){
  hdr "Internet egress (can traffic leave this network?)"
  case "$EGRESS_STATUS" in
    ok)
      ok "At least one tested public service port answered."
      echo "Meaning: Some outbound traffic works. Browsing, VPNs and other services need their own checks."
      ;;
    blocked)
      fail "Common outbound ports 53/80/443 look filtered."
      echo "Meaning: These probes did not get a clear answer. A firewall or login page is possible, not confirmed."
      echo "Next: Open a browser for a login page, switch SSID, or use a different uplink (e.g., phone hotspot)."
      ;;
    *) warn "Egress status unknown." ;;
  esac
}

explain_dns(){
  hdr "DNS (names → IP addresses)"
  case "$DNS_STATUS" in
    ok)
      ok "DNS lookups succeeded."
      echo "Meaning: The tested name resolved; website access is a separate check."
      ;;
    fail)
      warn "DNS lookups failed."
      echo "Meaning: You might reach the internet by IP, but names won’t resolve."
      echo "Next: Compare configured and public resolvers with net-tools advnetcheck."
      ;;
    skipped)
      warn "DNS test skipped."
      echo "Reason: 'dig' is not installed. Run net-tools toolscan to check tools."
      ;;
  esac
}

explain_lan(){
  hdr "Local network (who else is here)"
  echo "Approximate devices seen on LAN: $LAN_PEERS"
  if [[ "$LAN_PEERS" == "1" || "$LAN_PEERS" == "0" ]]; then
    echo "Meaning: Few devices answered; isolation, sleeping devices or a small LAN can produce this count."
  else
    echo "Meaning: This is a discovery count, not a congestion or security measurement."
  fi
}

state_of_parts(){
  hdr "State of the system's parts (plain English)"
  echo "- Router probe: $GW_STATUS"
  echo "- Public service probes: $EGRESS_STATUS"
  echo "- Name resolution (DNS): $(case $DNS_STATUS in ok) echo 'working';; fail) echo 'failing';; *) echo 'unknown';; esac)"
  echo "- LAN visibility: $LAN_PEERS device(s) detected"
  echo
  local router=unknown public=unknown dns=unknown
  case "$GW_STATUS" in icmp_ok|arp_only) router=yes;; esac
  [[ $EGRESS_STATUS != ok ]] || public=yes
  case "$DNS_STATUS" in ok) dns=yes;; fail) dns=no;; esac
  report_connection_tldr "$router" "$public" "$dns" unknown skipped 'net-tools advnetcheck'

}

# ---------- PRINT EXPLANATIONS ----------
explain_gateway
explain_egress
explain_dns
explain_lan
state_of_parts

# Suggest deeper run if anything is off
if [[ "$GW_STATUS" != "icmp_ok" || "$EGRESS_STATUS" != "ok" || "$DNS_STATUS" != "ok" ]]; then
  echo
  echo "Next: run net-tools advnetcheck for path, port and DNS comparisons."
fi
