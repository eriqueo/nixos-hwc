#!/usr/bin/env bash
# Grebuild - Git commit + NixOS rebuild workflow
# Enhanced workflow: commit → test → rebuild → push → AI docs
#
# Usage: grebuild.sh "commit message" [OPTIONS]
#
# Dependencies: git, nixos-rebuild, sudo, systemctl (standard on NixOS)
# Location: workspace/nixos/grebuild.sh
# Invoked by: Shell wrapper in domains/home/environment/shell/parts/grebuild.nix

set -euo pipefail

#==============================================================================
# DEPENDENCY VERIFICATION
#==============================================================================
# Standard tools - should always exist on NixOS, but verify for robustness

REQUIRED_COMMANDS=(git nixos-rebuild sudo systemctl)

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
#
# Examples:
#   grebuild.sh "Update configuration"
#   grebuild.sh "Add new service" --target hwc-server
#   grebuild.sh "Fix networking" --skip-test
#   grebuild.sh "Update docs" --dry-run

# Auto-detect current machine hostname for default target
DETECTED_HOSTNAME=$(hostname)
case "$DETECTED_HOSTNAME" in
  hwc-laptop)
    readonly DEFAULT_FLAKE_TARGET="hwc-laptop"
    ;;
  hwc-server)
    readonly DEFAULT_FLAKE_TARGET="hwc-server"
    ;;
  *)
    # Fallback: try to detect from hostname pattern
    echo "Warning: Unknown hostname '$DETECTED_HOSTNAME', defaulting to hwc-server" >&2
    readonly DEFAULT_FLAKE_TARGET="hwc-server"
    ;;
esac

# Configuration (can be overridden by environment variables)
readonly DEFAULT_AI_DOCS_SERVICE="post-rebuild-ai-docs"

# Script state
DRY_RUN=false
SKIP_TEST=false
SKIP_PUSH=false
SKIP_COMMIT=false
USE_SUDO=false
AUTO_YES=false

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

# Prompt user for yes/no (returns 0 for yes, 1 for no)
prompt_user() {
    local prompt="$1"

    # Auto-yes mode
    if [[ "$AUTO_YES" == true ]]; then
        echo -e "${prompt} ${GREEN}[auto-yes]${NC}"
        return 0
    fi

    # Dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${prompt} ${YELLOW}[dry-run: would prompt]${NC}"
        return 0
    fi

    # Interactive prompt
    while true; do
        read -rp "$(echo -e "${prompt} ${BOLD}[y/N]${NC} ")" response
        response=${response:-n}  # Default to 'n' if empty (Enter key)
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo]|"")
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Usage information
show_usage() {
    cat << EOF
${BOLD}Grebuild - Git + NixOS Rebuild Workflow${NC}

Automated workflow for committing, testing, rebuilding, and pushing NixOS configurations.

${BOLD}USAGE:${NC}
    $(basename "$0") "commit message" [OPTIONS]

${BOLD}OPTIONS:${NC}
    -t, --target NAME       Flake target to rebuild
                            (default: auto-detected from hostname)
    -n, --dry-run           Show what would be done without making changes
    -s, --skip-test         Skip nixos-rebuild test step (faster but riskier)
    -p, --skip-push         Skip git push prompt and push step entirely
    -y, --yes               Skip all prompts, auto-answer yes (including push)
    --no-sudo               Don't use sudo for git/rebuild commands
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
    AI_DOCS_SERVICE         Override AI docs systemd service name

${BOLD}WORKFLOW STEPS:${NC}
    1. Validate git repository and configuration
    2. Commit changes to git
    3. Test NixOS configuration (optional with --skip-test)
    4. Apply NixOS rebuild
    5. Prompt to push to remote (can skip interactively or with --skip-push)
    6. Trigger AI documentation generation

${BOLD}PREREQUISITES:${NC}
    - Git repository with changes to commit
    - NixOS flake configuration
    - Git configured for push access
    - sudo access (unless --no-sudo specified)

EOF
}

# Parse command line arguments
parse_args() {
    # Check for help flag before anything else
    if [[ $# -eq 0 ]]; then
        log_error "Missing commit message"
        echo ""
        show_usage
        exit 2
    fi

    # Handle --help/-h as first argument
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi

    COMMIT_MESSAGE="$1"
    shift

    FLAKE_TARGET="${FLAKE_TARGET:-$DEFAULT_FLAKE_TARGET}"
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
            -y|--yes)
                AUTO_YES=true
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

# Validate prerequisites and handle git changes interactively
validate_prerequisites() {
    log_step "🔍 Validating prerequisites..."

    # Check if in git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a git repository"
        exit 1
    fi
    log_info "Git repository found"

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

    # Check for git changes and prompt user
    local git_changes=$(git status --porcelain)

    if [[ -z "$git_changes" ]]; then
        # No changes to commit
        log_info "No changes to commit"
        echo ""
        if prompt_user "📦 No changes detected. Rebuild anyway?"; then
            SKIP_COMMIT=true
            log_info "Proceeding without commit"
        else
            log_info "Cancelled by user"
            exit 0
        fi
    else
        # Show changes
        log_info "Found changes:"
        echo ""
        git status --short
        echo ""

        if prompt_user "📦 Commit these changes and rebuild?"; then
            SKIP_COMMIT=false
            log_info "Will commit and rebuild"
        else
            # User doesn't want to commit
            if prompt_user "🔄 Rebuild without committing?"; then
                SKIP_COMMIT=true
                log_info "Will rebuild without committing"
            else
                log_info "Cancelled by user"
                exit 0
            fi
        fi
    fi
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

# Git commit workflow
git_commit() {
    if [[ "$SKIP_COMMIT" == true ]]; then
        log_step "📦 Skipping git commit"
        COMMIT_HASH="no-commit"
        SHORT_HASH="no-commit"
        readonly COMMIT_HASH SHORT_HASH
        return 0
    fi

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

    # Capture commit info (not readonly - readme_butler may amend and update)
    if [[ "$DRY_RUN" == false ]]; then
        COMMIT_HASH=$(git rev-parse HEAD)
        SHORT_HASH="${COMMIT_HASH:0:8}"
        log_info "Committed: $SHORT_HASH"
    else
        COMMIT_HASH="dry-run"
        SHORT_HASH="dry-run"
    fi
}

# README Butler - Law 12 compliance automation
# Updates domain README changelogs with AI-generated descriptions
readme_butler() {
    if [[ "$SKIP_COMMIT" == true ]]; then
        log_step "📝 Skipping README butler (no commit)"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_step "📝 Would run README butler"
        return 0
    fi

    log_step "📝 README Butler - Updating changelogs..."

    # Source the butler script
    local BUTLER_SCRIPT="${NIXOS_DIR:-/home/eric/.nixos}/domains/ai/tools/parts/readme-butler.sh"

    if [[ ! -f "$BUTLER_SCRIPT" ]]; then
        log_warn "README butler script not found: $BUTLER_SCRIPT"
        return 0
    fi

    # Run butler (it handles its own error checking)
    if "$BUTLER_SCRIPT"; then
        # Re-capture commit hash since butler may have amended
        COMMIT_HASH=$(git rev-parse HEAD)
        SHORT_HASH="${COMMIT_HASH:0:8}"
        log_info "README changelogs updated (commit: $SHORT_HASH)"
    else
        log_warn "README butler encountered issues (non-fatal)"
    fi
}

# Test NixOS configuration
test_configuration() {
    if [[ "$SKIP_TEST" == true ]]; then
        log_step "🧪 Skipping test (--skip-test specified)"
        return 0
    fi

    log_step "🧪 Testing NixOS configuration..."

    if ! execute sudo nixos-rebuild test --flake ".#${FLAKE_TARGET}"; then
        log_error "Configuration test failed"
        return 1
    fi

    log_info "Test successful"
}

# Apply NixOS rebuild
apply_rebuild() {
    log_step "🔄 Applying NixOS rebuild..."

    if ! execute sudo nixos-rebuild switch --flake ".#${FLAKE_TARGET}"; then
        log_error "Rebuild failed"
        return 1
    fi

    log_info "Rebuild successful"
}

# Push to remote
push_to_remote() {
    if [[ "$SKIP_COMMIT" == true ]]; then
        log_step "📤 Skipping push (no commit made)"
        PUSH_STATUS="⚠️ No commit to push"
        readonly PUSH_STATUS
        return 0
    fi

    if [[ "$SKIP_PUSH" == true ]]; then
        log_step "📤 Skipping push (--skip-push specified)"
        PUSH_STATUS="⚠️ Skipped (--skip-push)"
        readonly PUSH_STATUS
        return 0
    fi

    log_step "📤 Pushing to remote repository..."

    # Prompt user unless --yes was specified
    if ! prompt_user "📤 Push changes to remote repository?"; then
        log_info "Skipping push (user declined)"
        PUSH_STATUS="⚠️ Skipped by user"
        readonly PUSH_STATUS
        return 0
    fi

    if execute git push; then
        log_info "Push successful"
        PUSH_STATUS="✅ Pushed to remote"
        readonly PUSH_STATUS
        return 0
    else
        log_warn "Git push failed - changes are local only"
        PUSH_STATUS="⚠️ Push failed - local changes only"
        readonly PUSH_STATUS
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

    # Check if service exists (more reliable check)
    if ! systemctl list-unit-files "${AI_DOCS_SERVICE}.service" &>/dev/null; then
        log_warn "AI docs service not found: $AI_DOCS_SERVICE"
        return 0
    fi

    # Start service asynchronously (--no-block prevents waiting for completion)
    if sudo systemctl start --no-block "${AI_DOCS_SERVICE}.service" 2>/dev/null; then
        log_info "AI documentation processing started (running in background)"
    else
        log_warn "Failed to start AI docs service (non-fatal)"
    fi
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

    # Run README butler after commit, before rebuild (Law 12 compliance)
    readme_butler  # Non-fatal, continues on failure

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

    # Show summary
    show_summary

    exit 0
}

# Execute main function
main "$@"
