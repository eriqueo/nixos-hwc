#!/usr/bin/env bash
# HWC NixOS Update Validator
# CHARTER v9.0 - Pre-update validation to catch breaking changes
#
# Usage: ./workspace/utilities/update-validator.sh [--pre-switch]
# Run BEFORE nix flake update to check for known issues
# Use --pre-switch before nixos-rebuild switch for runtime validation

set -euo pipefail

PRE_SWITCH_MODE=false
if [[ "${1:-}" == "--pre-switch" ]]; then
    PRE_SWITCH_MODE=true
fi

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HWC NixOS Update Validator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print error
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

# Function to print warning
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

# Function to print success
success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Function to print info
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

#============================================================================
# CHECK 1: Prove nixpkgs provenance via nix eval
#============================================================================
echo "Proving server uses nixpkgs-stable (via nix eval)..."

NIXPKGS_VERSION=$(nix eval --raw '.#nixosConfigurations.hwc-server.pkgs.lib.trivial.release' 2>/dev/null || echo "unknown")

if [[ "$NIXPKGS_VERSION" == "24.05"* ]] || [[ "$NIXPKGS_VERSION" == "24.11"* ]]; then
    success "Server uses nixpkgs-stable ($NIXPKGS_VERSION)"
else
    error "Server using wrong nixpkgs! Got: $NIXPKGS_VERSION (expected 24.05 or 24.11)"
    echo "      This will cause breaking changes! Fix in flake.nix"
fi

#============================================================================
# CHECK 2: Prove PostgreSQL version via nix eval
#============================================================================
echo "Proving PostgreSQL version pin (via nix eval)..."

PG_VERSION=$(nix eval --raw '.#nixosConfigurations.hwc-server.config.services.postgresql.package.version' 2>/dev/null || echo "disabled")

if [[ "$PG_VERSION" == "disabled" ]]; then
    info "PostgreSQL not enabled (skipping version check)"
elif [[ "$PG_VERSION" == "15."* ]]; then
    success "PostgreSQL pinned to version $PG_VERSION"
else
    error "PostgreSQL version is $PG_VERSION (expected 15.x)!"
    echo "      Data directory is PostgreSQL 15 format - this will break!"
    echo "      Fix in domains/server/native/networking/parts/databases.nix"
fi

#============================================================================
# CHECK 3: Prove PostgreSQL runtime version (if running)
#============================================================================
if $PRE_SWITCH_MODE && systemctl is-active --quiet postgresql 2>/dev/null; then
    echo "Verifying PostgreSQL runtime version..."

    PG_RUNTIME_VERSION=$(sudo -u postgres psql -t -c "SHOW server_version;" 2>/dev/null | tr -d ' ' | cut -d'.' -f1 || echo "unknown")

    if [[ "$PG_RUNTIME_VERSION" == "15" ]]; then
        success "PostgreSQL running version 15 (matches data directory)"
    else
        warn "PostgreSQL runtime version: $PG_RUNTIME_VERSION (data directory expects 15)"
    fi
fi

#============================================================================
# CHECK 3: Disabled services (temporary breakage)
#============================================================================
echo "Checking for temporarily disabled services..."

DISABLED_COUNT=0

if rg -q "# .*transcript-api" domains/server/native/networking/index.nix; then
    warn "transcript-api is disabled (Python 3.13 compatibility issue)"
    ((DISABLED_COUNT++))
fi

if rg -q "# .*yt-transcripts-api" domains/server/native/networking/index.nix; then
    warn "yt-transcripts-api is disabled (Python 3.13 compatibility issue)"
    ((DISABLED_COUNT++))
fi

if rg -q "# .*gemini-cli" domains/system/packages/server.nix; then
    warn "gemini-cli is disabled (npm build failure)"
    ((DISABLED_COUNT++))
fi

if [ $DISABLED_COUNT -eq 0 ]; then
    success "No disabled services detected"
else
    info "Re-enable services after upstream fixes are available"
fi

#============================================================================
# CHECK 5: ZFS health (if applicable)
#============================================================================
echo "Checking ZFS pool health..."

if command -v zpool &> /dev/null; then
    ZFS_HEALTH=$(zpool status -x 2>/dev/null || echo "no pools")

    if [[ "$ZFS_HEALTH" == "all pools are healthy" ]]; then
        success "All ZFS pools healthy"
    elif [[ "$ZFS_HEALTH" == "no pools"* ]]; then
        info "No ZFS pools configured"
    else
        error "ZFS pools have issues!"
        echo "$ZFS_HEALTH"
        echo "      Run: zpool status for details"
    fi
else
    info "ZFS not installed (skipping)"
fi

#============================================================================
# CHECK 6: Disk space
#============================================================================
echo "Checking disk space..."

# Check /nix store
NIX_USAGE=$(df -h /nix | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $NIX_USAGE -lt 90 ]]; then
    success "/nix has ${NIX_USAGE}% used (healthy)"
elif [[ $NIX_USAGE -lt 95 ]]; then
    warn "/nix has ${NIX_USAGE}% used (consider cleanup)"
    echo "      Run: nix-collect-garbage -d"
else
    error "/nix has ${NIX_USAGE}% used (critical!)"
    echo "      Run: nix-collect-garbage -d immediately"
fi

# Check root filesystem
ROOT_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $ROOT_USAGE -lt 80 ]]; then
    success "/ has ${ROOT_USAGE}% used (healthy)"
else
    warn "/ has ${ROOT_USAGE}% used (monitor closely)"
fi

#============================================================================
# CHECK 7: Critical services health (runtime check)
#============================================================================
if $PRE_SWITCH_MODE; then
    echo "Checking critical services health..."

    CRITICAL_SERVICES=(
        "postgresql"
        "tailscaled"
        "caddy"
    )

    for service in "${CRITICAL_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            # Check if service has failed recently
            FAILED_COUNT=$(systemctl show "$service" -p NRestarts --value)
            if [[ ${FAILED_COUNT:-0} -gt 5 ]]; then
                warn "$service has restarted $FAILED_COUNT times (check journalctl)"
            else
                success "$service is healthy"
            fi
        else
            warn "$service is not running (may need restart after update)"
        fi
    done
else
    echo "Skipping runtime health checks (use --pre-switch for full validation)"
fi

#============================================================================
# CHECK 5: Flake lock age
#============================================================================
echo "Checking flake.lock age..."

if [ -f flake.lock ]; then
    LOCK_AGE_DAYS=$(( ($(date +%s) - $(stat -c %Y flake.lock)) / 86400 ))

    if [ $LOCK_AGE_DAYS -lt 30 ]; then
        success "flake.lock updated recently ($LOCK_AGE_DAYS days ago)"
    elif [ $LOCK_AGE_DAYS -lt 90 ]; then
        info "flake.lock is $LOCK_AGE_DAYS days old (consider updating)"
    else
        warn "flake.lock is $LOCK_AGE_DAYS days old (large update expected)"
        echo "      Consider gradual updates: nix flake lock --update-input nixpkgs-stable"
    fi
fi

#============================================================================
# SUMMARY
#============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}========================================${NC}"

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}Errors: $ERRORS${NC}"
    echo -e "${RED}DO NOT UPDATE until errors are resolved!${NC}"
    exit 1
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo -e "${YELLOW}Review warnings before updating${NC}"
fi

echo -e "${GREEN}Validation checks: PASSED${NC}"
echo ""
echo "Safe to proceed with gradual update:"
echo "  1. nix flake lock --update-input nixpkgs-stable"
echo "  2. nixos-rebuild build --flake .#hwc-server"
echo "  3. nixos-rebuild test --flake .#hwc-server"
echo "  4. Verify services: systemctl status postgresql tailscaled"
echo "  5. nixos-rebuild switch --flake .#hwc-server"
echo ""
