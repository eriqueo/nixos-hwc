#!/usr/bin/env bash
set -euo pipefail

echo "=== Validating Migration from github.com/eriqueo/nixos-hwc ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

check() {
    local name=$1
    local cmd=$2

    echo -n "Checking $name... "
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC}"
        ((FAILED++))
    fi
}

echo ""
echo "Structure Validation:"
echo "--------------------"
check "Modules directory" "[ -d modules/services ]"
check "Profiles directory" "[ -d profiles ]"
check "Machines directory" "[ -d machines ]"
check "Operations directory" "[ -d operations ]"

echo ""
echo "Core Modules:"
echo "-------------"
check "Paths module" "[ -f modules/system/paths.nix ]"
check "Users module" "[ -f modules/system/users.nix ]"

echo ""
echo "Service Modules:"
echo "---------------"
for service in jellyfin frigate arr-stack prometheus grafana; do
    check "$service module" "[ -f modules/services/$service.nix ]"
done

echo ""
echo "Build Tests:"
echo "-----------"
check "Flake validity" "nix flake check --no-build"
check "Server config" "nix build .#nixosConfigurations.hwc-server.config.system.build.toplevel --dry-run"

echo ""
echo "Path Migration:"
echo "--------------"
check "No hardcoded /mnt/hot" "! grep -r '/mnt/hot' modules/services/ 2>/dev/null | grep -v hwc.paths"
check "No hardcoded /mnt/media" "! grep -r '/mnt/media' modules/services/ 2>/dev/null | grep -v hwc.paths"
check "Using hwc namespace" "grep -r 'hwc.services' modules/services/ | wc -l | grep -qv '^0$'"

echo ""
echo "════════════════════════════════════════"
echo "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ Migration structure valid!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Port remaining services from old config"
    echo "2. Update secrets configuration"
    echo "3. Test build: sudo nixos-rebuild build --flake .#hwc-server"
    echo "4. Plan cutover window"
else
    echo -e "${YELLOW}⚠️  Issues found. Fix before proceeding.${NC}"
    exit 1
fi
