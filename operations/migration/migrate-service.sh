#!/usr/bin/env bash
set -euo pipefail

SERVICE=$1
OLD_PATH="/etc/nixos/hosts/server/modules/$SERVICE.nix"
NEW_PATH="/etc/nixos-next/modules/services/$SERVICE.nix"

echo "=== Migrating $SERVICE ==="

# Check if old service exists
if [ ! -f "$OLD_PATH" ]; then
    echo "⚠️  No old config found at $OLD_PATH"
    echo "Searching for service..."
    find /etc/nixos -name "*$SERVICE*" -type f
    exit 1
fi

# Create new module from template
cp operations/migration/SERVICE_TEMPLATE.nix "$NEW_PATH"

echo "✅ Created $NEW_PATH"
echo "📝 Now manually port the configuration"

echo "Old config:"
head -20 "$OLD_PATH"
