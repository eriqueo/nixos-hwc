#!/usr/bin/env bash
# Service Health Summary - Quick health overview of NixOS system
# Usage: ./workspace/monitoring/service-health-summary.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== NixOS System Health Summary ===${NC}"
echo ""

# 1. System Services
echo -e "${BLUE}System Services:${NC}"
failed_system=$(systemctl list-units --type=service --state=failed --no-legend | wc -l)
if [ "$failed_system" -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} All system services healthy"
else
    echo -e "  ${RED}✗${NC} $failed_system failed system services:"
    systemctl list-units --type=service --state=failed --no-legend | awk '{print "    - " $1}'
fi
echo ""

# 2. User Services
echo -e "${BLUE}User Services:${NC}"
failed_user=$(systemctl --user list-units --type=service --state=failed --no-legend 2>/dev/null | wc -l || echo 0)
if [ "$failed_user" -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} All user services healthy"
else
    echo -e "  ${RED}✗${NC} $failed_user failed user services:"
    systemctl --user list-units --type=service --state=failed --no-legend 2>/dev/null | awk '{print "    - " $1}' || true
fi
echo ""

# 3. Containers
echo -e "${BLUE}Containers:${NC}"
if command -v podman &> /dev/null; then
    stopped_containers=$(sudo podman ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null || true)
    if [ -z "$stopped_containers" ]; then
        echo -e "  ${GREEN}✓${NC} All containers running or no containers configured"
    else
        echo -e "  ${YELLOW}!${NC} Stopped containers:"
        echo "$stopped_containers" | while read -r container; do
            echo "    - $container"
        done
    fi
else
    echo -e "  ${YELLOW}!${NC} Podman not installed"
fi
echo ""

# 4. Boot Errors
echo -e "${BLUE}Recent Boot Errors:${NC}"
boot_errors=$(journalctl -b -p err --no-pager 2>/dev/null | wc -l || echo 0)
if [ "$boot_errors" -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} No errors since last boot"
else
    echo -e "  ${YELLOW}!${NC} $boot_errors error messages since boot"
    echo "    Run: journalctl -b -p err --no-pager"
fi
echo ""

# 5. Disk Space
echo -e "${BLUE}Disk Space:${NC}"
while IFS= read -r line; do
    usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
    mount=$(echo "$line" | awk '{print $6}')

    if [ "$usage" -ge 90 ]; then
        echo -e "  ${RED}✗${NC} $mount: ${usage}% (critical)"
    elif [ "$usage" -ge 80 ]; then
        echo -e "  ${YELLOW}!${NC} $mount: ${usage}% (warning)"
    else
        echo -e "  ${GREEN}✓${NC} $mount: ${usage}%"
    fi
done < <(df -h / /home /nix 2>/dev/null | tail -n +2)
echo ""

# 6. Nix Store
echo -e "${BLUE}Nix Store:${NC}"
nix_size=$(du -sh /nix/store 2>/dev/null | awk '{print $1}' || echo "unknown")
echo -e "  Size: $nix_size"
echo -e "  Run 'nix-collect-garbage -d' to clean up"
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ "$failed_system" -eq 0 ] && [ "$failed_user" -eq 0 ] && [ "$boot_errors" -eq 0 ]; then
    echo -e "${GREEN}✓ System is healthy${NC}"
else
    echo -e "${YELLOW}! Some issues detected - review above for details${NC}"
fi
