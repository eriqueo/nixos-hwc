#!/usr/bin/env bash
# Receipt OCR Pipeline Monitoring Script
#
# This script checks the health of the receipts OCR pipeline and sends
# alerts if issues are detected.
#
# Usage:
#   ./receipt-monitor.sh [--notify]
#
# Options:
#   --notify    Send notifications via ntfy on failures

set -euo pipefail

NOTIFY=false
NTFY_URL="${NTFY_URL:-http://localhost:8080}"
NTFY_TOPIC="${NTFY_TOPIC:-receipts-monitoring}"
API_URL="${API_URL:-http://localhost:8001}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --notify)
            NOTIFY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-3}"

    if [ "$NOTIFY" = true ]; then
        curl -s -X POST "$NTFY_URL/topic/$NTFY_TOPIC" \
            -H "Title: $title" \
            -H "Priority: $priority" \
            -H "Tags: warning,receipts" \
            -d "$message" > /dev/null 2>&1 || true
    fi
}

# Check functions
check_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        log_ok "$service is running"
        return 0
    else
        log_error "$service is not running"
        send_notification "Service Down" "$service is not running" 5
        return 1
    fi
}

check_api() {
    local response
    if response=$(curl -s -f "$API_URL/health" 2>&1); then
        log_ok "OCR API is responding"

        # Check database status
        if echo "$response" | grep -q '"status": "connected"'; then
            log_ok "Database is connected"
        else
            log_error "Database is not connected"
            send_notification "Database Error" "OCR service cannot connect to database" 5
            return 1
        fi

        return 0
    else
        log_error "OCR API is not responding"
        send_notification "API Down" "OCR API is not responding at $API_URL" 5
        return 1
    fi
}

check_stats() {
    local stats
    if ! stats=$(curl -s -f "$API_URL/api/stats" 2>&1); then
        log_warn "Could not retrieve processing stats"
        return 1
    fi

    # Extract key metrics (basic parsing, assumes JSON response)
    local total=$(echo "$stats" | grep -o '"total_receipts":[0-9]*' | grep -o '[0-9]*' || echo "0")
    local failed=$(echo "$stats" | grep -o '"failed":[0-9]*' | grep -o '[0-9]*' || echo "0")
    local pending_review=$(echo "$stats" | grep -o '"pending_review":[0-9]*' | grep -o '[0-9]*' || echo "0")

    echo ""
    echo "Processing Statistics:"
    echo "  Total Receipts: $total"
    echo "  Failed: $failed"
    echo "  Pending Review: $pending_review"

    # Check failure rate
    if [ "$total" -gt 0 ]; then
        local failure_rate=$((failed * 100 / total))
        if [ "$failure_rate" -gt 10 ]; then
            log_warn "High failure rate: ${failure_rate}%"
            send_notification "High Failure Rate" "Receipt processing failure rate is ${failure_rate}%" 4
        fi
    fi

    # Check pending review queue
    if [ "$pending_review" -gt 50 ]; then
        log_warn "High review queue: $pending_review items"
        send_notification "Review Queue Alert" "$pending_review receipts pending review" 3
    fi
}

check_disk_space() {
    local usage
    usage=$(df -h /hot/receipts 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ -z "$usage" ]; then
        log_warn "Could not check disk space for /hot/receipts"
        return 1
    fi

    if [ "$usage" -gt 90 ]; then
        log_error "Disk space critical: ${usage}% used"
        send_notification "Disk Space Critical" "/hot/receipts is ${usage}% full" 5
        return 1
    elif [ "$usage" -gt 80 ]; then
        log_warn "Disk space warning: ${usage}% used"
        send_notification "Disk Space Warning" "/hot/receipts is ${usage}% full" 3
    else
        log_ok "Disk space OK: ${usage}% used"
    fi
}

check_database() {
    if sudo -u postgres psql heartwood_business -c "SELECT 1 FROM receipts LIMIT 1" > /dev/null 2>&1; then
        log_ok "Database is accessible"
        return 0
    else
        log_error "Database is not accessible"
        send_notification "Database Error" "Cannot access heartwood_business database" 5
        return 1
    fi
}

# Main monitoring
echo "=== Receipt OCR Pipeline Health Check ==="
echo "Time: $(date)"
echo ""

ERRORS=0

echo "Service Status:"
check_service "receipts-ocr" || ((ERRORS++))
check_service "postgresql" || ((ERRORS++))
check_service "ollama" || ((ERRORS++))
check_service "n8n" || ((ERRORS++))

echo ""
echo "API Health:"
check_api || ((ERRORS++))

echo ""
echo "Database Health:"
check_database || ((ERRORS++))

echo ""
echo "Resource Usage:"
check_disk_space || ((ERRORS++))

echo ""
check_stats || ((ERRORS++))

echo ""
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ]; then
    log_ok "All checks passed"
    exit 0
else
    log_error "$ERRORS check(s) failed"
    exit 1
fi
