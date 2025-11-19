#!/usr/bin/env bash
set -euo pipefail

# Grebuild - Git commit + NixOS rebuild workflow with notifications
# Enhanced workflow: commit → test → rebuild → push → AI docs
#
# Usage: grebuild.sh "commit message" [OPTIONS]
#
# Examples:
#   grebuild.sh "Update configuration"
#   grebuild.sh "Add new service" --target hwc-server
#   grebuild.sh "Fix networking" --skip-test
#   grebuild.sh "Update docs" --dry-run

# Configuration (can be overridden by environment variables)
readonly DEFAULT_FLAKE_TARGET="hwc-server"
readonly DEFAULT_NOTIFY_URL="https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts"
readonly DEFAULT_AI_DOCS_SERVICE="post-rebuild-ai-docs"

# Script state
DRY_RUN=false
SKIP_TEST=false
SKIP_PUSH=false
USE_SUDO=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging functions
log_header() { echo -e "\n${BOLD}${BLUE}$*${NC}"; }
log_info() { echo -e "${GREEN}✅${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $*"; }
log_error() { echo -e "${RED}❌${NC} $*" >&2; }
log_step() { echo -e "\n${BOLD}$*${NC}"; }

# Usage information
show_usage() {
    cat << EOF
${BOLD}Grebuild - Git + NixOS Rebuild Workflow${NC}

Automated workflow for committing, testing, rebuilding, and pushing NixOS configurations.

${BOLD}USAGE:${NC}
    $(basename "$0") "commit message" [OPTIONS]

${BOLD}OPTIONS:${NC}
    -t, --target NAME       Flake target to rebuild
                            (default: ${DEFAULT_FLAKE_TARGET})
    -n, --dry-run           Show what would be done without making changes
    -s, --skip-test         Skip nixos-rebuild test step (faster but riskier)
    -p, --skip-push         Skip git push (local changes only)
    --no-sudo               Don't use sudo for git/rebuild commands
    --notify-url URL        Notification endpoint URL
                            (default: ${DEFAULT_NOTIFY_URL})
    -h, --help              Show this help message

${BOLD}EXAMPLES:${NC}
    # Standard workflow
    $(basename "$0") "Update services configuration"

    # Different flake target
    $(basename "$0") "Update laptop config" --target hwc-laptop

    # Skip test for faster rebuild (use with caution)
    $(basename "$0") "Minor tweak" --skip-test

    # Dry run to preview steps
    $(basename "$0") "Testing changes" --dry-run

    # Local only (no push)
    $(basename "$0") "WIP changes" --skip-push

${BOLD}ENVIRONMENT VARIABLES:${NC}
    FLAKE_TARGET            Override default flake target
    NOTIFY_URL              Override notification URL
    AI_DOCS_SERVICE         Override AI docs systemd service name

${BOLD}WORKFLOW STEPS:${NC}
    1. Validate git repository and configuration
    2. Commit changes to git
    3. Test NixOS configuration (optional with --skip-test)
    4. Apply NixOS rebuild
    5. Push to remote (optional with --skip-push)
    6. Trigger AI documentation generation
    7. Send notifications

${BOLD}PREREQUISITES:${NC}
    - Git repository with changes to commit
    - NixOS flake configuration
    - Git configured for push access
    - sudo access (unless --no-sudo specified)
    - curl for notifications (optional)

EOF
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        log_error "Missing commit message"
        echo ""
        show_usage
        exit 2
    fi

    COMMIT_MESSAGE="$1"
    shift

    FLAKE_TARGET="${FLAKE_TARGET:-$DEFAULT_FLAKE_TARGET}"
    NOTIFY_URL="${NOTIFY_URL:-$DEFAULT_NOTIFY_URL}"
    AI_DOCS_SERVICE="${AI_DOCS_SERVICE:-$DEFAULT_AI_DOCS_SERVICE}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                log_warn "DRY RUN MODE - No changes will be made"
                shift
                ;;
            -s|--skip-test)
                SKIP_TEST=true
                shift
                ;;
            -p|--skip-push)
                SKIP_PUSH=true
                shift
                ;;
            --no-sudo)
                USE_SUDO=false
                shift
                ;;
            -t|--target)
                FLAKE_TARGET="$2"
                shift 2
                ;;
            --notify-url)
                NOTIFY_URL="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_usage
                exit 2
                ;;
        esac
    done

    # Check if we need sudo
    if [[ "$USE_SUDO" == false ]] && [[ $EUID -ne 0 ]]; then
        # Check if git repo is owned by current user
        if [[ -d .git ]] && [[ $(stat -c '%u' .git) -ne $EUID ]]; then
            USE_SUDO=true
            log_warn "Git repository requires sudo access"
        fi
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_step "🔍 Validating prerequisites..."

    # Check if in git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a git repository"
        exit 1
    fi
    log_info "Git repository found"

    # Check for uncommitted changes
    if [[ -z "$(git status --porcelain)" ]]; then
        log_warn "No changes to commit"
    fi

    # Check if flake.nix exists
    if [[ ! -f "flake.nix" ]]; then
        log_error "flake.nix not found in current directory"
        exit 1
    fi
    log_info "NixOS flake found"

    # Check dependencies
    local missing=()
    for cmd in git nixos-rebuild systemctl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
    log_info "All dependencies found"
}

# Execute command with dry-run and sudo support
execute() {
    local cmd=("$@")

    if [[ "$USE_SUDO" == true ]] && [[ "${cmd[0]}" != "sudo" ]]; then
        cmd=("sudo" "${cmd[@]}")
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] ${cmd[*]}"
        return 0
    else
        "${cmd[@]}"
    fi
}

# Send notification
send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "Would send notification: $title"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_warn "curl not found, skipping notification"
        return 0
    fi

    if ! curl -sf \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -d "$message" \
        "$NOTIFY_URL" >/dev/null 2>&1; then
        log_warn "Failed to send notification (non-fatal)"
    fi
}

# Git commit workflow
git_commit() {
    log_step "📦 Git commit workflow"

    log_info "Adding changes to git..."
    if ! execute git add .; then
        log_error "Failed to stage changes"
        return 1
    fi

    log_info "Committing with message: $COMMIT_MESSAGE"
    if ! execute git commit -m "$COMMIT_MESSAGE"; then
        log_error "Failed to commit changes"
        return 1
    fi

    # Capture commit info
    if [[ "$DRY_RUN" == false ]]; then
        COMMIT_HASH=$(git rev-parse HEAD)
        SHORT_HASH="${COMMIT_HASH:0:8}"
        readonly COMMIT_HASH SHORT_HASH
        log_info "Committed: $SHORT_HASH"
    else
        COMMIT_HASH="dry-run"
        SHORT_HASH="dry-run"
        readonly COMMIT_HASH SHORT_HASH
    fi
}

# Test NixOS configuration
test_configuration() {
    if [[ "$SKIP_TEST" == true ]]; then
        log_step "🧪 Skipping test (--skip-test specified)"
        return 0
    fi

    log_step "🧪 Testing NixOS configuration..."

    if ! execute nixos-rebuild test --flake ".#${FLAKE_TARGET}"; then
        log_error "Configuration test failed"

        send_notification \
            "❌ NixOS Test Failed" \
            "Configuration test failed for: $COMMIT_MESSAGE ($SHORT_HASH). Changes not applied." \
            "high"

        return 1
    fi

    log_info "Test successful"
}

# Apply NixOS rebuild
apply_rebuild() {
    log_step "🔄 Applying NixOS rebuild..."

    if ! execute nixos-rebuild switch --flake ".#${FLAKE_TARGET}"; then
        log_error "Rebuild failed"

        send_notification \
            "❌ NixOS Rebuild Failed" \
            "NixOS rebuild failed for commit: $COMMIT_MESSAGE ($SHORT_HASH). Check system logs." \
            "urgent"

        return 1
    fi

    log_info "Rebuild successful"
}

# Push to remote
push_to_remote() {
    if [[ "$SKIP_PUSH" == true ]]; then
        log_step "📤 Skipping push (--skip-push specified)"
        PUSH_STATUS="⚠️ Skipped (--skip-push)"
        readonly PUSH_STATUS
        return 0
    fi

    log_step "📤 Pushing to remote repository..."

    if execute git push; then
        log_info "Push successful"
        PUSH_STATUS="✅ Pushed to remote"
        readonly PUSH_STATUS
        return 0
    else
        log_warn "Git push failed - changes are local only"
        PUSH_STATUS="⚠️ Push failed - local changes only"
        readonly PUSH_STATUS

        send_notification \
            "⚠️ Git Push Failed" \
            "NixOS rebuild succeeded but git push failed. Changes are local only. Commit: $SHORT_HASH" \
            "default"

        return 0  # Non-fatal
    fi
}

# Trigger AI documentation
trigger_ai_docs() {
    log_step "🤖 Triggering AI documentation processing..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "Would start systemd service: $AI_DOCS_SERVICE"
        return 0
    fi

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${AI_DOCS_SERVICE}.service"; then
        log_warn "AI docs service not found: $AI_DOCS_SERVICE"
        return 0
    fi

    # Start service in background
    if execute systemctl start "$AI_DOCS_SERVICE" & then
        log_info "AI documentation processing started"
    else
        log_warn "Failed to start AI docs service (non-fatal)"
    fi
}

# Send completion notification
send_completion_notification() {
    log_step "📱 Sending completion notification..."

    local message
    message="Successfully rebuilt and deployed: $COMMIT_MESSAGE ($SHORT_HASH)

$PUSH_STATUS
AI documentation processing started"

    send_notification \
        "✅ NixOS Rebuild Complete" \
        "$message" \
        "default"
}

# Show completion summary
show_summary() {
    log_header "🎉 Grebuild Complete!"

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        log_warn "DRY RUN completed - no changes were made"
        echo "Run without --dry-run to apply changes."
        return 0
    fi

    cat << EOF

${BOLD}Summary:${NC}
  Commit:      $SHORT_HASH
  Message:     $COMMIT_MESSAGE
  Target:      $FLAKE_TARGET
  Push Status: $PUSH_STATUS

${BOLD}Next Steps:${NC}
  • AI documentation is processing in the background
  • You'll receive a notification when docs are updated
  • Check system logs if you encounter any issues

EOF

    log_info "Workflow complete!"
}

# Main function
main() {
    # Parse arguments
    parse_args "$@"

    # Show header
    log_header "🚀 Grebuild Workflow"
    echo "Commit message: $COMMIT_MESSAGE"
    echo "Flake target: $FLAKE_TARGET"

    # Validate prerequisites
    validate_prerequisites || exit 1

    # Execute workflow steps
    git_commit || {
        log_error "Git commit failed"
        exit 1
    }

    test_configuration || {
        log_error "Configuration test failed - not proceeding"
        exit 1
    }

    apply_rebuild || {
        log_error "Rebuild failed - not pushing changes"
        exit 1
    }

    push_to_remote  # Non-fatal

    trigger_ai_docs  # Non-fatal

    send_completion_notification  # Non-fatal

    # Show summary
    show_summary

    exit 0
}

# Execute main function
main "$@"
