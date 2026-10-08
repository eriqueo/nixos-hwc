#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=network-report.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/network-report.sh"
report_init 'Detailed connection check' 'Compare router reachability, internet paths, DNS and visible LAN devices.' \
  'Sends active router and LAN scans; may request sudo.' '[--details]' "$@" || exit 0
set -- "${REPORT_ARGS[@]}"
PUB_OUT=''; LAN_PEERS='unknown'; SYSTEM_DNS='unknown'
ROUTER_REPLY=unknown; ALT_DNS=unknown; DNS_MATRIX_MISSING=0

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

  report_section 'Network setup' 'Find the active adapter, local address and default router.' \
    'The default route selects where outbound traffic goes. VPN routes can differ.'
  info "Interface : $IFACE"
  info "IP/CIDR  : $MYCIDR"
  info "Gateway  : $GATEWAY"
  info "Scan blk : $SUB24"

  report_section 'Services on this computer' 'List local listening sockets.' \
    '127.0.0.1 is local-only; 0.0.0.0 or [::] listens on all addresses. Firewall rules still control access.'
  if have ss; then ss -tulpn 2>/dev/null | report_evidence || true; else warn "ss not available"; fi

  report_section 'Configured DNS' 'Read the adapter DNS settings.' \
    'These servers translate website names into addresses. Configuration alone does not prove they answer.'
  if have resolvectl; then
    resolvectl status "$IFACE" 2>/dev/null | report_evidence || true
    mapfile -t DNS_ACTIVE < <(resolvectl dns "$IFACE" 2>/dev/null | awk '{sub(/^[^:]*:[[:space:]]*/, ""); for(i=1;i<=NF;i++)print $i}')
  else
    warn "resolvectl not available"
  fi
}

# ===== Phase 1: Reachability & egress policy =====
phase1() {
  report_section '1. Router reachability' 'Try ARP, ping and common router service ports.' \
    'Replies confirm a path. No ping reply can be filtering; a filtered port does not prove reachability.'

  printf "Gateway ARP/ICMP: "
  if have arping; then
    if sudo arping -c 1 -w 2 "$GATEWAY" >/dev/null 2>&1; then ROUTER_REPLY=yes; ok "ARP OK"; else warn "no ARP reply"; fi
  fi
  if ping -c1 -W1 "$GATEWAY" >/dev/null 2>&1; then ROUTER_REPLY=yes; ok "Ping answered"; else warn "No ping reply; cause unconfirmed"; fi

  printf "Gateway TCP probes: "
  local gw_tcp_ok=0
  if have nmap; then
    if sudo nmap -Pn -p 80,443,53 --host-timeout 5s "$GATEWAY" 2>/dev/null | awk '$2 == "open" {found=1} END {exit !found}'; then
      ok "A router service port answered"; gw_tcp_ok=1; ROUTER_REPLY=yes
    else
      warn "no service ports visible"
    fi
  else
    warn "nmap not present"
  fi

  report_section '2. Public service access' 'Probe TCP DNS, HTTP and HTTPS ports on two public hosts.' \
    'A response confirms only the tested destination and service. Timeout means unconfirmed.'
  report_port_legend
  if have nmap; then
    PUB_OUT=$(sudo nmap -Pn -p 53,80,443 --host-timeout 6s 8.8.8.8 1.1.1.1 2>&1 || true)
    printf '%s\n' "$PUB_OUT" | report_evidence
  else
    warn "nmap not present"
  fi

  report_section '3. Internet path' 'Send three MTR probes, or use traceroute.' \
    'Each hop is a router on the path; missing replies are not necessarily dropped user traffic.'
  report_path_legend
  if have mtr; then
    mtr -r -c 3 --no-dns 8.8.8.8 | report_evidence || true
  else
    if have traceroute; then traceroute -n 8.8.8.8 | report_evidence || true; else warn "mtr/traceroute not present"; fi
  fi
}

# ===== Phase 2: DNS truth table =====
phase2_dns() {
  report_section '4. Compare DNS answers' 'Ask configured and public resolvers for three website addresses.' \
    'OK means an address was returned. NO ANSWER can mean filtering, timeout or missing DNS data.' \
    'If public resolvers work but configured DNS fails, inspect the connection DNS settings.'
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
        if report_dns_answer @"$s" "$n"; then
          case "$s" in 1.1.1.1|8.8.8.8|9.9.9.9) ALT_DNS=yes;; esac
          printf "%-18s" "OK"; else DNS_MATRIX_MISSING=$((DNS_MATRIX_MISSING+1)); printf "%-18s" "NO ANSWER"; fi
      done
      printf "\n"
    done
    if report_dns_answer google.com; then SYSTEM_DNS=yes; ok 'The system resolver also returned an address.'; else SYSTEM_DNS=no; warn 'The system resolver returned no address.'; fi
  else
    warn "dig not present"
  fi
}

# ===== Phase 3: L2/LAN visibility =====
phase3_l2() {
  report_section '5. Visible local devices' 'Discover devices on the local network.' \
    'A low count can mean isolation, sleeping devices or few devices. Discovery does not identify every device.'
  need_sudo
  if have "arp-scan"; then
    local out
    if out=$(sudo arp-scan --interface "$IFACE" --localnet 2>&1); then
      LAN_PEERS=$(awk '/^[0-9]+\.[0-9]+/{n++} END{print n+0}' <<< "$out")
      printf '%s\n' "$out" | report_evidence
    else warn 'ARP discovery failed; device count is unknown.'; fi
  elif have nmap; then
    local out
    if out=$(sudo nmap -sn "$SUB24" 2>&1); then
      LAN_PEERS=$(awk '/Nmap scan report/{n++} END{print n+0}' <<< "$out")
      printf '%s\n' "$out" | report_evidence
    else warn 'Host discovery failed; device count is unknown.'; fi
  else
    warn "arp-scan/nmap not present"
  fi
}

# ===== Phase 4: Gateway fingerprint (safe) =====
phase4_gateway() {
  report_section '6. Router service ports' 'Probe the 100 most common TCP ports on the router.' \
    'Service names are port-based guesses here. This scan does not verify versions or vulnerabilities.' \
    'Review unexpected services in the router settings; keep firmware current.'
  report_port_legend
  if have nmap; then
    sudo nmap -Pn --top-ports 100 --open --max-retries 2 --host-timeout 15s "$GATEWAY" 2>/dev/null \
      | report_evidence || warn 'Router scan failed or timed out.'
  else
    warn "nmap not present"
  fi
}

# ===== Phase 5: Summary verdict =====
verdict() {
  bold "=== Summary Verdict ==="
  local eg_ok="unconfirmed" dns_ok="$SYSTEM_DNS" lan_peers="$LAN_PEERS"

  if awk '$1 ~ /^(53|80|443)\/tcp$/ && $2 == "open" {found=1} END {exit !found}' <<< "$PUB_OUT"; then eg_ok=yes; fi

  [[ "$eg_ok" == "yes" ]] && ok 'At least one public service port answered.' || warn 'Public service access is unconfirmed.'
  [[ "$dns_ok" == "yes" ]] && ok 'System DNS returned an address.' || warn "System DNS answer: $dns_ok"
  info "LAN peers seen (approx): ${lan_peers}"

  [[ "$eg_ok" == yes ]] || eg_ok=unknown
  report_connection_tldr "$ROUTER_REPLY" "$eg_ok" "$SYSTEM_DNS" "$ALT_DNS" skipped 'net-tools advnetcheck' "$DNS_MATRIX_MISSING"
  info "Visible LAN devices: $LAN_PEERS. Router ports above describe LAN access, not WAN exposure."

  [[ $HAD_SUDO -eq 1 ]] && echo "(sudo was used for some probes)"
  return 0
}

# ===== Main =====
main() {
  info "Started: $(date)"
  discover
  phase1
  phase2_dns
  phase3_l2
  phase4_gateway
  verdict
}
main "$@"
