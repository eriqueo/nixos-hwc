#!/usr/bin/env bash
# pr24-validation.sh - Automated testing for PR #24 paths refactor
#
# Usage: ./workspace/nixos/pr24-validation.sh [--verbose]
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed
#   2 - Critical failure (should rollback)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
CRITICAL_FAIL=0

# Verbose mode
VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# Test result tracking
declare -a FAILED_TESTS=()

log() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}[PASS]${NC} $1"
  ((PASS++))
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  ((FAIL++))
  FAILED_TESTS+=("$1")
}

critical() {
  echo -e "${RED}[CRITICAL]${NC} $1"
  ((CRITICAL_FAIL++))
  FAILED_TESTS+=("$1 (CRITICAL)")
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

test_cmd() {
  local name="$1"
  local cmd="$2"
  local is_critical="${3:-false}"

  if $VERBOSE; then
    echo -e "${BLUE}[TEST]${NC} $name"
    echo -e "${BLUE}[CMD]${NC}  $cmd"
  else
    echo -n "Testing $name... "
  fi

  if eval "$cmd" >/dev/null 2>&1; then
    $VERBOSE && success "$name" || echo -e "${GREEN}✓${NC}"
    ((PASS++))
    return 0
  else
    if [[ "$is_critical" == "true" ]]; then
      $VERBOSE && critical "$name" || echo -e "${RED}✗ CRITICAL${NC}"
      ((CRITICAL_FAIL++))
    else
      $VERBOSE && fail "$name" || echo -e "${RED}✗${NC}"
      ((FAIL++))
    fi
    FAILED_TESTS+=("$name")
    return 1
  fi
}

header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

# Detect machine type
MACHINE_TYPE="unknown"
if [[ -f /etc/nixos/machines/server/config.nix ]] || hostname | grep -q server; then
  MACHINE_TYPE="server"
elif [[ -f /etc/nixos/machines/laptop/config.nix ]] || hostname | grep -q laptop; then
  MACHINE_TYPE="laptop"
fi

log "Starting PR #24 Paths Refactor Validation"
log "Machine type: $MACHINE_TYPE"
log "Verbose mode: $VERBOSE"
echo ""

#=============================================================================
# PHASE 1: PATH RESOLUTION (CRITICAL)
#=============================================================================
header "PHASE 1: Path Resolution (CRITICAL)"

# Core path variables
test_cmd "HWC_HOT_STORAGE variable set" "test -n \"\${HWC_HOT_STORAGE:-}\"" true
test_cmd "HWC_MEDIA_STORAGE variable set" "test -n \"\${HWC_MEDIA_STORAGE:-}\"" true
test_cmd "HWC_USER_HOME variable set" "test -n \"\${HWC_USER_HOME:-}\"" true

# Path existence
test_cmd "Hot storage directory exists" "test -d \"\${HWC_HOT_STORAGE:-/nonexistent}\"" true
test_cmd "Media storage directory exists" "test -d \"\${HWC_MEDIA_STORAGE:-/nonexistent}\"" true
test_cmd "User home directory exists" "test -d \"\${HWC_USER_HOME:-/nonexistent}\"" true

# HWC service directories
test_cmd "/var/lib/hwc exists" "test -d /var/lib/hwc" true
test_cmd "/var/cache/hwc exists" "test -d /var/cache/hwc" false
test_cmd "/var/log/hwc exists" "test -d /var/log/hwc" false

# Verify correct ownership
test_cmd "/var/lib/hwc owned by eric:users" \
  "stat -c '%U:%G' /var/lib/hwc | grep -q 'eric:users'" false

# Machine-specific path validation
if [[ "$MACHINE_TYPE" == "server" ]]; then
  test_cmd "Server hot storage at /mnt/hot" \
    "echo \$HWC_HOT_STORAGE | grep -q '^/mnt/hot'" true
  test_cmd "Server media storage at /mnt/media" \
    "echo \$HWC_MEDIA_STORAGE | grep -q '^/mnt/media'" true
elif [[ "$MACHINE_TYPE" == "laptop" ]]; then
  test_cmd "Laptop hot storage in home" \
    "echo \$HWC_HOT_STORAGE | grep -q 'storage/hot'" false
fi

#=============================================================================
# PHASE 2: SERVICE HEALTH (CRITICAL)
#=============================================================================
header "PHASE 2: Service Health (CRITICAL)"

# System-wide service check
test_cmd "No failed systemd services" \
  "systemctl --failed --no-pager | grep -q '0 loaded units'" true

# Core system services
test_cmd "Networking active" "systemctl is-active NetworkManager" true || \
  test_cmd "Networking (systemd-networkd)" "systemctl is-active systemd-networkd" true

# Check for path-related errors in journal
test_cmd "No critical path errors in journal" \
  "! sudo journalctl -b -p err --no-pager | grep -qi 'no such file or directory.*hwc\|path.*not found.*hwc'" false

#=============================================================================
# PHASE 3: UPDATED CONSUMER SERVICES
#=============================================================================
header "PHASE 3: Consumer Services (Updated Modules)"

# Storage cleanup service
test_cmd "Storage cleanup timer exists" \
  "systemctl list-unit-files | grep -q hwc-storage-cleanup.timer" false

# Monitoring services (use state/cache/logs paths)
if systemctl list-unit-files | grep -q prometheus.service; then
  test_cmd "Prometheus service active" "systemctl is-active prometheus" false
  test_cmd "Prometheus state directory" "test -d /var/lib/hwc/prometheus" false
fi

if systemctl list-unit-files | grep -q grafana.service; then
  test_cmd "Grafana service active" "systemctl is-active grafana" false
  test_cmd "Grafana state directory" "test -d /var/lib/hwc/grafana" false
fi

#=============================================================================
# PHASE 4: SERVER SERVICES (NAMESPACE CHANGES)
#=============================================================================
if [[ "$MACHINE_TYPE" == "server" ]]; then
  header "PHASE 4: Server Services (Namespace hwc.server.*)"

  # NTFY (hwc.services.ntfy → hwc.server.ntfy)
  if systemctl list-unit-files | grep -q ntfy.service; then
    test_cmd "NTFY service active" "systemctl is-active ntfy" false
  fi

  # Caddy reverse proxy
  if systemctl list-unit-files | grep -q caddy.service; then
    test_cmd "Caddy service active" "systemctl is-active caddy" true
    test_cmd "Caddy responding" "curl -sf -I https://localhost 2>&1 | grep -qi 'HTTP'" false
  fi

  # Transcript API
  if systemctl list-unit-files | grep -q transcript-api.service; then
    test_cmd "Transcript API service active" "systemctl is-active transcript-api" false
  fi
fi

#=============================================================================
# PHASE 5: CONTAINER VALIDATION (SERVER)
#=============================================================================
if [[ "$MACHINE_TYPE" == "server" ]] && command -v podman &>/dev/null; then
  header "PHASE 5: Container Health"

  # Check podman is functional
  test_cmd "Podman operational" "sudo podman ps >/dev/null" true

  # Critical media containers
  for container in qbittorrent sonarr radarr prowlarr; do
    if sudo podman ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
      test_cmd "$container container running" \
        "sudo podman ps --filter name=^${container}$ --format '{{.State}}' | grep -q running" false
    fi
  done

  # Check for permission errors in container logs
  if sudo podman ps --format "{{.Names}}" | grep -q .; then
    test_cmd "No permission errors in container logs (last 100 lines)" \
      "! sudo podman ps --format '{{.Names}}' | xargs -I {} sudo podman logs {} 2>&1 | tail -100 | grep -qi 'permission denied'" false
  fi
fi

#=============================================================================
# PHASE 6: SECRET ACCESS (CRITICAL)
#=============================================================================
header "PHASE 6: Secret Access (CRITICAL)"

# Agenix runtime secrets
test_cmd "Agenix secrets directory exists" "test -d /run/agenix" true

if test -d /run/agenix; then
  test_cmd "Agenix secrets present" "test -n \"\$(sudo ls /run/agenix/ 2>/dev/null)\"" true
  test_cmd "Secrets have correct group (secrets)" \
    "sudo stat -c '%G' /run/agenix/* 2>/dev/null | grep -q secrets" true
fi

# Age key exists
test_cmd "Age key exists" "sudo test -f /etc/sops/age/keys.txt" true

#=============================================================================
# PHASE 7: FUNCTIONAL VALIDATION
#=============================================================================
header "PHASE 7: Functional Validation"

# Media services responding (if enabled)
if [[ "$MACHINE_TYPE" == "server" ]]; then
  if systemctl is-active jellyfin &>/dev/null; then
    test_cmd "Jellyfin health check" \
      "curl -sf http://localhost:8096/health | grep -qi 'healthy\|ok'" false
  fi

  if systemctl is-active navidrome &>/dev/null; then
    test_cmd "Navidrome ping" "curl -sf http://localhost:4533/ping" false
  fi

  if systemctl is-active immich &>/dev/null; then
    test_cmd "Immich ping" \
      "curl -sf http://localhost:2283/api/server-info/ping | grep -qi 'pong'" false
  fi
fi

# AI services (if enabled)
if systemctl is-active ollama &>/dev/null; then
  test_cmd "Ollama responding" "curl -sf http://localhost:11434/api/tags >/dev/null" false
fi

#=============================================================================
# SUMMARY
#=============================================================================
header "SUMMARY"

echo ""
echo "Results:"
echo "  ✓ Passed:  $PASS"
echo "  ✗ Failed:  $FAIL"
echo "  ✗ CRITICAL: $CRITICAL_FAIL"
echo ""

if [[ $CRITICAL_FAIL -gt 0 ]]; then
  echo -e "${RED}═══════════════════════════════════════${NC}"
  echo -e "${RED}  CRITICAL FAILURES DETECTED${NC}"
  echo -e "${RED}  Consider rolling back to previous generation${NC}"
  echo -e "${RED}═══════════════════════════════════════${NC}"
  echo ""
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  - $test"
  done
  echo ""
  echo "Rollback command:"
  echo "  sudo nixos-rebuild switch --rollback"
  exit 2
elif [[ $FAIL -gt 0 ]]; then
  echo -e "${YELLOW}═══════════════════════════════════════${NC}"
  echo -e "${YELLOW}  SOME TESTS FAILED${NC}"
  echo -e "${YELLOW}  Review failures before production use${NC}"
  echo -e "${YELLOW}═══════════════════════════════════════${NC}"
  echo ""
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  - $test"
  done
  echo ""
  echo "Check logs:"
  echo "  sudo journalctl -b -p err --no-pager"
  exit 1
else
  echo -e "${GREEN}═══════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✓ ALL TESTS PASSED${NC}"
  echo -e "${GREEN}  System validated successfully${NC}"
  echo -e "${GREEN}═══════════════════════════════════════${NC}"
  echo ""
  log "PR #24 paths refactor validation complete"
  exit 0
fi
