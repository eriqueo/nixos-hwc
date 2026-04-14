#!/usr/bin/env bash
set -euo pipefail

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

bold(){ printf "\n${BOLD}%s${NC}\n" "$*"; }
info(){ printf "%s\n" "$*"; }
warn(){ printf "${YELLOW}⚠️  %s${NC}\n" "$*"; }
error(){ printf "${RED}❌ %s${NC}\n" "$*"; }
success(){ printf "${GREEN}✅ %s${NC}\n" "$*"; }

# Global variables for test results
BASIC_NET_OK=0
DNS_BYPASS_OK=0
GATEWAY_OK=0
INTERNET_IP_OK=0
DNS_RESOLVE_OK=0

# Quick network discovery
get_network_info() {
    DEF_LINE=$(ip route show default | head -n1 || true)
    if [[ -z "$DEF_LINE" ]]; then
        error "No default route found!"
        return 1
    fi
    
    export IFACE=$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$DEF_LINE")
    export GATEWAY=$(awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<<"$DEF_LINE")
    export MYIP=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | head -n1)
    export NETWORK=$(ipcalc -n "$MYIP" | cut -d= -f2 2>/dev/null || echo "unknown")
    export CIDR=$(ipcalc -p "$MYIP" | cut -d= -f2 2>/dev/null || echo "24")
    export SUBNET="${NETWORK%.*}.0/24"  # Force /24 for faster scanning
    
    info "Interface: $IFACE | IP: $MYIP | Gateway: $GATEWAY"
}

# PHASE 1: Fast triage tests (30 seconds max)
fast_triage() {
    bold "🚀 PHASE 1: Fast Triage (Is it me or the network?)"
    
    echo "Testing basic connectivity..."
    
    # Test 1: Can we reach gateway at all?
    echo -n "Gateway reachability: "
    if timeout 3 ping -c 1 -W 1 "$GATEWAY" >/dev/null 2>&1; then
        success "Gateway responds to ping"
        GATEWAY_OK=1
    elif timeout 5 bash -c "</dev/tcp/$GATEWAY/80" 2>/dev/null || \
         timeout 5 bash -c "</dev/tcp/$GATEWAY/443" 2>/dev/null; then
        warn "Gateway reachable but blocks ping"
        GATEWAY_OK=1
    else
        error "Gateway completely unreachable"
        GATEWAY_OK=0
    fi
    
    # Test 2: Can we reach internet by IP (bypass DNS)?
    echo -n "Internet via IP: "
    if timeout 5 bash -c "</dev/tcp/8.8.8.8/53" 2>/dev/null; then
        success "Can reach 8.8.8.8:53 directly"
        INTERNET_IP_OK=1
    elif timeout 3 ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        success "Can ping 8.8.8.8"
        INTERNET_IP_OK=1
    else
        error "Cannot reach internet IPs"
        INTERNET_IP_OK=0
    fi
    
    # Test 3: DNS resolution working?
    echo -n "DNS resolution: "
    if timeout 3 nslookup google.com 8.8.8.8 >/dev/null 2>&1; then
        success "DNS resolution works"
        DNS_RESOLVE_OK=1
    else
        error "DNS resolution failed"
        DNS_RESOLVE_OK=0
    fi
    
    # Test 4: Can we fetch a webpage?
    echo -n "HTTP connectivity: "
    if timeout 10 curl -s --connect-timeout 5 http://httpbin.org/ip >/dev/null 2>&1; then
        success "HTTP works"
    elif timeout 10 curl -s --connect-timeout 5 -I http://8.8.8.8 >/dev/null 2>&1; then
        warn "HTTP works to IP but not domains (DNS issue)"
    else
        error "HTTP completely blocked"
    fi
}

# Analyze triage results and give verdict
analyze_triage() {
    bold "📊 TRIAGE VERDICT"
    
    if [[ $GATEWAY_OK -eq 0 ]]; then
        error "VERDICT: YOUR CONNECTION IS BROKEN"
        echo "Problem: Cannot reach gateway"
        
        # Run automatic diagnostics
        bold "🔍 Running Connection Diagnostics..."
        
        # Check interface status
        echo "Interface status:"
        ip link show "$IFACE" | grep -E "(state|mtu)" || true
        
        # Check WiFi association
        echo -e "\nWiFi connection status:"
        if command -v iwconfig >/dev/null 2>&1; then
            iwconfig "$IFACE" 2>/dev/null | grep -E "(ESSID|Access Point|Signal)" || echo "iwconfig not available"
        fi
        if command -v iw >/dev/null 2>&1; then
            iw dev "$IFACE" link 2>/dev/null || echo "Not associated with any network"
        fi
        
        # Check assigned IP
        echo -e "\nIP assignment:"
        ip addr show "$IFACE" | grep -E "(inet |state)" || echo "No IP assigned"
        
        # Check which network manager is running
        echo -e "\nNetwork management:"
        if systemctl is-active NetworkManager >/dev/null 2>&1; then
            success "NetworkManager is running"
            echo "Available connections:"
            nmcli connection show | head -5 || true
        elif systemctl is-active systemd-networkd >/dev/null 2>&1; then
            success "systemd-networkd is running"
        else
            warn "No standard network manager detected"
        fi
        
        bold "🛠️ RECOMMENDED FIX COMMANDS:"
        echo "Try these commands in order:"
        echo ""
        echo "1️⃣ Restart NetworkManager (most common fix):"
        echo "   sudo systemctl restart NetworkManager"
        echo ""
        echo "2️⃣ If that fails, reconnect to WiFi:"
        echo "   sudo nmcli connection down \"$(iwconfig $IFACE 2>/dev/null | grep ESSID | cut -d'\"' -f2)\""
        echo "   sudo nmcli connection up \"$(iwconfig $IFACE 2>/dev/null | grep ESSID | cut -d'\"' -f2)\""
        echo ""
        echo "3️⃣ If NetworkManager isn't working, try interface reset:"
        echo "   sudo ip link set $IFACE down"
        echo "   sudo ip link set $IFACE up"
        echo ""
        echo "4️⃣ Force DHCP renewal (systemd-networkd):"
        echo "   sudo networkctl renew $IFACE"
        echo ""
        echo "5️⃣ Check recent network logs:"
        echo "   journalctl -u NetworkManager -n 20"
        echo ""
        echo "6️⃣ Manual network analysis:"
        echo "   sudo ./$(basename "$0") -f  # Force detailed scan"
        echo ""
        
        read -p "Continue with detailed analysis anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Stopping here. Run with -f to force detailed scan."
            exit 1
        fi
        
    elif [[ $INTERNET_IP_OK -eq 0 ]]; then
        error "VERDICT: NETWORK/ISP PROBLEM"
        echo "Problem: Gateway works but internet is down"
        
        # Run automatic diagnostics for upstream issues
        bold "🔍 Diagnosing Upstream Issues..."
        
        # Test if it's captive portal
        echo "Testing for captive portal..."
        if timeout 5 curl -s --connect-timeout 3 http://detectportal.firefox.com/canonical.html 2>/dev/null | grep -q "success"; then
            info "No captive portal detected"
        else
            warn "Possible captive portal or redirect detected"
        fi
        
        # Check gateway services
        echo -e "\nTesting gateway services:"
        for port in 80 443 53; do
            echo -n "Port $port: "
            if timeout 3 bash -c "</dev/tcp/$GATEWAY/$port" 2>/dev/null; then
                success "Open"
            else
                warn "Blocked"
            fi
        done
        
        # Check other devices on network
        echo -e "\nChecking for other active devices:"
        OTHER_HOSTS=$(timeout 10 sudo nmap -sn "${SUBNET}" 2>/dev/null | grep -c "Nmap scan report" || echo "0")
        if [[ $OTHER_HOSTS -gt 1 ]]; then
            info "Found $OTHER_HOSTS devices - network seems active"
        else
            warn "Only 1 device visible - possible client isolation"
        fi
        
        bold "🛠️ RECOMMENDED ACTIONS:"
        echo "This is NOT your fault. Try these:"
        echo ""
        echo "1️⃣ Test for captive portal:"
        echo "   firefox http://detectportal.firefox.com &"
        echo "   # OR try: firefox http://$GATEWAY &"
        echo ""
        echo "2️⃣ Check if other devices have internet:"
        echo "   # Test with phone/other device on same WiFi"
        echo ""
        echo "3️⃣ Verify network credentials:"
        echo "   nmcli connection show"
        echo "   # Look for authentication failures"
        echo ""
        echo "4️⃣ Contact network admin/ISP:"
        echo "   # Say: 'Can reach gateway $GATEWAY but no internet access'"
        echo ""
        echo "5️⃣ Try mobile hotspot to isolate issue:"
        echo "   # If hotspot works, confirms it's the network"
        
    elif [[ $DNS_RESOLVE_OK -eq 0 ]]; then
        warn "VERDICT: DNS PROBLEM"
        echo "Problem: Internet works but DNS is broken"
        
        # Test multiple DNS servers
        bold "🔍 Testing DNS Servers..."
        DNS_RESULTS=()
        for dns in "8.8.8.8" "1.1.1.1" "9.9.9.9" "208.67.222.222"; do
            echo -n "Testing DNS $dns: "
            if timeout 3 dig @"$dns" google.com +short >/dev/null 2>&1; then
                success "Working"
                DNS_RESULTS+=("$dns")
            else
                error "Failed"
            fi
        done
        
        # Check current DNS config
        echo -e "\nCurrent DNS configuration:"
        if command -v resolvectl >/dev/null 2>&1; then
            resolvectl status "$IFACE" 2>/dev/null | grep -E "(DNS Servers|Current DNS)" | head -3 || true
        fi
        
        bold "🛠️ DNS FIX COMMANDS:"
        if [[ ${#DNS_RESULTS[@]} -gt 0 ]]; then
            echo "Good news: ${DNS_RESULTS[*]} are working!"
            echo ""
            echo "1️⃣ Quick temporary fix:"
            echo "   sudo resolvectl dns $IFACE 8.8.8.8 1.1.1.1"
            echo ""
            echo "2️⃣ Permanent fix (NetworkManager):"
            echo "   sudo nmcli connection modify \"$(nmcli -t -f NAME connection show --active | head -1)\" ipv4.dns \"8.8.8.8,1.1.1.1\""
            echo "   sudo nmcli connection up \"$(nmcli -t -f NAME connection show --active | head -1)\""
            echo ""
            echo "3️⃣ Alternative permanent fix:"
            echo "   echo -e 'nameserver 8.8.8.8\\nnameserver 1.1.1.1' | sudo tee /etc/resolv.conf"
            echo ""
            echo "4️⃣ Verify the fix:"
            echo "   nslookup google.com"
        else
            error "All external DNS servers failed - this indicates deeper network issues"
            echo "Try the network/ISP troubleshooting steps instead."
        fi
        
        read -p "🤖 Apply DNS fix automatically? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            apply_dns_fix
        fi
        
    else
        success "VERDICT: BASIC CONNECTIVITY LOOKS GOOD"
        echo "All basic tests passed. If you're still having issues:"
        echo "  • Try different websites"
        echo "  • Check for proxy requirements"
        echo "  • Look for application-specific problems"
        echo ""
        echo "Proceeding with detailed diagnostics..."
        return 0
    fi
}
    
# Automatic connection repair functions
run_connection_fixes() {
    bold "🤖 Running Automatic Connection Fixes..."
    
    echo "Step 1: Restarting NetworkManager..."
    if sudo systemctl restart NetworkManager; then
        success "NetworkManager restarted"
        sleep 5
        
        # Test if it worked
        if timeout 5 ping -c 1 "$GATEWAY" >/dev/null 2>&1; then
            success "🎉 CONNECTION RESTORED! Gateway is now reachable."
            return 0
        fi
    else
        warn "NetworkManager restart failed"
    fi
    
    echo -e "\nStep 2: Trying interface reset..."
    sudo ip link set "$IFACE" down
    sleep 2
    sudo ip link set "$IFACE" up
    sleep 5
    
    if timeout 5 ping -c 1 "$GATEWAY" >/dev/null 2>&1; then
        success "🎉 CONNECTION RESTORED! Interface reset worked."
        return 0
    fi
    
    echo -e "\nStep 3: Trying systemd-networkd renewal..."
    if sudo networkctl renew "$IFACE" 2>/dev/null; then
        sleep 5
        if timeout 5 ping -c 1 "$GATEWAY" >/dev/null 2>&1; then
            success "🎉 CONNECTION RESTORED! DHCP renewal worked."
            return 0
        fi
    fi
    
    error "Automatic fixes didn't work. Manual intervention needed."
    echo "Next steps:"
    echo "1. Check physical WiFi connection"
    echo "2. Try connecting to different network"
    echo "3. Reboot system if nothing else works"
    return 1
}

apply_dns_fix() {
    bold "🤖 Applying DNS Fix..."
    
    echo "Setting DNS to 8.8.8.8 and 1.1.1.1..."
    
    # Try resolvectl first (systemd-resolved)
    if command -v resolvectl >/dev/null 2>&1; then
        if sudo resolvectl dns "$IFACE" 8.8.8.8 1.1.1.1; then
            success "DNS updated via resolvectl"
        fi
    fi
    
    # Also update via NetworkManager if available
    if command -v nmcli >/dev/null 2>&1; then
        ACTIVE_CONN=$(nmcli -t -f NAME connection show --active | head -1)
        if [[ -n "$ACTIVE_CONN" ]]; then
            if sudo nmcli connection modify "$ACTIVE_CONN" ipv4.dns "8.8.8.8,1.1.1.1"; then
                sudo nmcli connection up "$ACTIVE_CONN"
                success "DNS updated via NetworkManager"
            fi
        fi
    fi
    
    sleep 3
    echo "Testing DNS fix..."
    if timeout 5 nslookup google.com >/dev/null 2>&1; then
        success "🎉 DNS FIX SUCCESSFUL! You should now be able to browse."
        echo "Try opening a website to confirm."
    else
        error "DNS fix didn't work immediately. Try manually:"
        echo "sudo systemctl restart systemd-resolved"
    fi
}

# PHASE 2: Detailed network analysis (original comprehensive stuff)
detailed_analysis() {
    bold "🔍 PHASE 2: Detailed Network Analysis"
    
    # Enhanced network discovery
    echo "=== Network Details ==="
    info "Scanning subnet: $SUBNET"
    
    # WiFi-specific info
    if [[ "$IFACE" =~ ^wl ]]; then
        echo "WiFi connection details:"
        if command -v iw >/dev/null 2>&1; then
            iw dev "$IFACE" link 2>/dev/null | grep -E 'SSID|freq|signal|bitrate' || true
        fi
    fi
    
    # Gateway detailed scan
    echo -e "\n=== Gateway Analysis ==="
    echo "Performing detailed gateway scan..."
    timeout 60 sudo nmap -Pn --top-ports 100 -T4 "$GATEWAY" 2>/dev/null | \
        grep -E "(open|filtered|MAC|OS)" || warn "Gateway scan timeout/failed"
    
    # Network topology (limited scan)
    echo -e "\n=== Active Hosts Discovery ==="
    echo "Scanning for other devices (limited to 10 hosts max)..."
    timeout 30 sudo nmap -sn "$SUBNET" 2>/dev/null | \
        grep -E 'Nmap scan report|MAC Address' | head -20 || warn "Host discovery timeout"
    
    # Internet path analysis
    echo -e "\n=== Internet Path Analysis ==="
    echo "Traceroute to 8.8.8.8 (first 10 hops):"
    if command -v mtr >/dev/null 2>&1; then
        timeout 30 mtr -r -c 3 --no-dns 8.8.8.8 | head -12 || warn "MTR timeout"
    else
        timeout 30 traceroute -n 8.8.8.8 2>/dev/null | head -12 || warn "Traceroute timeout"
    fi
    
    # DNS deep dive
    echo -e "\n=== DNS Analysis ==="
    echo "Testing multiple DNS servers:"
    for dns in "8.8.8.8" "1.1.1.1" "9.9.9.9"; do
        if timeout 3 dig @"$dns" google.com +short >/dev/null 2>&1; then
            success "DNS $dns: Working"
        else
            error "DNS $dns: Failed"
        fi
    done
    
    # Performance tests
    echo -e "\n=== Performance Tests ==="
    echo -n "Gateway response time: "
    if command -v fping >/dev/null 2>&1; then
        fping -c 3 -q "$GATEWAY" 2>&1 | grep -o '[0-9.]*ms' | tail -1 || echo "timeout"
    else
        ping -c 3 "$GATEWAY" 2>/dev/null | tail -1 | grep -o 'time=[0-9.]*' || echo "timeout"
    fi
}

# PHASE 3: Advanced diagnostics and tools
advanced_diagnostics() {
    bold "🛠️ PHASE 3: Advanced Diagnostics"
    
    echo "=== Security Analysis ==="
    echo "Checking for common network issues..."
    
    # Check for captive portal
    echo -n "Captive portal test: "
    if timeout 5 curl -s --connect-timeout 3 http://detectportal.firefox.com/canonical.html | \
        grep -q "success"; then
        success "No captive portal detected"
    else
        warn "Possible captive portal - try opening browser"
    fi
    
    # Check for proxy requirements
    echo -n "Proxy detection: "
    if env | grep -i proxy; then
        warn "Proxy environment variables set"
    else
        info "No proxy settings detected"
    fi
    
    # Port connectivity tests
    echo -e "\nTesting common service ports:"
    for port in 80 443 53 22 21; do
        echo -n "Port $port: "
        if timeout 3 bash -c "</dev/tcp/8.8.8.8/$port" 2>/dev/null; then
            success "Open"
        else
            warn "Blocked/Filtered"
        fi
    done
    
    echo -e "\n=== Additional Tools Available ==="
    echo "For deeper analysis, try these commands:"
    echo "  • Bandwidth test: iperf3 -c speedtest.net"
    echo "  • Packet capture: sudo tcpdump -i $IFACE -w capture.pcap"
    echo "  • WiFi analysis: wavemon"
    echo "  • Real-time traffic: sudo iftop -i $IFACE"
    echo "  • DNS debugging: dig +trace google.com"
}

# Generate summary report
generate_report() {
    bold "📋 FINAL SUMMARY REPORT"
    
    # Create results file
    cat > "/tmp/netcheck_results.env" <<EOF
GATEWAY_OK="$GATEWAY_OK"
INTERNET_IP_OK="$INTERNET_IP_OK"
DNS_RESOLVE_OK="$DNS_RESOLVE_OK"
GATEWAY="$GATEWAY"
MY_IP="$MYIP"
INTERFACE="$IFACE"
SUBNET="$SUBNET"
TIMESTAMP="$(date)"
EOF
    
    echo "Quick diagnosis:"
    if [[ $GATEWAY_OK -eq 1 && $INTERNET_IP_OK -eq 1 && $DNS_RESOLVE_OK -eq 1 ]]; then
        success "✅ Network connectivity is good"
    elif [[ $GATEWAY_OK -eq 1 && $INTERNET_IP_OK -eq 1 && $DNS_RESOLVE_OK -eq 0 ]]; then
        warn "⚠️  DNS issues - change DNS servers to 8.8.8.8"
    elif [[ $GATEWAY_OK -eq 1 && $INTERNET_IP_OK -eq 0 ]]; then
        error "❌ Internet/ISP problem - not your fault"
    else
        error "❌ Local connectivity issues - check your connection"
    fi
    
    echo ""
    echo "Results saved to: /tmp/netcheck_results.env"
    echo "For ongoing monitoring: watch -n 5 'ping -c 1 8.8.8.8'"
}

# Main execution
main() {
    bold "🌐 Smart Network Diagnostic Tool"
    echo "Strategy: Fast triage first, detailed analysis second"
    echo "Timestamp: $(date)"
    
    # Check for required tools
    MISSING_TOOLS=()
    for tool in ip ipcalc; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            MISSING_TOOLS+=("$tool")
        fi
    done
    
    if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
        error "Missing required tools: ${MISSING_TOOLS[*]}"
        echo "Install with: sudo apt install iproute2 ipcalc"
        exit 1
    fi
    
    # Get basic network info
    get_network_info || exit 1
    
    # Phase 1: Fast triage (always run)
    fast_triage
    analyze_triage || exit 0
    
    # Phase 2: Detailed analysis (only if triage passes or forced)
    if [[ "${1:-}" == "-f" ]] || [[ $GATEWAY_OK -eq 1 ]]; then
        detailed_analysis
        
        # Phase 3: Advanced diagnostics (optional)
        echo ""
        read -p "Run advanced diagnostics? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            advanced_diagnostics
        fi
    fi
    
    generate_report
    
    bold "🏁 Analysis Complete"
}

# Handle command line arguments
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    echo "Smart Network Diagnostic Tool"
    echo ""
    echo "Usage: $0 [options]"
    echo "  -f    Force detailed analysis even if basic tests fail"
    echo "  -h    Show this help"
    echo ""
    echo "The tool runs in phases:"
    echo "  1. Fast triage (30 seconds) - determines if it's your problem"
    echo "  2. Detailed analysis - comprehensive network scanning"
    echo "  3. Advanced diagnostics - security and performance tests"
    exit 0
fi

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
