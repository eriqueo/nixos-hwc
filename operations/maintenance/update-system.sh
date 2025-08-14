#!/usr/bin/env bash
set -euo pipefail

echo "=== NixOS System Update ==="

# Update flake inputs
echo "Updating flake inputs..."
nix flake update

# Build new configuration
echo "Building configuration..."
sudo nixos-rebuild build --flake .#$(hostname)

# Show changes
echo "Changes in this update:"
nvd diff /run/current-system result

# Ask for confirmation
read -p "Apply update? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo nixos-rebuild switch --flake .#$(hostname)
    echo "✅ Update complete"
else
    echo "❌ Update cancelled"
fi
