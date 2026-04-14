#!/usr/bin/env bash
#
# Container Consistency Validator
# Purpose: Validate all NixOS containers for Charter v6 compliance, networking consistency,
#          and troubleshooting readiness
#
# Usage: ./scripts/lints/container-lint.sh [--verbose] [--fix] [container-name]
#
# Exit codes:
#   0 - All checks passed
#   1 - Validation errors found
#   2 - Script error

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
PASSED=0

# Configuration
VERBOSE=false
FIX_MODE=false
CONTAINER_FILTER=""
CONTAINERS_DIR="domains/server/containers"
REPORT_DIR=".lint-reports"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --fix)
      FIX_MODE=true
      shift
      ;;
    *)
      CONTAINER_FILTER="$1"
      shift
      ;;
  esac
done

# Helper functions
log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  ((ERRORS++))
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
  ((WARNINGS++))
}

log_pass() {
  if $VERBOSE; then
    echo -e "${GREEN}[PASS]${NC} $1"
  fi
  ((PASSED++))
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
  echo ""
  echo -e "${CYAN}==== $1 ====${NC}"
}

# Check if we're in the right directory
if [[ ! -d "$CONTAINERS_DIR" ]]; then
  echo -e "${RED}Error: Must run from nixos-hwc root directory${NC}"
  exit 2
fi

# Create report directory
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/container-lint-$(date +%Y%m%d-%H%M%S).txt"

# Get list of containers
CONTAINERS=$(find "$CONTAINERS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name "_*" -exec basename {} \;)

if [[ -n "$CONTAINER_FILTER" ]]; then
  CONTAINERS=$(echo "$CONTAINERS" | grep "$CONTAINER_FILTER" || true)
  if [[ -z "$CONTAINERS" ]]; then
    echo -e "${RED}No containers match filter: $CONTAINER_FILTER${NC}"
    exit 2
  fi
fi

# Start validation
log_section "Container Consistency Validator"
log_info "Analyzing containers in $CONTAINERS_DIR"
log_info "Report will be saved to: $REPORT_FILE"
echo ""

# Validation functions

validate_file_structure() {
  local container=$1
  local container_path="$CONTAINERS_DIR/$container"

  log_section "File Structure: $container"

  # Check for required files
  if [[ -f "$container_path/index.nix" ]]; then
    log_pass "$container has index.nix"
  else
    log_error "$container missing index.nix"
  fi

  if [[ -f "$container_path/options.nix" ]]; then
    log_pass "$container has options.nix"
  else
    log_error "$container missing options.nix"
  fi

  # Check for either sys.nix OR parts/config.nix (Charter v6 pattern)
  if [[ -f "$container_path/sys.nix" ]] || [[ -f "$container_path/parts/config.nix" ]]; then
    log_pass "$container has implementation file (sys.nix or parts/config.nix)"
  else
    log_error "$container missing both sys.nix and parts/config.nix"
  fi

  # Check for parts directory structure
  if [[ -d "$container_path/parts" ]]; then
    log_pass "$container has parts/ directory"

    # If parts/ exists, expect lib.nix, pkgs.nix, scripts.nix
    for part in config lib pkgs scripts; do
      if [[ -f "$container_path/parts/$part.nix" ]]; then
        log_pass "$container has parts/$part.nix"
      else
        if $VERBOSE; then
          log_warning "$container missing parts/$part.nix (optional)"
        fi
      fi
    done
  fi
}

validate_charter_v6_compliance() {
  local container=$1
  local container_path="$CONTAINERS_DIR/$container"

  log_section "Charter v6 Compliance: $container"

  # Check for assertions section
  local config_file=""
  if [[ -f "$container_path/parts/config.nix" ]]; then
    config_file="$container_path/parts/config.nix"
  elif [[ -f "$container_path/sys.nix" ]]; then
    config_file="$container_path/sys.nix"
  fi

  if [[ -n "$config_file" ]]; then
    if grep -q "assertions = \[" "$config_file" 2>/dev/null; then
      log_pass "$container has assertions section (Charter v6 ✓)"

      # Check for meaningful assertions
      if grep -q "assertion = cfg.network.mode" "$config_file" 2>/dev/null; then
        log_pass "$container validates network mode dependencies"
      fi

      if grep -q "assertion = .*paths\." "$config_file" 2>/dev/null; then
        log_pass "$container validates required paths"
      fi
    else
      log_warning "$container missing assertions section (Charter v6 requirement)"
    fi

    # Check for section headers (Charter v6 style)
    if grep -q "#=====" "$config_file" 2>/dev/null; then
      log_pass "$container uses section headers for clarity"
    else
      if $VERBOSE; then
        log_warning "$container could benefit from section headers"
      fi
    fi

    # Check for comments explaining "why"
    local comment_count=$(grep -c "# " "$config_file" 2>/dev/null || echo "0")
    if [[ $comment_count -gt 5 ]]; then
      log_pass "$container has documentation comments ($comment_count lines)"
    else
      log_warning "$container has minimal documentation ($comment_count comment lines)"
    fi
  fi

  # Check namespace compliance
  if [[ -f "$container_path/options.nix" ]]; then
    if grep -q "hwc.server.containers.$container" "$container_path/options.nix" 2>/dev/null; then
      log_pass "$container uses correct namespace (hwc.server.containers.$container)"
    else
      log_error "$container namespace does not match folder name"
    fi
  fi
}

validate_networking() {
  local container=$1
  local container_path="$CONTAINERS_DIR/$container"

  log_section "Networking Configuration: $container"

  local config_file=""
  if [[ -f "$container_path/parts/config.nix" ]]; then
    config_file="$container_path/parts/config.nix"
  elif [[ -f "$container_path/sys.nix" ]]; then
    config_file="$container_path/sys.nix"
  fi

  if [[ -n "$config_file" ]]; then
    # Check for network mode configuration
    if grep -q "networkMode\|network.mode" "$config_file" 2>/dev/null; then
      log_pass "$container has configurable network mode"
    else
      if grep -q "network=container:gluetun" "$config_file" 2>/dev/null; then
        log_warning "$container hardcodes VPN network mode (should be configurable)"
      elif grep -q "network=media-network" "$config_file" 2>/dev/null; then
        log_warning "$container hardcodes media network mode (should be configurable)"
      fi
    fi

    # Check for proper VPN dependency
    if grep -q "network=container:gluetun" "$config_file" 2>/dev/null; then
      if grep -q 'dependsOn.*"gluetun"' "$config_file" 2>/dev/null; then
        log_pass "$container declares Gluetun dependency (VPN mode)"
      else
        log_error "$container uses Gluetun network but missing dependency"
      fi
    fi

    # Check port binding strategy
    if grep -q "127.0.0.1:[0-9]*:" "$config_file" 2>/dev/null; then
      log_pass "$container binds to localhost (secure default)"
    elif grep -q "0.0.0.0:[0-9]*:" "$config_file" 2>/dev/null; then
      log_warning "$container binds to 0.0.0.0 (exposes to LAN)"
    fi

    # Check for systemd network dependencies
    if grep -q "after.*network-online.target" "$config_file" 2>/dev/null; then
      log_pass "$container waits for network-online.target"
    else
      log_warning "$container missing network-online.target dependency"
    fi

    if grep -q "after.*init-media-network\|hwc-media-network" "$config_file" 2>/dev/null; then
      log_pass "$container waits for media network initialization"
    fi
  fi
}

validate_caddy_integration() {
  local container=$1
  local routes_file="$CONTAINERS_DIR/../routes.nix"

  log_section "Caddy Integration: $container"

  # Skip if no web UI expected (gluetun, recyclarr)
  if [[ "$container" =~ ^(gluetun|recyclarr)$ ]]; then
    log_info "$container does not require Caddy integration (no web UI)"
    return
  fi

  if [[ -f "$routes_file" ]]; then
    if grep -q "name = \"$container\"" "$routes_file" 2>/dev/null; then
      log_pass "$container has Caddy route defined"

      # Check if needsUrlBase is documented
      if grep -B2 -A5 "name = \"$container\"" "$routes_file" 2>/dev/null | grep -q "needsUrlBase" 2>/dev/null; then
        log_pass "$container has needsUrlBase configured"
      fi
    else
      log_warning "$container missing from routes.nix (no Caddy route)"
    fi
  fi
}

validate_resource_limits() {
  local container=$1
  local container_path="$CONTAINERS_DIR/$container"

  log_section "Resource Limits: $container"

  local config_file=""
  if [[ -f "$container_path/parts/config.nix" ]]; then
    config_file="$container_path/parts/config.nix"
  elif [[ -f "$container_path/sys.nix" ]]; then
    config_file="$container_path/sys.nix"
  fi

  if [[ -n "$config_file" ]]; then
    if grep -q -- "--memory=" "$config_file" 2>/dev/null; then
      log_pass "$container has memory limit configured"
    else
      log_warning "$container missing memory limit (uses mkContainer default)"
    fi

    if grep -q -- "--cpus=" "$config_file" 2>/dev/null; then
      log_pass "$container has CPU limit configured"
    else
      log_warning "$container missing CPU limit (uses mkContainer default)"
    fi

    # Check for sensible defaults
    if grep -q -- "--memory=2g" "$config_file" 2>/dev/null; then
      log_pass "$container uses standard 2GB memory limit"
    fi
  fi
}

validate_environment_variables() {
  local container=$1
  local container_path="$CONTAINERS_DIR/$container"

  log_section "Environment Variables: $container"

  local config_file=""
  if [[ -f "$container_path/parts/config.nix" ]]; then
    config_file="$container_path/parts/config.nix"
  elif [[ -f "$container_path/sys.nix" ]]; then
    config_file="$container_path/sys.nix"
  fi

  if [[ -n "$config_file" ]]; then
    # Check for required environment variables
    for var in PUID PGID TZ; do
      if grep -q "$var" "$config_file" 2>/dev/null; then
        log_pass "$container sets $var environment variable"
      else
        log_warning "$container missing $var environment variable"
      fi
    done

    # Check for URL base configuration (if applicable)
    if [[ "$container" =~ ^(sonarr|radarr|lidarr|prowlarr|navidrome|sabnzbd)$ ]]; then
      local urlbase_var="${container^^}__URLBASE"
      if grep -qi "URLBASE\|URL_BASE" "$config_file" 2>/dev/null; then
        log_pass "$container configures URL base for subpath routing"
      else
        log_warning "$container may need URL base configuration"
      fi
    fi
  fi
}

validate_secrets_handling() {
  local container=$1
  local container_path="$CONTAINERS_DIR/$container"

  log_section "Secrets Handling: $container"

  local config_file=""
  if [[ -f "$container_path/parts/config.nix" ]]; then
    config_file="$container_path/parts/config.nix"
  elif [[ -f "$container_path/sys.nix" ]]; then
    config_file="$container_path/sys.nix"
  fi

  if [[ -n "$config_file" ]]; then
    # Check for agenix integration
    if grep -q "age.secrets\|agenix.service" "$config_file" 2>/dev/null; then
      log_pass "$container uses agenix for secrets"

      if grep -q "chmod 600" "$config_file" 2>/dev/null; then
        log_pass "$container sets restrictive permissions on secrets"
      fi
    fi

    # Check for hardcoded secrets (anti-pattern)
    if grep -q "password.*=.*\"" "$config_file" 2>/dev/null; then
      log_error "$container may contain hardcoded secrets!"
    fi
  fi
}

# Main validation loop
log_info "Found $(echo "$CONTAINERS" | wc -l) containers to validate"
echo ""

for container in $CONTAINERS; do
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}Container: $container${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  validate_file_structure "$container"
  validate_charter_v6_compliance "$container"
  validate_networking "$container"
  validate_caddy_integration "$container"
  validate_resource_limits "$container"
  validate_environment_variables "$container"
  validate_secrets_handling "$container"
done

# Summary
echo ""
echo ""
log_section "Validation Summary"
echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASSED"
echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "  ${RED}Errors:${NC}   $ERRORS"
echo ""

# Generate detailed report
{
  echo "Container Consistency Validation Report"
  echo "========================================"
  echo "Date: $(date)"
  echo "Containers Analyzed: $(echo "$CONTAINERS" | wc -l)"
  echo ""
  echo "Summary:"
  echo "  Passed:   $PASSED"
  echo "  Warnings: $WARNINGS"
  echo "  Errors:   $ERRORS"
  echo ""
  echo "Containers:"
  for container in $CONTAINERS; do
    echo "  - $container"
  done
  echo ""
  echo "For detailed analysis, see:"
  echo "  docs/architecture/CONTAINER_CONSISTENCY_ANALYSIS.md"
} > "$REPORT_FILE"

log_info "Full report saved to: $REPORT_FILE"

# Exit with appropriate code
if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo -e "${RED}Validation failed with $ERRORS errors${NC}"
  echo -e "${YELLOW}See report for details: $REPORT_FILE${NC}"
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}Validation completed with $WARNINGS warnings${NC}"
  echo -e "Consider addressing warnings for better compliance"
  exit 0
else
  echo ""
  echo -e "${GREEN}All validations passed!${NC}"
  exit 0
fi
