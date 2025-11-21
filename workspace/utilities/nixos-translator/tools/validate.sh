#!/usr/bin/env bash
#
# Migration Validation Suite
# Pre-flight and post-deployment checks
#
# Usage:
#   ./validate.sh --mode pre-flight   # Before migration
#   ./validate.sh --mode post-deploy  # After deployment
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MODE="${1:---mode}"
MODE="${2:-pre-flight}"

PASSED=0
FAILED=0
WARNINGS=0

log() {
    echo -e "${GREEN}[validate]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

run_test() {
    local test_name="$1"
    local test_cmd="$2"

    info "Testing: $test_name"

    if eval "$test_cmd" >/dev/null 2>&1; then
        pass "  $test_name"
        return 0
    else
        error "  $test_name"
        return 1
    fi
}

log "Migration Validation Suite"
log "Mode: $MODE"
echo ""

# Pre-flight checks (run before migration)
if [[ "$MODE" == "pre-flight" ]]; then
    echo "========================================="
    echo "PRE-FLIGHT CHECKS"
    echo "========================================="
    echo ""

    # System requirements
    log "Checking system requirements..."

    run_test "Docker installed" "command -v docker"
    run_test "Docker Compose installed" "command -v docker-compose"
    run_test "Docker daemon running" "systemctl is-active docker"
    run_test "User in docker group" "groups | grep -q docker"

    # Package managers
    run_test "pacman available" "command -v pacman"

    # Tools
    run_test "yq installed (YAML parser)" "command -v yq" || warn "Install with: sudo pacman -S yq"
    run_test "age installed (for secrets)" "command -v age" || warn "Install with: sudo pacman -S age"
    run_test "sops installed (for secrets)" "command -v sops" || warn "Install with: sudo pacman -S sops"
    run_test "stow installed (for dotfiles)" "command -v stow" || warn "Install with: sudo pacman -S stow"

    # Directories
    log "Checking directory structure..."

    if [[ -d "./arch-hwc" ]]; then
        pass "  arch-hwc directory exists"
    else
        error "  arch-hwc directory missing"
    fi

    if [[ -d "./arch-hwc/compose" ]]; then
        pass "  compose directory exists"
    else
        error "  compose directory missing"
    fi

    if [[ -d "./arch-hwc/packages" ]]; then
        pass "  packages directory exists"
    else
        error "  packages directory missing"
    fi

    # Docker Compose files
    log "Validating Docker Compose files..."

    for compose_file in ./arch-hwc/compose/*/docker-compose.yml; do
        if [[ -f "$compose_file" ]]; then
            if docker-compose -f "$compose_file" config >/dev/null 2>&1; then
                pass "  $(basename $(dirname $compose_file))/docker-compose.yml"
            else
                error "  $(basename $(dirname $compose_file))/docker-compose.yml - Invalid YAML"
            fi
        fi
    done

    # Required volumes
    log "Checking volume mount points..."

    for mount in /mnt/hot /mnt/media; do
        if mountpoint -q "$mount" 2>/dev/null; then
            pass "  $mount is mounted"
        else
            warn "  $mount is NOT mounted"
        fi
    done

    # Required directories
    for dir in /opt/downloads /opt/arr /opt/secrets; do
        if [[ -d "$dir" ]]; then
            pass "  $dir exists"
        else
            warn "  $dir does not exist (will be created)"
        fi
    done

fi

# Post-deployment checks (run after migration)
if [[ "$MODE" == "post-deploy" ]]; then
    echo "========================================="
    echo "POST-DEPLOYMENT CHECKS"
    echo "========================================="
    echo ""

    # Secrets
    log "Checking secrets..."

    if [[ -d "/opt/secrets" ]]; then
        secret_count=$(find /opt/secrets -type f 2>/dev/null | wc -l)
        if [[ "$secret_count" -gt 0 ]]; then
            pass "  Secrets deployed ($secret_count files)"
        else
            error "  No secrets found in /opt/secrets"
        fi
    else
        error "  /opt/secrets directory missing"
    fi

    # Docker networks
    log "Checking Docker networks..."

    if docker network ls | grep -q media-network; then
        pass "  media-network exists"
    else
        error "  media-network missing (create with: docker network create media-network)"
    fi

    # Containers
    log "Checking container status..."

    # Count running containers
    running=$(docker ps --format '{{.Names}}' | wc -l)
    total=$(docker ps -a --format '{{.Names}}' | wc -l)

    info "  $running/$total containers running"

    # Check critical containers
    for container in gluetun jellyfin immich; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            pass "  $container is running"
        else
            if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
                error "  $container exists but is not running"
            else
                warn "  $container not found"
            fi
        fi
    done

    # GPU access
    log "Checking GPU access..."

    if lspci | grep -i nvidia >/dev/null 2>&1; then
        if command -v nvidia-smi >/dev/null 2>&1; then
            if nvidia-smi >/dev/null 2>&1; then
                pass "  NVIDIA GPU accessible"
            else
                error "  nvidia-smi failed"
            fi
        else
            error "  nvidia-smi not installed"
        fi
    else
        info "  No NVIDIA GPU detected"
    fi

    # Test GPU in container (if NVIDIA)
    if command -v nvidia-smi >/dev/null 2>&1; then
        if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi >/dev/null 2>&1; then
            pass "  GPU accessible in containers"
        else
            error "  GPU not accessible in containers"
        fi
    fi

    # Service connectivity
    log "Checking service connectivity..."

    # Test if services respond
    services_to_test=(
        "localhost:8096"   # Jellyfin
        "localhost:2283"   # Immich
        "localhost:8989"   # Sonarr
        "localhost:7878"   # Radarr
    )

    for service in "${services_to_test[@]}"; do
        if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${service/:/ }" 2>/dev/null; then
            pass "  $service responding"
        else
            warn "  $service not responding (may not be started yet)"
        fi
    done

    # Systemd services (if any native services)
    log "Checking systemd services..."

    for service in jellyfin immich ollama; do
        if systemctl list-unit-files | grep -q "${service}.service"; then
            if systemctl is-active "$service" >/dev/null 2>&1; then
                pass "  $service.service is active"
            else
                error "  $service.service is not active"
            fi
        fi
    done

    # Dotfiles
    log "Checking dotfiles..."

    if [[ -L "$HOME/.zshrc" ]]; then
        pass "  Dotfiles symlinks exist (stow deployed)"
    else
        warn "  No dotfile symlinks found (stow not run?)"
    fi

fi

# Summary
echo ""
echo "========================================="
echo "SUMMARY"
echo "========================================="
echo ""
echo -e "${GREEN}Passed:${NC}   $PASSED"
[[ "$WARNINGS" -gt 0 ]] && echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
[[ "$FAILED" -gt 0 ]] && echo -e "${RED}Failed:${NC}   $FAILED"
echo ""

# Generate JSON report
REPORT_FILE="validation-report-$(date +%Y%m%d-%H%M%S).json"

cat > "$REPORT_FILE" <<JSON_REPORT
{
  "timestamp": "$(date -Iseconds)",
  "mode": "$MODE",
  "summary": {
    "passed": $PASSED,
    "warnings": $WARNINGS,
    "failed": $FAILED,
    "total": $((PASSED + WARNINGS + FAILED))
  }
}
JSON_REPORT

log "Report saved: $REPORT_FILE"

# Exit code
if [[ "$FAILED" -gt 0 ]]; then
    echo ""
    error "Validation FAILED ($FAILED failures)"
    exit 1
else
    echo ""
    log "Validation PASSED"
    [[ "$WARNINGS" -gt 0 ]] && warn "But with $WARNINGS warnings"
    exit 0
fi
