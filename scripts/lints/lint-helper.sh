#!/usr/bin/env bash

# HWC Lint Comparison Helper
# Saves lint output with timestamps for easy comparison

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly LINT_SCRIPT="$SCRIPT_DIR/charter-lint.sh"
readonly REPORTS_DIR="$REPO_ROOT/.lint-reports"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    printf "${BLUE}[LINT-COMPARE]${NC} %s\n" "$1"
}

success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

# Create reports directory
mkdir -p "$REPORTS_DIR"

# Generate timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Report filename
REPORT_FILE="$REPORTS_DIR/lint_${TIMESTAMP}_${BRANCH}_${COMMIT}.txt"

log "Running HWC Charter lint and saving to report..."
log "Report: ${REPORT_FILE#$REPO_ROOT/}"

# Run the linter and save output
if "$LINT_SCRIPT" "$@" 2>&1 | tee "$REPORT_FILE"; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
fi

# Add metadata to report
{
    echo ""
    echo "========================================="
    echo "METADATA"
    echo "========================================="
    echo "Timestamp: $(date)"
    echo "Branch: $BRANCH"
    echo "Commit: $COMMIT"
    echo "Arguments: $*"
    echo "Exit Code: $EXIT_CODE"
    echo "Repository: $REPO_ROOT"
} >> "$REPORT_FILE"

success "Report saved: ${REPORT_FILE#$REPO_ROOT/}"

# Show comparison with previous report if available
PREV_REPORT=$(find "$REPORTS_DIR" -name "lint_*.txt" -type f | sort | tail -2 | head -1)
if [[ -n "$PREV_REPORT" && "$PREV_REPORT" != "$REPORT_FILE" ]]; then
    log "Comparing with previous report..."
    
    # Extract error/warning counts
    PREV_ERRORS=$(grep "Found [0-9]* error(s)" "$PREV_REPORT" | grep -o "[0-9]*" | head -1 || echo "0")
    PREV_WARNINGS=$(grep "Found [0-9]* warning(s)" "$PREV_REPORT" | grep -o "[0-9]*" | head -1 || echo "0")
    
    CURR_ERRORS=$(grep "Found [0-9]* error(s)" "$REPORT_FILE" | grep -o "[0-9]*" | head -1 || echo "0")
    CURR_WARNINGS=$(grep "Found [0-9]* warning(s)" "$REPORT_FILE" | grep -o "[0-9]*" | head -1 || echo "0")
    
    echo ""
    echo "📊 COMPARISON WITH PREVIOUS RUN:"
    echo "Previous: $PREV_ERRORS errors, $PREV_WARNINGS warnings"
    echo "Current:  $CURR_ERRORS errors, $CURR_WARNINGS warnings"
    
    ERROR_DIFF=$((CURR_ERRORS - PREV_ERRORS))
    WARNING_DIFF=$((CURR_WARNINGS - PREV_WARNINGS))
    
    if [[ $ERROR_DIFF -lt 0 ]]; then
        success "✅ Errors reduced by ${ERROR_DIFF#-}"
    elif [[ $ERROR_DIFF -gt 0 ]]; then
        warn "❌ Errors increased by $ERROR_DIFF"
    fi
    
    if [[ $WARNING_DIFF -lt 0 ]]; then
        success "✅ Warnings reduced by ${WARNING_DIFF#-}"
    elif [[ $WARNING_DIFF -gt 0 ]]; then
        warn "❌ Warnings increased by $WARNING_DIFF"
    fi
fi

echo ""
log "Available commands:"
echo "  📁 ls $REPORTS_DIR"
echo "  📄 cat $REPORT_FILE"
echo "  🔍 diff <(head -n -10 prev_report.txt) <(head -n -10 current_report.txt)"

exit $EXIT_CODE
