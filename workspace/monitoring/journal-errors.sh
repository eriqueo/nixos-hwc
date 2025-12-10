#!/usr/bin/env bash
# journal-errors - Summarize and deduplicate journalctl errors
#
# Usage: journal-errors [time-window] [service] [--show-all]
# Examples:
#   journal-errors                    # Last 10 minutes, all services (with filters)
#   journal-errors "1 hour ago"       # Last hour, all services (with filters)
#   journal-errors "1 hour ago" tdarr # Last hour, tdarr only
#   journal-errors "10 minutes ago" "" --show-all  # Bypass all exclusion filters
#
# Configuration:
#   Edit EXCLUDE_SERVICES and EXCLUDE_PATTERNS arrays below to customize filtering
#
# Dependencies: journalctl, awk, sed, grep, wc, sort, uniq, tail (standard on NixOS)
# Location: workspace/monitoring/journal-errors.sh
# Invoked by: Shell wrapper in domains/home/environment/shell/parts/journal-errors.nix

set -euo pipefail

#==============================================================================
# DEPENDENCY VERIFICATION
#==============================================================================
# Standard tools - should always exist on NixOS, but verify for robustness

REQUIRED_COMMANDS=(journalctl awk sed grep wc sort uniq tail)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' not found" >&2
    echo "This should not happen on a standard NixOS system." >&2
    exit 127
  fi
done

#==============================================================================
# CONFIGURATION
#==============================================================================

TIME_WINDOW="${1:-10 minutes ago}"
SERVICE="${2:-}"
SHOW_ALL=false

# Check for --show-all flag in any position
for arg in "$@"; do
  if [[ "$arg" == "--show-all" ]]; then
    SHOW_ALL=true
    break
  fi
done

# Exclusion patterns (grep -E compatible regex)
# Add services or patterns to exclude from error reports
EXCLUDE_SERVICES=(
  "soularr"
)

EXCLUDE_PATTERNS=(
  "INFO\|"
  "DEBUG\|"
  "\[INFO"
  "\[DEBUG"
  "No releases wanted"
  "Server stats"
  "No expired messages"
  "No expired attachments"
  "Removed 0 empty topic"
  "Deleted 0 stale visitor"
  "Manager finished"
  "Pruned messages"
)

# Colors
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

#==============================================================================
# MAIN LOGIC
#==============================================================================

echo -e "${BOLD}${BLUE}=== System Errors Summary ===${NC}"
echo -e "${CYAN}Time window: ${TIME_WINDOW}${NC}"

# Build journalctl command
JOURNAL_CMD="journalctl --since \"${TIME_WINDOW}\" -p err --no-pager -o short-iso"
if [ -n "$SERVICE" ]; then
    JOURNAL_CMD="$JOURNAL_CMD -u ${SERVICE}"
    echo -e "${CYAN}Service filter: ${SERVICE}${NC}"
fi

# Show filter status
if [ "$SHOW_ALL" = true ]; then
    echo -e "${YELLOW}Exclusion filters: DISABLED (--show-all)${NC}"
else
    echo -e "${CYAN}Exclusion filters: ${#EXCLUDE_SERVICES[@]} services, ${#EXCLUDE_PATTERNS[@]} patterns${NC}"
    echo -e "${CYAN}(Use --show-all to bypass filters)${NC}"
fi
echo ""

# Get raw errors and apply filters
RAW_ERRORS=$(eval "$JOURNAL_CMD" 2>/dev/null || echo "")

# Apply exclusion filters (unless --show-all is specified)
if [ "$SHOW_ALL" = false ]; then
  # Apply service exclusions
  for service in "${EXCLUDE_SERVICES[@]}"; do
    RAW_ERRORS=$(echo "$RAW_ERRORS" | grep -v "$service" || echo "")
  done

  # Apply pattern exclusions
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    RAW_ERRORS=$(echo "$RAW_ERRORS" | grep -v "$pattern" || echo "")
  done
fi

if [ -z "$RAW_ERRORS" ]; then
    echo -e "${GREEN}✓ No errors found!${NC}"
    exit 0
fi

# Count total errors
TOTAL_ERRORS=$(echo "$RAW_ERRORS" | wc -l)
echo -e "${YELLOW}Total error entries: ${TOTAL_ERRORS}${NC}"
echo ""

# Deduplicate and count error types
echo -e "${BOLD}${BLUE}=== Error Summary (deduplicated) ===${NC}"
echo "$RAW_ERRORS" | \
    # Remove timestamps and hostnames for grouping
    sed -E 's/^[^ ]+ [^ ]+ //' | \
    # Group and count duplicates
    sort | uniq -c | sort -rn | \
    # Format output with colors
    while read -r count message; do
        if [ "$count" -gt 10 ]; then
            echo -e "${RED}[${count}x]${NC} ${message}"
        elif [ "$count" -gt 5 ]; then
            echo -e "${YELLOW}[${count}x]${NC} ${message}"
        else
            echo -e "${CYAN}[${count}x]${NC} ${message}"
        fi
    done

echo ""
echo -e "${BOLD}${BLUE}=== Top 5 Most Recent Errors ===${NC}"
echo "$RAW_ERRORS" | tail -5

echo ""
echo -e "${CYAN}Tip: Run 'journalctl --since \"${TIME_WINDOW}\" -p err' for full details${NC}"
if [ -z "$SERVICE" ]; then
    echo -e "${CYAN}Tip: Add service name to filter: journal-errors \"${TIME_WINDOW}\" podman-tdarr${NC}"
fi
if [ "$SHOW_ALL" = false ]; then
    echo -e "${CYAN}Tip: Use 'journal-errors \"${TIME_WINDOW}\" \"\" --show-all' to see all errors without filters${NC}"
fi
