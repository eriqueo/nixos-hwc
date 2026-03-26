#!/usr/bin/env bash
set -Eeuo pipefail

# --- UI helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
say(){ printf "%b%s%b\n" "$1" "$2" "$NC"; }
ok(){ say "$GREEN" "OK  - $1"; }
warn(){ say "$YELLOW" "WARN- $1"; }
fail(){ say "$RED" "FAIL- $1"; }
hdr(){ printf "\n${BOLD}%s${NC}\n" "$1"; }

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

hdr "QuickNet — fast triage"
echo "IFACE=$IFACE  IP=$IP  GW=$GW  SCAN=$SUB24"

# === 1) Gateway reachability ===
if ping -c1 -W1 "$GW" >/dev/null 2>&1; then
  ok "Gateway replies to ICMP"
  GW_STATUS="icmp_ok"
elif have arping && sudo arping -c1 -w2 "$GW" >/dev/null 2>&1; then
  warn "Gateway reachable by ARP (ICMP blocked)"
  GW_STATUS="arp_only"
else
  fail "Gateway unreachable"
  GW_STATUS="unreachable"
fi

# === 2) Public egress sanity (53/80/443) ===
NMAP_OPTS=(-Pn --max-retries 1 --host-timeout 6s -T4)
PUB_OUT="$(sudo nmap "${NMAP_OPTS[@]}" -p 53,80,443 1.1.1.1 8.8.8.8 2>/dev/null | sed -n '1,120p')"
echo "$PUB_OUT"

# Decide egress: if all three ports appear filtered in the combined output → blocked
if grep -qE '53/tcp\s+filtered'  <<<"$PUB_OUT" && \
   grep -qE '80/tcp\s+filtered'  <<<"$PUB_OUT" && \
   grep -qE '443/tcp\s+filtered' <<<"$PUB_OUT"; then
  EGRESS_STATUS="blocked"
else
  EGRESS_STATUS="ok"
fi

# === 3) DNS quick test ===
if [[ "$EGRESS_STATUS" == "ok" ]] && have dig; then
  if timeout 3 dig +short google.com >/dev/null 2>&1; then
    DNS_STATUS="ok"
  else
    DNS_STATUS="fail"
  fi
fi

# === 4) LAN peers (quick count) ===
if have arp-scan; then
  LAN_PEERS="$(sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null | grep -cE '^[0-9]+\.[0-9]+')"
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
      echo "Meaning: You are connected to the same LAN, but the router blocks ICMP. That’s a policy choice, not a failure."
      ;;
    unreachable)
      fail "Your computer cannot reach the router."
      echo "Meaning: Local connection problem (wrong network/credentials, DHCP lease expired, or the AP is misbehaving)."
      echo "Next: Reconnect Wi-Fi, renew DHCP, or try another SSID/hotspot."
      ;;
    *) warn "Gateway status unknown." ;;
  esac
}

explain_egress(){
  hdr "Internet egress (can traffic leave this network?)"
  case "$EGRESS_STATUS" in
    ok)
      ok "Key internet ports (DNS/HTTP/HTTPS) are reachable."
      echo "Meaning: The network lets outbound traffic through. If something fails, it’s likely app/site-specific."
      ;;
    blocked)
      fail "Common outbound ports 53/80/443 look filtered."
      echo "Meaning: Guest/quarantine VLAN or a captive portal is blocking you."
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
      echo "Meaning: Name resolution works; websites should load by name."
      ;;
    fail)
      warn "DNS lookups failed."
      echo "Meaning: You might reach the internet by IP, but names won’t resolve."
      echo "Next: Temporarily set resolvers (e.g., 1.1.1.1, 8.8.8.8) with resolvectl or NetworkManager."
      ;;
    skipped)
      warn "DNS test skipped."
      echo "Reason: Either egress is blocked or 'dig' isn’t installed."
      ;;
  esac
}

explain_lan(){
  hdr "Local network (who else is here)"
  echo "Approximate devices seen on LAN: $LAN_PEERS"
  if [[ "$LAN_PEERS" == "1" || "$LAN_PEERS" == "0" ]]; then
    echo "Meaning: Likely client isolation (typical for hotspots/guest Wi-Fi). Only the router is visible."
  else
    echo "Meaning: Multiple devices share this LAN. Normal at home/work; noisy cafés can be crowded."
  fi
}

state_of_parts(){
  hdr "State of the system's parts (plain English)"
  echo "- Wi-Fi/Local link: $(case $GW_STATUS in icmp_ok) echo 'healthy';; arp_only) echo 'connected (router blocks ping)';; unreachable) echo 'broken';; *) echo 'unknown';; esac)"
  echo "- Router → Internet: $( [[ $EGRESS_STATUS == ok ]] && echo 'open' || echo 'blocked' )"
  echo "- Name resolution (DNS): $(case $DNS_STATUS in ok) echo 'working';; fail) echo 'failing';; *) echo 'unknown';; esac)"
  echo "- LAN visibility: $LAN_PEERS device(s) detected"
  echo
  # Overall verdict
  if [[ "$GW_STATUS" == "icmp_ok" && "$EGRESS_STATUS" == "ok" && "$DNS_STATUS" == "ok" ]]; then
    ok "Overall: healthy connection."
    echo "If you still see issues, they’re likely app/site-specific or performance-related."
  elif [[ "$GW_STATUS" == "unreachable" ]]; then
    fail "Overall: local connection issue."
    echo "Try reconnecting Wi-Fi, renewing DHCP, or switching networks."
  elif [[ "$EGRESS_STATUS" == "blocked" ]]; then
    fail "Overall: network is blocking outbound traffic."
    echo "Look for captive portals or use an alternate uplink."
  elif [[ "$DNS_STATUS" == "fail" ]]; then
    warn "Overall: DNS problem."
    echo "Set known-good resolvers (1.1.1.1, 8.8.8.8) and retest."
  else
    warn "Overall: inconclusive."
    echo "Run the deeper tool: sudo ./advnetcheck2.sh"
  fi
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
  echo "→ For deeper diagnostics (path, ports, DNS matrix), run: sudo ./advnetcheck2.sh"
fi
