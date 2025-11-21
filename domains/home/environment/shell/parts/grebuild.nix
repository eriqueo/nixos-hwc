# HWC Charter Module/domains/home/environment/shell/parts/grebuild.nix
#
# GREBUILD PART - Git rebuild function as proper derivation
# Pure function returning writeShellApplication for grebuild command
#
# DEPENDENCIES: None (pure function)
# USED BY: domains/home/environment/shell/index.nix
#
# PURPOSE: Returns grebuild script derivation for Nix store management

{ pkgs }:

pkgs.writeShellApplication {
  name = "grebuild";

  runtimeInputs = with pkgs; [
    git
    nixos-rebuild
    sudo
    coreutils
    hostname
  ];

  text = ''
    set -euo pipefail

    #==========================================================================
    # CONFIGURATION
    #==========================================================================

    readonly SCRIPT_NAME="grebuild"
    readonly NIXOS_DIR="''${HWC_NIXOS_DIR:-/home/eric/.nixos}"
    readonly STASH_PREFIX="grebuild-temp"

    # Colors for output
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m'

    #==========================================================================
    # LOGGING FUNCTIONS
    #==========================================================================

    log_info() {
      echo "''${BLUE}[INFO]''${NC} $*"
    }

    log_success() {
      echo "''${GREEN}[OK]''${NC} $*"
    }

    log_warn() {
      echo "''${YELLOW}[WARN]''${NC} $*"
    }

    log_error() {
      echo "''${RED}[ERROR]''${NC} $*" >&2
    }

    error_exit() {
      log_error "$1"
      cd "$original_dir" 2>/dev/null || true
      exit "''${2:-1}"
    }

    #==========================================================================
    # GIT OPERATION HELPERS
    #==========================================================================

    # Execute git command, handling permission issues gracefully
    git_exec() {
      # Try as current user first
      if git "$@" 2>/dev/null; then
        return 0
      fi

      # If that fails due to permissions, try with sudo
      # This preserves environment and Git credentials
      if sudo -E git "$@"; then
        return 0
      else
        return 1
      fi
    }

    # Check if working tree is clean
    is_working_tree_clean() {
      git_exec diff-index --quiet HEAD -- 2>/dev/null
    }

    # Stash local changes with a timestamped message
    stash_changes() {
      local stash_msg
      stash_msg="''${STASH_PREFIX}-$(date +%s)"
      git_exec stash push -m "$stash_msg"
    }

    # Pop most recent stash
    pop_stash() {
      git_exec stash pop
    }

    #==========================================================================
    # VALIDATION FUNCTIONS
    #==========================================================================

    validate_nixos_dir() {
      if [[ ! -d "$NIXOS_DIR" ]]; then
        error_exit "Could not find NixOS configuration directory at: $NIXOS_DIR" 1
      fi

      if ! cd "$NIXOS_DIR" 2>/dev/null; then
        error_exit "Could not access $NIXOS_DIR directory" 1
      fi
    }

    validate_git_repo() {
      if ! git_exec rev-parse --git-dir >/dev/null 2>&1; then
        error_exit "$NIXOS_DIR is not a git repository" 1
      fi
    }

    check_network_connectivity() {
      local remote_url
      remote_url=$(git_exec config --get remote.origin.url 2>/dev/null || echo "")

      if [[ -z "$remote_url" ]]; then
        return 1
      fi

      if ! git_exec ls-remote --exit-code origin HEAD >/dev/null 2>&1; then
        log_warn "Cannot reach remote repository"
        return 1
      fi

      return 0
    }

    #==========================================================================
    # SYNC FUNCTIONS
    #==========================================================================

    sync_with_remote() {
      local stash_created=false
      local has_changes=false

      # Check if tree is dirty
      if ! is_working_tree_clean; then
        log_info "Detected local changes"
        has_changes=true
      else
        log_success "Working tree is clean"
      fi

      log_info "Syncing with remote..."

      # Stash local changes if any exist
      if [[ "$has_changes" == true ]]; then
        log_info "Stashing local changes..."
        if stash_changes; then
          stash_created=true
          log_success "Local changes stashed"
        else
          error_exit "Failed to stash local changes" 1
        fi
      fi

      # Fetch latest changes
      log_info "Fetching from remote..."
      if ! git_exec fetch origin; then
        log_error "Git fetch failed"
        if [[ "$stash_created" == true ]]; then
          log_info "Restoring stashed changes..."
          pop_stash || log_warn "Could not restore stash automatically"
        fi
        error_exit "Remote sync failed" 1
      fi

      # Check if we're behind remote
      local local_rev remote_rev
      local_rev=$(git_exec rev-parse HEAD)
      remote_rev=$(git_exec rev-parse origin/main 2>/dev/null || git_exec rev-parse origin/master 2>/dev/null || echo "$local_rev")

      if [[ "$local_rev" == "$remote_rev" ]]; then
        log_success "Already up to date with remote"
      else
        log_info "Pulling changes from remote..."
        if ! git_exec pull origin main 2>/dev/null && ! git_exec pull origin master 2>/dev/null; then
          log_error "Git pull failed - resolve conflicts manually"
          if [[ "$stash_created" == true ]]; then
            log_info "Restoring stashed changes..."
            pop_stash || log_warn "Could not restore stash automatically"
          fi
          error_exit "Remote sync failed" 1
        fi
        log_success "Pulled latest changes"
      fi

      # Restore local changes on top of pulled changes
      if [[ "$stash_created" == true ]]; then
        log_info "Applying local changes on top of remote changes..."
        if ! pop_stash; then
          error_exit "Merge conflict! Resolve manually and run 'git stash drop'" 1
        fi
        log_success "Local changes applied successfully"
      fi

      return 0
    }

    #==========================================================================
    # BUILD FUNCTIONS
    #==========================================================================

    test_nixos_config() {
      local hostname_val
      hostname_val=$(hostname)

      log_info "Testing configuration on host: $hostname_val"

      if [[ -f flake.nix ]]; then
        if ! sudo nixos-rebuild test --flake ".#$hostname_val" --show-trace; then
          return 1
        fi
      else
        if ! sudo nixos-rebuild test --show-trace; then
          return 1
        fi
      fi

      return 0
    }

    switch_nixos_config() {
      local hostname_val
      hostname_val=$(hostname)

      log_info "Switching to new configuration..."

      if [[ -f flake.nix ]]; then
        if ! sudo nixos-rebuild switch --flake ".#$hostname_val"; then
          return 1
        fi
      else
        if ! sudo nixos-rebuild switch; then
          return 1
        fi
      fi

      return 0
    }

    #==========================================================================
    # MAIN WORKFLOW
    #==========================================================================

    show_usage() {
      cat << EOF
Usage: $SCRIPT_NAME <commit message>
       $SCRIPT_NAME --test <commit message>  (test only, no switch)
       $SCRIPT_NAME --sync                   (sync only, no rebuild)

Description:
  Safe git + NixOS rebuild workflow with multi-host sync protection.

  Default: sync, test, commit, push, switch
  --test:  sync, test (no commit/push/switch)
  --sync:  sync only (no test/commit/push/switch)

Examples:
  $SCRIPT_NAME 'feat(waybar): add GPU status module'
  $SCRIPT_NAME --test 'fix(hyprland): update keybinds'
  $SCRIPT_NAME --sync

Environment:
  HWC_NIXOS_DIR  NixOS config directory (default: /home/eric/.nixos)
EOF
    }

    main() {
      # Save current directory
      readonly original_dir="$PWD"

      # Check arguments
      if [[ $# -eq 0 ]]; then
        show_usage
        exit 2
      fi

      # Parse mode flags
      local test_mode=false
      local sync_only=false

      if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        show_usage
        exit 0
      fi

      if [[ "$1" == "--test" ]]; then
        test_mode=true
        shift
        if [[ $# -eq 0 ]]; then
          error_exit "Commit message required even in test mode" 2
        fi
      fi

      if [[ "$1" == "--sync" ]]; then
        sync_only=true
        shift
      fi

      # Validate environment
      log_info "Working in: $NIXOS_DIR"
      validate_nixos_dir
      validate_git_repo

      # Handle sync-only mode
      if [[ "$sync_only" == true ]]; then
        if ! check_network_connectivity; then
          error_exit "Cannot sync: no network connectivity" 1
        fi
        sync_with_remote
        log_success "Git sync complete"
        cd "$original_dir"
        exit 0
      fi

      # Sync with remote (with network check)
      if check_network_connectivity; then
        sync_with_remote
      else
        log_warn "Skipping remote sync (no network connectivity)"
      fi

      # Add all changes
      log_info "Staging all changes..."
      if ! git_exec add .; then
        error_exit "Git add failed" 1
      fi

      # Check if there are staged changes
      if is_working_tree_clean; then
        log_info "No changes to commit"
        cd "$original_dir"
        exit 0
      fi

      # Test configuration BEFORE committing
      log_info "Testing configuration before committing..."
      if ! test_nixos_config; then
        error_exit "NixOS test failed! No changes committed" 1
      fi

      log_success "Test passed! Configuration is valid"

      # Exit if test-only mode
      if [[ "$test_mode" == true ]]; then
        log_success "Test mode complete - configuration valid but not committed"
        cd "$original_dir"
        exit 0
      fi

      # Commit tested changes
      local commit_msg="$*"
      log_info "Committing tested changes: $commit_msg"
      if ! git_exec commit -m "$commit_msg"; then
        error_exit "Git commit failed" 1
      fi

      # Push to remote (with network check)
      if check_network_connectivity; then
        log_info "Pushing to remote..."
        if ! git_exec push; then
          error_exit "Git push failed. Changes committed locally but not pushed" 1
        fi
        log_success "Pushed to remote"
      else
        log_warn "Skipping push (no network). Changes committed locally only"
      fi

      # Switch to new configuration (already tested)
      if ! switch_nixos_config; then
        error_exit "NixOS switch failed (but changes are committed)" 1
      fi

      log_success "Complete! System rebuilt and switched with: $commit_msg"
      cd "$original_dir"
    }

    # Execute main function
    main "$@"
  '';
}
