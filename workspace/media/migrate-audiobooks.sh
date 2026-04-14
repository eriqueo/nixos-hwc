#!/usr/bin/env bash
#
# migrate-audiobooks.sh - One-time migration for existing audiobooks
#
# Migrates existing audiobooks from /mnt/hot/downloads/ to Audiobookshelf library.
# Run once, then event-driven processing takes over.
#
# Usage:
#   ./migrate-audiobooks.sh           # Dry run (shows what would be done)
#   ./migrate-audiobooks.sh --execute # Actually perform the migration
#
# This script:
# 1. Scans the qBittorrent books download directory
# 2. Copies all audiobook directories to /mnt/media/books/audiobooks
# 3. Creates .abs-copied marker files to prevent re-processing
# 4. Triggers Audiobookshelf library scan

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPIER_SCRIPT="/mnt/hot/downloads/scripts/audiobook-copier.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Migrate existing audiobooks to Audiobookshelf library.

Options:
    --execute     Actually perform the migration (default is dry-run)
    --help        Show this help message
    -v, --verbose Enable verbose output

Examples:
    $(basename "$0")              # Dry run - shows what would be copied
    $(basename "$0") --execute    # Actually copy audiobooks
EOF
}

main() {
    local dry_run=true
    local verbose=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --execute)
                dry_run=false
                shift
                ;;
            -v|--verbose)
                verbose="-v"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Check if copier script exists
    if [[ ! -f "$COPIER_SCRIPT" ]]; then
        log_error "Audiobook copier script not found: $COPIER_SCRIPT"
        log_info "Run 'sudo systemctl start audiobook-copier-install' to deploy the script"
        exit 1
    fi

    # Build command
    local cmd="python3 $COPIER_SCRIPT --scan-all $verbose"

    if $dry_run; then
        log_info "=== DRY RUN MODE ==="
        log_info "Add --execute to actually perform the migration"
        cmd="$cmd --dry-run"
    else
        log_warn "=== EXECUTE MODE ==="
        log_info "Copying audiobooks to Audiobookshelf library..."
    fi

    echo ""
    log_info "Running: $cmd"
    echo ""

    # Execute
    eval "$cmd"

    echo ""
    if $dry_run; then
        log_info "Dry run complete. Use --execute to actually copy files."
    else
        log_info "Migration complete!"
        log_info "Check Audiobookshelf to verify the audiobooks appeared."
    fi
}

main "$@"
