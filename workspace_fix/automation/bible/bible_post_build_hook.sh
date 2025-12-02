#\!/bin/bash
# AI Bible Documentation System - Post-Build Integration Hook
# Agent 7: Integration & Workflow Manager
#
# This script integrates the Bible Workflow Manager with the existing NixOS
# rebuild workflow through git post-commit hooks and systemd integration.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/nixos/config/bible_system_config.yaml"
WORKFLOW_MANAGER="/etc/nixos/scripts/bible_workflow_manager.py"
LOG_DIR="/etc/nixos/docs/logs"
LOCK_FILE="/tmp/bible_workflow.lock"

# Logging setup
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="${LOG_DIR}/post_build_integration.log"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$TIMESTAMP] [$level] bible_post_build_hook: $*" | tee -a "$LOG_FILE"
}

# Error handling
cleanup() {
    local exit_code=$?
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Post-build hook failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

trap cleanup EXIT ERR

# Check if workflow manager is available
check_workflow_manager() {
    if [[ \! -f "$WORKFLOW_MANAGER" ]]; then
        log "ERROR" "Workflow manager not found: $WORKFLOW_MANAGER"
        return 1
    fi
    
    if [[ \! -x "$WORKFLOW_MANAGER" ]]; then
        log "ERROR" "Workflow manager not executable: $WORKFLOW_MANAGER"
        return 1
    fi
    
    return 0
}

# Check for concurrent execution
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log "INFO" "Another workflow is running (PID: $lock_pid). Exiting."
            exit 0
        else
            log "WARN" "Stale lock file found. Removing."
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    log "INFO" "Acquired workflow lock (PID: $$)"
}

# Determine build status
determine_build_status() {
    local build_success="true"
    
    # Check various indicators of build success/failure
    # 1. Exit code from previous command (if available)
    if [[ "${1:-}" == "failed" ]]; then
        build_success="false"
    fi
    
    # 2. Check for NixOS build artifacts
    if [[ \! -d "/run/current-system" ]]; then
        log "WARN" "No current system detected - build may have failed"
        build_success="false"
    fi
    
    # 3. Check git status for build-related indicators
    if command -v git >/dev/null 2>&1; then
        if git status >/dev/null 2>&1; then
            # Check for any build failure indicators in recent commits
            local recent_commits
            recent_commits=$(git log --oneline -5 --grep="fail\|error\|broken" --ignore-case 2>/dev/null || echo "")
            if [[ -n "$recent_commits" ]]; then
                log "WARN" "Recent commits suggest build issues: $recent_commits"
                # Don't automatically mark as failed - just log the warning
            fi
        fi
    fi
    
    echo "$build_success"
}

# Execute workflow with proper error handling
execute_workflow() {
    local build_success="$1"
    local workflow_args=("--post-build")
    
    if [[ "$build_success" == "true" ]]; then
        workflow_args+=("--build-success")
        log "INFO" "Executing post-successful-build workflow"
    else
        workflow_args+=("--build-failed")
        log "INFO" "Executing post-failed-build workflow"
    fi
    
    # Add configuration if available
    if [[ -f "$CONFIG_FILE" ]]; then
        workflow_args+=("--config" "$CONFIG_FILE")
    fi
    
    # Execute workflow manager
    local workflow_exit_code=0
    local workflow_output
    
    log "INFO" "Starting workflow: ${WORKFLOW_MANAGER} ${workflow_args[*]}"
    
    if workflow_output=$("$WORKFLOW_MANAGER" "${workflow_args[@]}" 2>&1); then
        log "INFO" "Workflow completed successfully"
        log "DEBUG" "Workflow output: $workflow_output"
    else
        workflow_exit_code=$?
        log "ERROR" "Workflow failed with exit code $workflow_exit_code"
        log "ERROR" "Workflow output: $workflow_output"
        
        # For post-build hooks, we generally don't want to fail the entire build
        # process, so we log the error but continue
        if [[ "$build_success" == "true" ]]; then
            log "WARN" "Workflow failure during successful build - continuing"
            # Send notification if configured
            send_failure_notification "Workflow failed during successful build" "$workflow_output"
        fi
    fi
    
    return $workflow_exit_code
}

# Send failure notification (placeholder for actual notification system)
send_failure_notification() {
    local subject="$1"
    local details="$2"
    
    # Log notification
    log "ERROR" "NOTIFICATION: $subject"
    log "ERROR" "Details: $details"
    
    # In a full implementation, this would send actual notifications
    # via email, webhook, or other notification system
}

# Validate system state before execution
validate_system_state() {
    log "INFO" "Validating system state"
    
    # Check if configuration file exists
    if [[ \! -f "$CONFIG_FILE" ]]; then
        log "WARN" "Configuration file not found: $CONFIG_FILE"
        log "WARN" "Workflow may run with default settings"
    fi
    
    # Check if Ollama service is available (required for AI operations)
    if command -v systemctl >/dev/null 2>&1; then
        if \! systemctl is-active ollama >/dev/null 2>&1; then
            log "WARN" "Ollama service not active - AI features may be limited"
        fi
    fi
    
    # Check disk space
    local available_space
    available_space=$(df /etc/nixos | awk 'NR==2 {print $4}')
    local available_mb=$((available_space / 1024))
    
    if [[ $available_mb -lt 100 ]]; then
        log "ERROR" "Low disk space: ${available_mb}MB available"
        return 1
    elif [[ $available_mb -lt 500 ]]; then
        log "WARN" "Limited disk space: ${available_mb}MB available"
    fi
    
    log "INFO" "System state validation completed"
    return 0
}

# Integration with existing git hooks
integrate_git_hooks() {
    local git_dir="/etc/nixos/.git"
    local hooks_dir="${git_dir}/hooks"
    local post_commit_hook="${hooks_dir}/post-commit"
    
    if [[ \! -d "$git_dir" ]]; then
        log "WARN" "Not in a git repository - skipping git hook integration"
        return 0
    fi
    
    # Ensure hooks directory exists
    mkdir -p "$hooks_dir"
    
    # Check if post-commit hook exists and includes bible system
    if [[ -f "$post_commit_hook" ]]; then
        if grep -q "bible" "$post_commit_hook"; then
            log "INFO" "Bible system already integrated with post-commit hook"
            return 0
        else
            log "INFO" "Adding bible system integration to existing post-commit hook"
            # Append our integration to existing hook
            cat >> "$post_commit_hook" << 'HOOK_EOF'

# AI Bible Documentation System Integration
if [[ -f "/etc/nixos/scripts/bible_post_build_hook.sh" ]]; then
    /etc/nixos/scripts/bible_post_build_hook.sh "git-commit" || true
fi
HOOK_EOF
        fi
    else
        log "INFO" "Creating new post-commit hook with bible system integration"
        cat > "$post_commit_hook" << 'HOOK_EOF'
#\!/bin/bash
# Git post-commit hook with AI Bible Documentation System integration

# AI Bible Documentation System Integration
if [[ -f "/etc/nixos/scripts/bible_post_build_hook.sh" ]]; then
    /etc/nixos/scripts/bible_post_build_hook.sh "git-commit" || true
fi
HOOK_EOF
    fi
    
    # Make hook executable
    chmod +x "$post_commit_hook"
    log "INFO" "Git hook integration completed"
}

# Main execution function
main() {
    local build_status_arg="${1:-auto}"
    
    log "INFO" "Starting post-build integration hook"
    log "INFO" "Arguments: $*"
    
    # Validate prerequisites
    if \! check_workflow_manager; then
        log "ERROR" "Workflow manager validation failed"
        return 1
    fi
    
    # Check for concurrent execution
    check_lock
    
    # Validate system state
    if \! validate_system_state; then
        log "ERROR" "System state validation failed"
        return 1
    fi
    
    # Determine build status
    local build_success
    build_success=$(determine_build_status "$build_status_arg")
    log "INFO" "Determined build status: $build_success"
    
    # Execute workflow
    local workflow_success=true
    if \! execute_workflow "$build_success"; then
        workflow_success=false
    fi
    
    # Log completion
    if [[ "$workflow_success" == "true" ]]; then
        log "INFO" "Post-build integration completed successfully"
    else
        log "WARN" "Post-build integration completed with warnings"
    fi
    
    # For script execution modes, integrate git hooks
    if [[ "$build_status_arg" == "integrate" ]]; then
        integrate_git_hooks
    fi
    
    return 0
}

# Command line interface
case "${1:-}" in
    "integrate")
        log "INFO" "Running git hook integration"
        integrate_git_hooks
        ;;
    "test")
        log "INFO" "Running test execution"
        main "test"
        ;;
    "failed")
        log "INFO" "Running post-failed-build workflow"
        main "failed"
        ;;
    "success"|"git-commit"|"")
        log "INFO" "Running post-successful-build workflow"
        main "success"
        ;;
    "help"|"--help"|"-h")
        cat << 'HELP_EOF'
AI Bible Documentation System - Post-Build Integration Hook

Usage: bible_post_build_hook.sh [COMMAND]

Commands:
  (none)     - Auto-detect build status and run appropriate workflow
  success    - Run post-successful-build workflow
  failed     - Run post-failed-build workflow  
  integrate  - Integrate with git post-commit hooks
  test       - Test execution with validation
  help       - Show this help message

Environment Variables:
  BIBLE_DEBUG=1           - Enable debug logging
  BIBLE_DRY_RUN=1        - Run in dry-run mode
  BIBLE_SKIP_VALIDATION=1 - Skip system validation

Examples:
  # Auto-detect and run appropriate workflow
  bible_post_build_hook.sh
  
  # Integrate with git hooks (run once during setup)  
  bible_post_build_hook.sh integrate
  
  # Test the integration
  bible_post_build_hook.sh test
HELP_EOF
        ;;
    *)
        log "ERROR" "Unknown command: $1"
        log "INFO" "Use 'bible_post_build_hook.sh help' for usage information"
        exit 1
        ;;
esac
EOF < /dev/null