#!/usr/bin/env bash
set -euo pipefail

# ===== UI =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
bold(){ printf "\n${BOLD}%s${NC}\n" "$*"; }
info(){ printf "%s\n" "$*"; }
warn(){ printf "${YELLOW}⚠ %s${NC}\n" "$*"; }
ok(){ printf "${GREEN}✓ %s${NC}\n" "$*"; }
fail(){ printf "${RED}✗ %s${NC}\n" "$*"; }

HAD_SUDO=0
need_sudo() { if [[ $EUID -ne 0 ]]; then HAD_SUDO=1; sudo -v || true; fi; }

# ===== Globals =====
IFACE=""; GATEWAY=""; MYCIDR=""; MYIP=""; SUB24=""; DNS_ACTIVE=(); DNS_ALT=(1.1.1.1 8.8.8.8 9.9.9.9)

have(){ command -v "$1" >/dev/null 2>&1; }

# ===== Discover network =====
discover() {
  local def
  def=$(ip route show default | head -n1 || true)
  if [[ -z "$def" ]]; then fail "No default route"; exit 1; fi
  IFACE=$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$def")
  GATEWAY=$(awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<<"$def")
  MYCIDR=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | head -1)
  MYIP=${MYCIDR%%/*}
  if have ipcalc; then
    local net; net=$(ipcalc -n "$MYCIDR" 2>/dev/null | cut -d= -f2 || true)
    SUB24="${net%.*}.0/24"
  else
    # fall back: assume /24
    SUB24="$(cut -d. -f1-3 <<<"$MYIP").0/24"
  fi

  bold "=== Interface & Route ==="
  info "Interface : $IFACE"
  info "IP/CIDR  : $MYCIDR"
  info "Gateway  : $GATEWAY"
  info "Scan blk : $SUB24"

  bold "=== Sockets (listeners) ==="
  if have ss; then ss -tulpn 2>/dev/null | head -20 || true; else warn "ss not available"; fi

  bold "=== DNS (systemd-resolved) ==="
  if have resolvectl; then
    resolvectl status "$IFACE" 2>/dev/null | sed -n '1,60p' || resolvectl status | sed -n '1,60p' || true
    mapfile -t DNS_ACTIVE < <(resolvectl dns "$IFACE" 2>/dev/null | awk '{for(i=3;i<=NF;i++)print $i}')
  else
    warn "resolvectl not available"
  fi
}

# ===== Phase 1: Reachability & egress policy =====
phase1() {
  bold "=== Phase 1: Basic Reachability & Egress ==="

  printf "Gateway ARP/ICMP: "
  if have arping; then
    if sudo arping -c 1 -w 2 "$GATEWAY" >/dev/null 2>&1; then ok "ARP OK"; else warn "no ARP reply"; fi
  fi
  if ping -c1 -W1 "$GATEWAY" >/dev/null 2>&1; then ok "ICMP OK"; else warn "ICMP blocked"; fi

  printf "Gateway TCP probes: "
  local gw_tcp_ok=0
  if have nmap; then
    if sudo nmap -Pn -p 80,443,53 --host-timeout 5s "$GATEWAY" 2>/dev/null | grep -qE "open|filtered"; then
      ok "reachable (some ports open/filtered)"; gw_tcp_ok=1
    else
      warn "no service ports visible"
    fi
  else
    warn "nmap not present"
  fi

  bold "Public egress (8.8.8.8/1.1.1.1 ports 53/80/443)"
  if have nmap; then
    sudo nmap -Pn -p 53,80,443 --host-timeout 6s 8.8.8.8 1.1.1.1 2>/dev/null \
      | sed -n '1,80p'
  else
    warn "nmap not present"
  fi

  bold "Traceroute/MTR (first hops)"
  if have mtr; then
    mtr -r -c 3 --no-dns 8.8.8.8 | sed -n '1,12p' || true
  else
    if have traceroute; then traceroute -n 8.8.8.8 | sed -n '1,12p' || true; else warn "mtr/traceroute not present"; fi
  fi
}

# ===== Phase 2: DNS truth table =====
phase2_dns() {
  bold "=== Phase 2: DNS Resolution Matrix ==="
  local names=(google.com cloudflare.com example.com)
  local servers=()

  if ((${#DNS_ACTIVE[@]})); then servers=("${DNS_ACTIVE[@]}"); fi
  servers+=("${DNS_ALT[@]}")
  # de-dup
  local uniq=(); declare -A seen=()
  for s in "${servers[@]}"; do [[ -z ${seen[$s]+x} ]] && uniq+=("$s") && seen[$s]=1; done
  servers=("${uniq[@]}")

  if have dig; then
    printf "%-18s" "Server"
    for n in "${names[@]}"; do printf "%-18s" "$n"; done; printf "\n"
    for s in "${servers[@]}"; do
      printf "%-18s" "$s"
      for n in "${names[@]}"; do
        if timeout 3 dig @"$s" +short "$n" A >/dev/null 2>&1; then printf "%-18s" "OK"; else printf "%-18s" "FAIL"; fi
      done
      printf "\n"
    done
  else
    warn "dig not present"
  fi
}

# ===== Phase 3: L2/LAN visibility =====
phase3_l2() {
  bold "=== Phase 3: LAN Visibility (who else is alive) ==="
  need_sudo
  if have "arp-scan"; then
    sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null \
      | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]+([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/{print $1, $2, $3}' \
      | head -20 || true
  elif have nmap; then
    sudo nmap -sn "$SUB24" 2>/dev/null | grep -E 'Nmap scan report|MAC Address' | head -20 || true
  else
    warn "arp-scan/nmap not present"
  fi
}

# ===== Phase 4: Gateway fingerprint (safe) =====
phase4_gateway() {
  bold "=== Phase 4: Gateway Fingerprint (top ports + banner) ==="
  if have nmap; then
    sudo nmap -Pn --top-ports 100 --open --max-retries 2 --host-timeout 15s "$GATEWAY" 2>/dev/null \
      | sed -n '1,120p' || true
  else
    warn "nmap not present"
  fi
}

# ===== Phase 5: Summary verdict =====
verdict() {
  bold "=== Summary Verdict ==="
  local eg_ok="unknown" dns_ok="unknown" lan_peers="unknown"

  # egress inference: use nmap cached exit code if possible; otherwise quick ping
  if have nmap; then
    if sudo nmap -Pn -p 53,80,443 --host-timeout 6s 8.8.8.8 >/dev/null 2>&1; then
      # Not reliable from exit code; check a port quickly
      if sudo nmap -Pn -p 443 --host-timeout 4s 1.1.1.1 2>/dev/null | grep -q "open"; then eg_ok="yes"; else eg_ok="no"; fi
    fi
  else
    if ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; then eg_ok="likely"; else eg_ok="no"; fi
  fi

  if have dig; then
    if timeout 3 dig +short google.com >/dev/null 2>&1; then dns_ok="yes"; else dns_ok="no"; fi
  fi

  if have "arp-scan"; then
    lan_peers=$(sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null | grep -cE '^[0-9]+\.[0-9]+')
  elif have nmap; then
    lan_peers=$(sudo nmap -sn "$SUB24" 2>/dev/null | grep -c "Nmap scan report" || echo "0")
  fi

  [[ "$eg_ok" == "yes" || "$eg_ok" == "likely" ]] && ok "Public egress: $eg_ok" || fail "Public egress: $eg_ok"
  [[ "$dns_ok" == "yes" ]] && ok "DNS: working" || warn "DNS: $dns_ok"
  info "LAN peers seen (approx): ${lan_peers}"

  echo ""
  if [[ "$eg_ok" == "no" ]]; then
    warn "Egress blocked. Likely captive portal, ACL, or guest VLAN. Check first hop/firewall."
  elif [[ "$dns_ok" == "no" ]]; then
    warn "DNS failing. Try: resolvectl dns $IFACE 1.1.1.1 8.8.8.8"
  fi

  [[ $HAD_SUDO -eq 1 ]] && echo "(sudo was used for some probes)"
}

# ===== Main =====
main() {
  bold "🌐 netprobe (nmap/mtr/dig/arp-scan driven)"
  info "Started: $(date)"
  discover
  phase1
  phase2_dns
  phase3_l2
  phase4_gateway
  verdict
}
main "$@"
