#!/usr/bin/env bash
# Promotes a workspace script to a domain-level Nix derivation
#
# Usage: promote-to-domain.sh <workspace-script-path> <command-name>
#
# Example:
#   promote-to-domain.sh workspace/scripts/development/my-tool.sh my-tool
#
# This creates:
#   - domains/home/environment/shell/parts/<command-name>.nix (Nix derivation)
#
# You must then manually:
#   1. Add import in domains/home/environment/shell/index.nix (in let block)
#   2. Add to home.packages list in index.nix
#   3. Test with: nix flake check
#   4. Rebuild: sudo nixos-rebuild test --flake .#hwc-laptop

set -euo pipefail

SCRIPT_PATH="${1:?Usage: $0 <workspace-script-path> <command-name>}"
COMMAND_NAME="${2:?}"

# Validate first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/validate-workspace-script.sh" "$SCRIPT_PATH"
VALIDATION_EXIT=$?

if [[ $VALIDATION_EXIT -eq 1 ]]; then
  echo ""
  echo "❌ Cannot promote: Script failed validation"
  exit 1
elif [[ $VALIDATION_EXIT -eq 2 ]]; then
  echo ""
  echo "⚠️  Script has warnings but will proceed with promotion"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Promoting script to domain command"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Derive paths
SCRIPT_REL_PATH="${SCRIPT_PATH#workspace/scripts/}"
PARTS_FILE="domains/home/environment/shell/parts/${COMMAND_NAME}.nix"

# Check if derivation already exists
if [[ -f "$PARTS_FILE" ]]; then
  echo "⚠️  WARNING: $PARTS_FILE already exists"
  read -p "Overwrite? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Promotion cancelled"
    exit 0
  fi
fi

echo ""
echo "Creating Nix derivation: $PARTS_FILE"
echo "Script path: $SCRIPT_REL_PATH"
echo "Command name: $COMMAND_NAME"
echo ""

# Create the Nix derivation
cat > "$PARTS_FILE" <<EOF
{ pkgs, config, ... }:

let
  workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
  workspaceScripts = workspaceRoot + "/scripts";
in
pkgs.writeShellApplication {
  name = "${COMMAND_NAME}";
  runtimeInputs = with pkgs; [
    # TODO: Add required runtime dependencies
    # Common: bash, coreutils, findutils, gnugrep, gnused, gawk
    # System tools: git, curl, jq
    # NixOS tools: (sudo, systemctl, journalctl are in system PATH)
    bash
  ];
  text = ''
    exec bash "\${workspaceScripts}/${SCRIPT_REL_PATH}" "\$@"
  '';
}
EOF

echo "✓ Created $PARTS_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next steps (MANUAL):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Add import in domains/home/environment/shell/index.nix:"
echo ""
echo "   let"
echo "     cfg = config.hwc.home.shell;"
echo "     ..."
echo "     ${COMMAND_NAME} = import ./parts/${COMMAND_NAME}.nix { inherit pkgs config; };"
echo "   in"
echo ""
echo "2. Add to home.packages in index.nix:"
echo ""
echo "   home.packages = cfg.packages"
echo "     ++ [ ... ]"
echo "     ++ ["
echo "       ..."
echo "       ${COMMAND_NAME}"
echo "     ];"
echo ""
echo "3. Review and add runtime dependencies in $PARTS_FILE"
echo "   (Check the script for commands it uses)"
echo ""
echo "4. Test build:"
echo "   nix flake check"
echo ""
echo "5. Test without activation:"
echo "   sudo nixos-rebuild test --flake .#hwc-laptop"
echo ""
echo "6. Verify command in PATH:"
echo "   which ${COMMAND_NAME}"
echo ""
echo "7. If tests pass, activate:"
echo "   sudo nixos-rebuild switch --flake .#hwc-laptop"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
