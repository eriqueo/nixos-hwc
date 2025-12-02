#!/usr/bin/env bash
# journal-errors - Summarize and deduplicate journalctl errors
#
# Usage: journal-errors [time-window] [service]
# Examples:
#   journal-errors                    # Last 10 minutes, all services
#   journal-errors "1 hour ago"       # Last hour, all services
#   journal-errors "1 hour ago" tdarr # Last hour, tdarr only
#
# Dependencies: journalctl, awk, sed, grep, wc, sort, uniq, tail (standard on NixOS)
# Location: workspace/scripts/monitoring/journal-errors.sh
# Invoked by: Shell function in domains/home/environment/shell/index.nix

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
echo ""

# Get raw errors
RAW_ERRORS=$(eval "$JOURNAL_CMD" 2>/dev/null || echo "")

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
