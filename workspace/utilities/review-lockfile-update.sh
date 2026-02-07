#!/usr/bin/env bash
# Lockfile Review and Incremental Update Tool
# CHARTER v9.0 - Safe, incremental flake input updates
#
# Usage: ./workspace/utilities/review-lockfile-update.sh [input-name]
#
# Without arguments: Shows what would change with full update
# With input: Updates only that input (e.g., nixpkgs-stable)

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

INPUT_NAME="${1:-}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Flake Lockfile Review Tool${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if git repo is clean
if [[ -n $(git status --porcelain flake.lock) ]]; then
    echo -e "${YELLOW}[WARN]${NC} flake.lock has uncommitted changes"
    echo "      Commit or stash changes before updating"
    echo ""
fi

if [[ -z "$INPUT_NAME" ]]; then
    #=======================================================================
    # PREVIEW MODE: Show what would change
    #=======================================================================
    echo -e "${CYAN}[PREVIEW]${NC} Showing what would change with full update..."
    echo ""

    # Save current lockfile
    cp flake.lock flake.lock.backup

    # Update lockfile
    nix flake update --commit-lock-file 2>&1 | grep -E "(Updated|warning)" || true

    # Show diff
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Lockfile Changes${NC}"
    echo -e "${BLUE}========================================${NC}"

    if git diff --no-index --color=always flake.lock.backup flake.lock 2>/dev/null; then
        echo -e "${GREEN}No changes${NC}"
    fi

    # Restore original lockfile
    mv flake.lock.backup flake.lock

    echo ""
    echo -e "${YELLOW}This was a preview only. No changes were made.${NC}"
    echo ""
    echo "To update a specific input:"
    echo "  ./workspace/utilities/review-lockfile-update.sh nixpkgs-stable"
    echo "  ./workspace/utilities/review-lockfile-update.sh home-manager"
    echo ""
    echo "Available inputs:"
    nix flake metadata --json | jq -r '.locks.nodes.root.inputs | keys[]' | sed 's/^/  - /'
    echo ""

else
    #=======================================================================
    # UPDATE MODE: Update specific input
    #=======================================================================
    echo -e "${CYAN}[UPDATE]${NC} Updating input: $INPUT_NAME"
    echo ""

    # Verify input exists
    if ! nix flake metadata --json | jq -e ".locks.nodes.root.inputs.\"$INPUT_NAME\"" > /dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} Input '$INPUT_NAME' not found in flake.nix"
        echo ""
        echo "Available inputs:"
        nix flake metadata --json | jq -r '.locks.nodes.root.inputs | keys[]' | sed 's/^/  - /'
        exit 1
    fi

    # Get current revision
    CURRENT_REV=$(nix flake metadata --json | jq -r ".locks.nodes.\"$INPUT_NAME\".locked.rev // .locks.nodes.\"$INPUT_NAME\".locked.narHash" 2>/dev/null || echo "unknown")

    # Save current lockfile
    cp flake.lock flake.lock.before

    # Update the input
    echo "Updating $INPUT_NAME..."
    nix flake lock --update-input "$INPUT_NAME"

    # Get new revision
    NEW_REV=$(nix flake metadata --json | jq -r ".locks.nodes.\"$INPUT_NAME\".locked.rev // .locks.nodes.\"$INPUT_NAME\".locked.narHash" 2>/dev/null || echo "unknown")

    # Show diff
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Changes to $INPUT_NAME${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "Before: ${CYAN}${CURRENT_REV:0:12}${NC}"
    echo -e "After:  ${CYAN}${NEW_REV:0:12}${NC}"
    echo ""

    git diff --no-index --color=always flake.lock.before flake.lock 2>/dev/null | tail -n +5 || true

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Next Steps${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "1. Review the changes above"
    echo "2. Test the build:"
    echo "     nixos-rebuild build --flake .#hwc-server"
    echo ""
    echo "3. If build succeeds, commit the lockfile update:"
    echo "     git add flake.lock"
    echo "     git commit -m \"chore(flake): update $INPUT_NAME to ${NEW_REV:0:12}\""
    echo ""
    echo "4. Test without activating:"
    echo "     nixos-rebuild test --flake .#hwc-server"
    echo ""
    echo "5. If tests pass, apply:"
    echo "     nixos-rebuild switch --flake .#hwc-server"
    echo ""
    echo "To revert this update:"
    echo "  mv flake.lock.before flake.lock"
    echo ""
fi
