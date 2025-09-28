#!/usr/bin/env bash
set -euo pipefail

# Ensure UTF-8 for proper SSID display
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# ===== UI =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
bold(){ printf "\n${BOLD}%s${NC}\n" "$*"; }
info(){ printf "%s\n" "$*"; }
warn(){ printf "${YELLOW}⚠ %s${NC}\n" "$*"; }
ok(){ printf "${GREEN}✓ %s${NC}\n" "$*"; }
fail(){ printf "${RED}✗ %s${NC}\n" "$*"; }
explain(){ printf "${BLUE}💡 %s${NC}\n" "$*"; }

HAD_SUDO=0
need_sudo() { if [[ $EUID -ne 0 ]]; then HAD_SUDO=1; sudo -v || true; fi; }

# ===== Globals =====
IFACE=""; GATEWAY=""; MYCIDR=""; MYIP=""; SUB24=""; DNS_ACTIVE=(); DNS_ALT=(1.1.1.1 8.8.8.8 9.9.9.9)
GW_PING_OK=0; GW_TCP_OK=0; INTERNET_OK=0; DNS_OK=0; CAPTIVE_PORTAL=0; DO_PERF=0
PUB_NMAP_OUT=""

# Fast nmap options for hostile networks
NMAP_FAST=(-Pn --max-retries 1 --host-timeout 6s -T4)

have(){ command -v "$1" >/dev/null 2>&1; }

egress_blocked() {
    # Check if common egress ports are filtered
    grep -qE '53/tcp\s+filtered' <<<"$PUB_NMAP_OUT" &&
    grep -qE '80/tcp\s+filtered' <<<"$PUB_NMAP_OUT" &&
    grep -qE '443/tcp\s+filtered' <<<"$PUB_NMAP_OUT"
}

# ===== Quick Triage (30 seconds max) =====
quick_triage() {
    bold "🚀 QUICK TRIAGE - Is your connection working?"
    explain "This tests the basics in 30 seconds to tell you if it's your problem or the network's problem"
    
    echo -n "Testing gateway (your router): "
    if timeout 3 ping -c 1 -W 1 "$GATEWAY" >/dev/null 2>&1; then
        ok "Can reach gateway"
        GW_PING_OK=1
    elif timeout 5 bash -c "</dev/tcp/$GATEWAY/80" 2>/dev/null; then
        warn "Gateway blocks ping but is reachable"
        GW_PING_OK=1
    else
        fail "Cannot reach gateway at all"
        GW_PING_OK=0
    fi
    
    echo -n "Testing internet (bypassing DNS): "
    if timeout 5 bash -c "</dev/tcp/8.8.8.8/53" 2>/dev/null; then
        ok "Internet connection works"
        INTERNET_OK=1
    else
        fail "No internet access"
        INTERNET_OK=0
    fi
    
    echo -n "Testing DNS resolution: "
    if timeout 3 nslookup google.com 8.8.8.8 >/dev/null 2>&1; then
        ok "DNS works"
        DNS_OK=1
    else
        fail "DNS broken"
        DNS_OK=0
    fi
    
    echo -n "Testing for captive portal: "
    if timeout 5 curl -s --connect-timeout 3 http://detectportal.firefox.com/canonical.html 2>/dev/null | grep -q "success"; then
        ok "No captive portal"
        CAPTIVE_PORTAL=0
    else
        warn "Possible captive portal detected"
        CAPTIVE_PORTAL=1
    fi
    
    # Quick verdict
    triage_verdict
}

triage_verdict() {
    bold "📊 QUICK VERDICT"
    
    if [[ $GW_PING_OK -eq 0 ]]; then
        fail "❌ YOUR CONNECTION IS BROKEN"
        explain "Problem: Can't reach your router/gateway"
        echo "🔧 What this means:"
        echo "  • Your WiFi might be disconnected"
        echo "  • Your network cable might be unplugged"
        echo "  • Your network interface might be down"
        echo ""
        echo "🛠️ Try these fixes:"
        echo "  1. sudo systemctl restart NetworkManager"
        echo "  2. Check WiFi connection: iwconfig $IFACE"
        echo "  3. Reconnect to WiFi network"
        return 1
        
    elif [[ $INTERNET_OK -eq 0 ]]; then
        if [[ $CAPTIVE_PORTAL -eq 1 ]]; then
            warn "🌐 CAPTIVE PORTAL DETECTED"
            explain "Problem: Connected to WiFi but need to login through web browser"
            echo "🔧 What this means:"
            echo "  • Hotel/coffee shop WiFi requiring login"
            echo "  • Guest network with terms to accept"
            echo "  • Corporate network requiring authentication"
            echo ""
            echo "🛠️ Try these fixes:"
            echo "  1. Open web browser and go to any website"
            echo "  2. You should be redirected to login page"
            echo "  3. Or try: firefox http://$GATEWAY &"
        else
            fail "❌ INTERNET/ISP PROBLEM"
            explain "Problem: Router works but internet is down - NOT YOUR FAULT"
            echo "🔧 What this means:"
            echo "  • ISP outage or maintenance"
            echo "  • Router's internet connection failed"
            echo "  • Network firewall blocking traffic"
            echo ""
            echo "🛠️ Try these fixes:"
            echo "  1. Test with phone on same WiFi"
            echo "  2. Contact network admin or ISP"
            echo "  3. Try mobile hotspot to confirm"
        fi
        return 1
        
    elif [[ $DNS_OK -eq 0 ]]; then
        warn "🔍 DNS PROBLEM"
        explain "Problem: Internet works but can't translate website names to IP addresses"
        echo "🔧 What this means:"
        echo "  • Can reach websites by IP address (like 8.8.8.8)"
        echo "  • Cannot reach websites by name (like google.com)"
        echo "  • Your DNS servers are down or misconfigured"
        echo ""
        echo "🛠️ Try these fixes:"
        echo "  1. sudo resolvectl dns $IFACE 8.8.8.8 1.1.1.1"
        echo "  2. Or: echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
        echo "  3. Test: nslookup google.com"
        return 1
        
    else
        ok "✅ BASIC CONNECTIVITY LOOKS GOOD"
        explain "All quick tests passed! If you're still having problems, it's likely:"
        echo "  • Specific website issues"
        echo "  • Application-specific problems"
        echo "  • Performance/speed issues"
        echo ""
        echo "Continuing with detailed analysis..."
        return 0
    fi
}

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

    bold "=== 📡 Your Network Setup ==="
    info "Interface : $IFACE (your network card)"
    info "Your IP   : $MYIP (your computer's address)"
    info "Gateway   : $GATEWAY (your router's address)"
    info "Scan range: $SUB24 (local network to scan)"
    
    # Add WiFi info if wireless
    if [[ "$IFACE" =~ ^wl ]]; then
        explain "This is a WiFi connection"
        if have iwconfig; then
            echo "WiFi details:"
            iwconfig "$IFACE" 2>/dev/null | grep -E 'ESSID|Frequency|Access Point|Signal level|Bit Rate' || true
        fi
        if have iw; then
            echo "Current WiFi connection:"
            iw dev "$IFACE" link 2>/dev/null | grep -E 'SSID|freq|signal|bitrate' || true
        fi
    else
        explain "This is a wired (Ethernet) connection"
    fi

    bold "=== 🔌 What's Running on Your Computer ==="
    explain "These are network services your computer is listening for (like web servers, SSH, etc.)"
    if have ss; then 
        ss -tulpn 2>/dev/null | head -10 || true
        echo "  (Showing first 10 services - 't'=TCP, 'u'=UDP, 'l'=listening)"
    else 
        warn "ss not available"
    fi

    bold "=== 🌐 DNS Configuration ==="
    explain "DNS translates website names (google.com) into IP addresses (172.217.164.142)"
    if have resolvectl; then
        echo "Current DNS settings:"
        resolvectl status "$IFACE" 2>/dev/null | sed -n '1,60p' || resolvectl status | sed -n '1,60p' || true
        
        # Fixed DNS collection - only collect valid IPs
        DNS_ACTIVE=()
        if command -v resolvectl >/dev/null 2>&1; then
            mapfile -t DNS_ACTIVE < <(
                resolvectl status "$IFACE" 2>/dev/null \
                  | awk '/^\s*DNS Servers:/{for(i=3;i<=NF;i++) print $i}'
            )
        fi
        
        # Drop unscoped IPv6 link-local (dig would need %IFACE)
        DNS_ACTIVE=($(printf "%s\n" "${DNS_ACTIVE[@]}" | awk '!/^fe80::/'))
        
        if ((${#DNS_ACTIVE[@]})); then
            info "Active DNS servers: ${DNS_ACTIVE[*]}"
            # Show which DNS is currently being used
            resolvectl status "$IFACE" 2>/dev/null | awk '/Current DNS Server:/{print}' || true
        else
            warn "No DNS servers configured for this interface"
        fi
    else
        warn "resolvectl not available - using /etc/resolv.conf"
        cat /etc/resolv.conf 2>/dev/null | grep nameserver || warn "No DNS configuration found"
    fi
}

# ===== Phase 1: Reachability & egress policy =====
phase1() {
    bold "=== 📋 Phase 1: Router Reachability & Internet Access ==="
    explain "Testing if you can reach your router and if your router can reach the internet"

    echo "🔍 Testing your router ($GATEWAY):"
    printf "  ARP test (hardware-level): "
    if have arping; then
        if sudo arping -c 1 -w 2 "$GATEWAY" >/dev/null 2>&1; then 
            ok "Router responds at hardware level"
        else 
            warn "No ARP reply (router might be down)"
        fi
    else
        info "arping not available"
    fi
    
    printf "  Ping test (network-level): "
    if ping -c1 -W1 "$GATEWAY" >/dev/null 2>&1; then 
        ok "Router responds to ping"
        GW_PING_OK=1
    else 
        warn "Router blocks ping (normal security)"
        GW_PING_OK=0
    fi

    printf "  Service ports test: "
    if have nmap; then
        echo ""
        explain "Checking if router has web interface or other services running"
        sudo nmap -Pn -p 80,443,53,22,23 --host-timeout 5s "$GATEWAY" 2>/dev/null | grep -E "(open|filtered|Port)"
        if sudo nmap -Pn -p 80,443,53 --host-timeout 5s "$GATEWAY" 2>/dev/null | grep -qE "open|filtered"; then
            GW_TCP_OK=1
        fi
    else
        warn "nmap not available"
    fi

    bold "🌍 Testing Internet Access"
    explain "Checking if you can reach major internet services (Google DNS, Cloudflare)"
    if have nmap; then
        echo "Testing connections to 8.8.8.8 (Google) and 1.1.1.1 (Cloudflare):"
        PUB_NMAP_OUT=$(sudo nmap "${NMAP_FAST[@]}" -p 53,80,443 8.8.8.8 1.1.1.1 2>/dev/null)
        echo "$PUB_NMAP_OUT" | grep -E "(Nmap scan report|53/tcp|80/tcp|443/tcp)" || warn "No internet access detected"
        
        # Set INTERNET_OK based on results
        if echo "$PUB_NMAP_OUT" | grep -q "443/tcp.*open"; then
            INTERNET_OK=1
        fi
    else
        warn "nmap not available"
        # Fallback to ping
        if ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; then
            ok "Can ping Google DNS (8.8.8.8)"
            INTERNET_OK=1
        else
            warn "Cannot reach internet"
        fi
    fi

    bold "🛣️ Path to Internet (Traceroute)"
    explain "Shows the route your data takes to reach the internet"
    if have mtr; then
        echo "Using MTR (shows packet loss and latency):"
        timeout 30 mtr -r -c 3 --no-dns 8.8.8.8 | sed -n '1,12p' || warn "MTR timeout"
        explain "Each line shows a 'hop' - a router your data passes through. '???' is normal for carrier networks."
    else
        if have traceroute; then 
            echo "Using traceroute:"
            timeout 30 traceroute -n 8.8.8.8 | sed -n '1,12p' || warn "Traceroute timeout"
        else 
            warn "mtr/traceroute not available"
        fi
    fi
}

# ===== Phase 2: DNS truth table =====
phase2_dns() {
    bold "=== 🔍 Phase 2: DNS Testing Matrix ==="
    explain "Testing different DNS servers to see which ones work"
    explain "DNS translates 'google.com' into IP addresses like '172.217.164.142'"
    
    # Check if egress is blocked before doing DNS tests
    if [[ -n "$PUB_NMAP_OUT" ]] && egress_blocked; then
        warn "DNS Matrix: skipped (egress on 53/80/443 is blocked by the network)"
        explain "The network is blocking outbound connections, so DNS tests would fail anyway"
        DNS_OK=0
        return
    fi
    
    local names=(google.com cloudflare.com example.com)
    local servers=()

    if ((${#DNS_ACTIVE[@]})); then servers=("${DNS_ACTIVE[@]}"); fi
    servers+=("${DNS_ALT[@]}")
    # de-dup
    local uniq=(); declare -A seen=()
    for s in "${servers[@]}"; do [[ -z ${seen[$s]+x} ]] && uniq+=("$s") && seen[$s]=1; done
    servers=("${uniq[@]}")

    if have dig; then
        echo "DNS Test Results:"
        printf "%-20s" "DNS Server"
        for n in "${names[@]}"; do printf "%-18s" "$n"; done; printf "\n"
        printf "%-20s" "----------"
        for n in "${names[@]}"; do printf "%-18s" "--------"; done; printf "\n"
        
        local any_dns_working=0
        for s in "${servers[@]}"; do
            printf "%-20s" "$s"
            local this_server_working=0
            for n in "${names[@]}"; do
                if timeout 3 dig @"$s" +short "$n" A >/dev/null 2>&1; then 
                    printf "%-18s" "✓ OK"
                    any_dns_working=1
                    this_server_working=1
                else 
                    printf "%-18s" "✗ FAIL"
                fi
            done
            if [[ $this_server_working -eq 1 ]]; then
                echo " ← This DNS server works!"
            else
                echo " ← This DNS server is broken"
            fi
        done
        
        if [[ $any_dns_working -eq 1 ]]; then
            DNS_OK=1
            explain "✅ At least one DNS server is working"
        else
            DNS_OK=0
            explain "❌ All DNS servers failed - this indicates network egress filtering"
        fi
    else
        warn "dig not available - cannot test DNS properly"
        # Fallback test
        if timeout 3 nslookup google.com >/dev/null 2>&1; then
            ok "Basic DNS test passed"
            DNS_OK=1
        else
            fail "Basic DNS test failed"
            DNS_OK=0
        fi
    fi
}

# ===== Phase 3: L2/LAN visibility =====
phase3_l2() {
    bold "=== 👥 Phase 3: Who Else is on Your Network ==="
    explain "Scanning your local network to see what other devices are connected"
    explain "This helps identify if you're on a busy network or if client isolation is enabled"
    
    need_sudo
    echo "Scanning network $SUB24 for active devices..."
    
    if have arp-scan; then
        echo "Using ARP scan (most reliable method):"
        # Fixed ARP scan formatting
        sudo arp-scan --interface "$IFACE" --localnet --retry=2 --timeout=200 2>/dev/null | \
            awk 'match($0,/^([0-9.]+)[ \t]+(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})[ \t]+(.+)$/,m){printf "  %-15s %-17s %s\n", m[1], m[2], m[4]}' || \
            warn "ARP scan failed"
    elif have nmap; then
        echo "Using nmap host discovery:"
        local hosts_found=0
        while IFS= read -r line; do
            if [[ $line =~ "Nmap scan report" ]]; then
                echo "  Device: $line"
                ((hosts_found++))
            elif [[ $line =~ "MAC Address" ]]; then
                echo "    $line"
            fi
        done < <(timeout 30 sudo nmap "${NMAP_FAST[@]}" -sn "$SUB24" 2>/dev/null | head -40)
        
        if [[ $hosts_found -le 2 ]]; then
            warn "Only found $hosts_found devices (including yourself)"
            explain "This might mean:"
            echo "  • Client isolation is enabled (devices can't see each other)"
            echo "  • Very quiet network with few devices"
            echo "  • Network security settings blocking discovery"
        else
            ok "Found $hosts_found devices on the network"
            explain "This looks like a normal, active network"
        fi
    else
        warn "arp-scan/nmap not available"
    fi
}

# ===== Phase 4: Gateway fingerprint (safe) =====
phase4_gateway() {
    bold "=== 🔍 Phase 4: Router Analysis ==="
    explain "Examining your router to identify what type it is and what services it offers"
    
    if have nmap; then
        echo "Scanning router $GATEWAY for open ports and services..."
        timeout 30 sudo nmap "${NMAP_FAST[@]}" --top-ports 100 --open "$GATEWAY" 2>/dev/null | \
            head -50 || warn "Gateway scan timeout/failed"
        
        echo ""
        echo "Looking for router web interface and common services..."
        if timeout 15 sudo nmap "${NMAP_FAST[@]}" -p 80,443,8080,8443 "$GATEWAY" 2>/dev/null | grep -q "open"; then
            ok "Router has web interface available"
            explain "You can probably access router settings at: http://$GATEWAY"
        else
            warn "No web interface found (might be disabled for security)"
        fi
        
        if timeout 10 sudo nmap "${NMAP_FAST[@]}" -p 22 "$GATEWAY" 2>/dev/null | grep -q "open"; then
            ok "SSH available (advanced users)"
        fi
        
        if timeout 10 sudo nmap "${NMAP_FAST[@]}" -p 23 "$GATEWAY" 2>/dev/null | grep -q "open"; then
            warn "Telnet available (insecure - avoid using)"
        fi
    else
        warn "nmap not available"
    fi
}

# Speed Test (non-interactive, flag-controlled)
run_perf() {
    bold "=== 🚀 Network Performance Tests ==="
    explain "Testing your network speed and performance"
    
    # Basic ping test for latency with tight timeouts
    echo "Latency (ms):"
    for h in "$GATEWAY" 1.1.1.1 8.8.8.8; do
        printf "  %-12s " "$h"
        ping -c 3 -W 1 "$h" 2>/dev/null | awk -F'/' '/^rtt|^round-trip/{printf "%.1f\n",$5}' || echo "timeout"
    done
    
    echo ""
    if have speedtest-cli; then
        echo "Running internet speed test..."
        timeout 60 speedtest-cli --simple 2>/dev/null || warn "Speed test timed out or failed"
    elif have fast-cli; then
        echo "Running Netflix speed test..."
        timeout 45 fast-cli --upload || warn "Netflix speed test failed"
    elif have iperf3; then
        echo "Throughput testing available with iperf3:"
        echo "  Run: iperf3 -c <server_ip> (requires iperf3 server)"
        explain "Contact your network admin for internal iperf3 server, or use public servers"
    else
        echo "For speed testing, consider installing:"
        echo "  • speedtest-cli: pip install speedtest-cli"
        echo "  • fast-cli: npm install --global fast-cli"
        echo "  • iperf3: Available in your system packages"
    fi
}

# ===== Phase 5: Summary verdict =====
verdict() {
    bold "=== 📊 FINAL DIAGNOSIS & RECOMMENDATIONS ==="
    
    local eg_ok="unknown" dns_ok="unknown" lan_peers="unknown"

    # Use our global variables from tests
    if [[ $INTERNET_OK -eq 1 ]]; then
        eg_ok="yes"
    elif [[ $INTERNET_OK -eq 0 ]]; then
        eg_ok="no"
    fi
    
    if [[ $DNS_OK -eq 1 ]]; then
        dns_ok="yes"
    elif [[ $DNS_OK -eq 0 ]]; then
        dns_ok="no"
    fi

    if have arp-scan; then
        lan_peers=$(sudo arp-scan --interface "$IFACE" --localnet 2>/dev/null | grep -cE '^[0-9]+\.[0-9]+' || echo "0")
    elif have nmap; then
        lan_peers=$(sudo nmap -sn "$SUB24" 2>/dev/null | grep -c "Nmap scan report" || echo "0")
    fi

    echo "🔍 Test Results Summary:"
    [[ "$eg_ok" == "yes" ]] && ok "✅ Internet access: Working" || fail "❌ Internet access: $eg_ok"
    [[ "$dns_ok" == "yes" ]] && ok "✅ DNS resolution: Working" || warn "⚠️ DNS resolution: $dns_ok"
    info "📱 Other devices visible: ${lan_peers} (low numbers may indicate client isolation)"
    [[ $GW_PING_OK -eq 1 ]] && ok "✅ Router connection: Good" || warn "⚠️ Router connection: Limited"

    echo ""
    bold "🎯 WHAT THIS MEANS FOR YOU:"
    
    if [[ "$eg_ok" == "yes" && "$dns_ok" == "yes" ]]; then
        ok "🎉 YOUR NETWORK IS WORKING PERFECTLY!"
        explain "All tests passed. If you're still having issues:"
        echo "  • Try different websites"
        echo "  • Check for application-specific problems"
        echo "  • Consider if it's a performance issue (run speed test)"
        
    elif [[ "$eg_ok" == "no" ]]; then
        if [[ $CAPTIVE_PORTAL -eq 1 ]]; then
            warn "🌐 CAPTIVE PORTAL ISSUE"
            echo "🔧 Next steps:"
            echo "  1. Open your web browser"
            echo "  2. Try to visit any website (like google.com)"
            echo "  3. You should be redirected to a login page"
            echo "  4. Complete the login or accept terms"
            echo "  5. Or try going directly to: http://$GATEWAY"
        else
            fail "🚨 INTERNET CONNECTION PROBLEM"
            echo "🔧 This is likely NOT your fault. Next steps:"
            echo "  1. Test with another device (phone, tablet) on same WiFi"
            echo "  2. If other devices also fail: contact network admin/ISP"
            echo "  3. If other devices work: restart your network interface"
            echo "     • sudo systemctl restart NetworkManager"
            echo "  4. Check router status lights (should be solid, not blinking)"
        fi
        
    elif [[ "$dns_ok" == "no" ]]; then
        warn "🔍 DNS PROBLEM (Easy to fix!)"
        echo "🔧 Try these fixes in order:"
        echo "  1. Quick fix (temporary):"
        echo "     sudo resolvectl dns $IFACE 8.8.8.8 1.1.1.1"
        echo "  2. Test it worked:"
        echo "     nslookup google.com"
        echo "  3. For permanent fix, configure your network connection"
        echo "     to use DNS servers: 8.8.8.8, 1.1.1.1"
    fi

    if [[ "$lan_peers" != "unknown" && $lan_peers -le 2 ]]; then
        echo ""
        warn "🔒 CLIENT ISOLATION DETECTED"
        explain "Your device can't see others on the network"
        echo "  • This is normal on guest networks"
        echo "  • Provides security but limits some features"
        echo "  • File sharing and network discovery won't work"
    fi

    echo ""
    bold "🛠️ USEFUL COMMANDS FOR ONGOING MONITORING:"
    echo "  • Check connection: ping -c 3 8.8.8.8"
    echo "  • Check DNS: nslookup google.com"
    echo "  • Monitor network: watch -n 5 'ping -c 1 $GATEWAY'"
    echo "  • Restart networking: sudo systemctl restart NetworkManager"
    echo "  • View WiFi networks: iwlist scan | grep ESSID"

    [[ $HAD_SUDO -eq 1 ]] && echo "" && info "ℹ️ Some tests required sudo privileges for detailed network scanning"
    
    echo ""
    bold "📝 SUMMARY REPORT SAVED"
    cat > "/tmp/netprobe_results.txt" <<EOF
Network Analysis Report - $(date)
=====================================

Basic Information:
- Interface: $IFACE
- Your IP: $MYIP
- Gateway: $GATEWAY
- Network: $SUB24

Test Results:
- Internet Access: $eg_ok
- DNS Resolution: $dns_ok
- Gateway Connection: $([ $GW_PING_OK -eq 1 ] && echo "good" || echo "limited")
- Other Devices Visible: $lan_peers
- Captive Portal: $([ $CAPTIVE_PORTAL -eq 1 ] && echo "detected" || echo "none")

Overall Status: $(
    if [[ "$eg_ok" == "yes" && "$dns_ok" == "yes" ]]; then
        echo "WORKING PERFECTLY"
    elif [[ "$eg_ok" == "no" ]]; then
        echo "INTERNET/NETWORK ISSUE"
    elif [[ "$dns_ok" == "no" ]]; then
        echo "DNS PROBLEM"
    else
        echo "NEEDS INVESTIGATION"
    fi
)
EOF
    ok "Report saved to: /tmp/netprobe_results.txt"
}

# ===== Main =====
main() {
    bold "🌐 Enhanced Network Diagnostic Tool"
    explain "This tool will test your network connection step by step and explain what everything means"
    info "Started: $(date)"
    echo ""
    
    # Check for tools and give helpful advice
    local missing_tools=()
    for tool in dig nmap; do
        if ! have "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        warn "Some advanced tools are missing: ${missing_tools[*]}"
        echo "For full functionality, install with:"
        echo "  Ubuntu/Debian: sudo apt install nmap dnsutils"
        echo "  Fedora/RHEL: sudo dnf install nmap bind-utils"
        echo ""
        echo "Continuing with available tools..."
    fi
    
    discover
    
    # Run quick triage first
    quick_triage
    
    # If basic tests failed, ask if they want detailed analysis
    if [[ $GW_PING_OK -eq 0 || $INTERNET_OK -eq 0 || $DNS_OK -eq 0 ]]; then
        echo ""
        read -p "🤔 Run detailed analysis anyway to learn more? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Stopping here. You can run detailed analysis with: $0 --detailed"
            exit 0
        fi
    fi
    
    # Run detailed phases
    phase1
    phase2_dns
    phase3_l2
    phase4_gateway
    
    # Run performance test if flag is set
    if [[ $DO_PERF -eq 1 ]]; then
        run_perf
    fi
    
    verdict
    
    bold "🏁 Analysis Complete!"
    explain "Check /tmp/netprobe_results.txt for a summary you can save or share"
}

# Handle command line arguments
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    echo "Enhanced Network Diagnostic Tool"
    echo ""
    echo "This tool tests your network connection and explains what each test means."
    echo "It's designed for people learning networking concepts."
    echo ""
    echo "The tool will:"
    echo "  1. Run quick tests to identify obvious problems"
    echo "  2. Explain what each test means in simple terms"
    echo "  3. Give specific commands to fix common issues"
    echo "  4. Provide a detailed analysis if needed"
    echo ""
    echo "Usage: $0 [options]"
    echo "  --detailed    Skip quick triage and run full analysis"
    echo "  --perf        Include network performance tests"
    echo "  -h, --help    Show this help"
    exit 0
fi

# Parse command line flags
[[ "${1:-}" == "--perf" ]] && DO_PERF=1
[[ "${2:-}" == "--perf" ]] && DO_PERF=1

# Skip triage if --detailed specified
if [[ "${1:-}" == "--detailed" ]]; then
    discover
    phase1
    phase2_dns
    phase3_l2
    phase4_gateway
    [[ $DO_PERF -eq 1 ]] && run_perf
    verdict
else
    main "$@"
fi
