# nixos-h../domains/home/environment/shell/parts/grebuild.nix
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
    if [[ -z "$1" ]]; then
      echo "Usage: grebuild <commit message>"
      echo "       grebuild --test <commit message>  (test only, no switch)"
      echo "       grebuild --sync  (sync only, no rebuild)"
      echo "Example: grebuild 'added waybar autostart'"
      exit 1
    fi

    # Save current directory
    original_dir="$PWD"

    # Use dynamic NixOS config directory
    nixdir="''${HWC_NIXOS_DIR:-/home/eric/.nixos}"

    if [[ -z "$nixdir" || ! -d "$nixdir" ]]; then
      echo "❌ Could not find NixOS configuration directory at: $nixdir"
      echo "💡 HWC_NIXOS_DIR environment variable may not be set correctly"
      exit 1
    fi

    # Change to NixOS config directory
    cd "$nixdir" || {
      echo "❌ Could not access $nixdir directory"
      exit 1
    }

    echo "📁 Working in: $nixdir"

    # Check for test mode
    test_mode=false
    if [[ "$1" == "--test" ]]; then
      test_mode=true
      shift
      if [[ -z "$1" ]]; then
        echo "❌ Commit message required even in test mode"
        cd "$original_dir"
        exit 1
      fi
    fi

    # Handle sync-only mode
    if [[ "$1" == "--sync" ]]; then
      echo "🔄 Syncing with remote..."
      if ! sudo -E git fetch origin; then
        echo "❌ Git fetch failed"
        cd "$original_dir"
        exit 1
      fi
      if ! sudo -E git pull origin main; then
        echo "❌ Git pull failed - resolve conflicts manually"
        cd "$original_dir"
        exit 1
      fi
      echo "✅ Git sync complete!"
      cd "$original_dir"
      exit 0
    fi

    # Check if tree is dirty
    if ! sudo git diff-index --quiet HEAD 2>/dev/null; then
      echo "📋 Detected local changes to commit"
      has_changes=true
    else
      echo "✅ Working tree is clean"
      has_changes=false
    fi

    # ENHANCED SYNC - Handle multi-host scenarios safely
    echo "🔄 Syncing with remote (safe multi-host sync)..."

    # Stash local changes if any exist
    stash_created=false
    if [[ "$has_changes" == true ]]; then
      echo "💾 Stashing local changes for safe sync..."
      if sudo git stash push -m "grebuild-temp-$(date +%s)"; then
        stash_created=true
        echo "✅ Local changes stashed"
      else
        echo "❌ Failed to stash local changes"
        cd "$original_dir"
        exit 1
      fi
    fi

    # Fetch and pull latest changes
    if ! sudo -E git fetch origin; then
      echo "❌ Git fetch failed"
      if [[ "$stash_created" == true ]]; then
        echo "🔄 Restoring stashed changes..."
        sudo git stash pop
      fi
      cd "$original_dir"
      exit 1
    fi

    if ! sudo -E git pull origin main; then
      echo "❌ Git pull failed - resolve conflicts manually"
      if [[ "$stash_created" == true ]]; then
        echo "🔄 Restoring stashed changes..."
        sudo git stash pop
      fi
      cd "$original_dir"
      exit 1
    fi

    # Restore local changes on top of pulled changes
    if [[ "$stash_created" == true ]]; then
      echo "🔄 Applying local changes on top of remote changes..."
      if ! sudo git stash pop; then
        echo "❌ Merge conflict applying local changes!"
        echo "💡 Resolve conflicts manually and run 'git stash drop' when done"
        cd "$original_dir"
        exit 1
      fi
      echo "✅ Local changes applied successfully"
    fi

    # Add all changes (including any merged ones)
    echo "📝 Adding all changes..."
    if ! sudo git add .; then
      echo "❌ Git add failed"
      cd "$original_dir"
      exit 1
    fi

    # IMPROVED FLOW: Test BEFORE committing
    echo "🧪 Testing configuration before committing..."
    hostname_val=$(hostname)
    test_success=false

    if [[ -f flake.nix ]]; then
      if sudo nixos-rebuild test --flake ".#$hostname_val"; then
        test_success=true
      fi
    else
      if sudo nixos-rebuild test; then
        test_success=true
      fi
    fi

    if [[ "$test_success" != true ]]; then
      echo "❌ NixOS test failed! No changes committed."
      echo "💡 Fix configuration issues and try again"
      cd "$original_dir"
      exit 1
    fi

    echo "✅ Test passed! Configuration is valid."

    if [[ "$test_mode" == true ]]; then
      echo "✅ Test mode complete! Configuration is valid but not committed."
      cd "$original_dir"
      exit 0
    fi

    # Only commit if test passed
    echo "💾 Committing tested changes: $*"
    if ! sudo git commit -m "$*"; then
      echo "❌ Git commit failed"
      cd "$original_dir"
      exit 1
    fi

    echo "☁️  Pushing to remote..."
    if ! sudo -E git push; then
      echo "❌ Git push failed"
      cd "$original_dir"
      exit 1
    fi

    # Switch to new configuration (already tested)
    echo "🔄 Switching to new configuration..."
    if [[ -f flake.nix ]]; then
      if ! sudo nixos-rebuild switch --flake ".#$hostname_val"; then
        echo "❌ NixOS switch failed (but changes are committed)"
        cd "$original_dir"
        exit 1
      fi
    else
      if ! sudo nixos-rebuild switch; then
        echo "❌ NixOS switch failed (but changes are committed)"
        cd "$original_dir"
        exit 1
      fi
    fi

    echo "✅ Complete! System rebuilt and switched with: $*"
    cd "$original_dir"
  '';
}