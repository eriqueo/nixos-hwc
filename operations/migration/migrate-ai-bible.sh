#!/usr/bin/env bash
set -euo pipefail

echo "=== Migrating AI Bible System ==="

OLD_BASE="/etc/nixos"
NEW_BASE="/etc/nixos-next"

# Copy Python scripts
echo "Copying Python scripts..."
mkdir -p "$NEW_BASE/modules/ai-bible/scripts"
cp "$OLD_BASE/scripts/bible_"*.py "$NEW_BASE/modules/ai-bible/scripts/"

# Copy prompts
echo "Copying prompts..."
mkdir -p "$NEW_BASE/modules/ai-bible/prompts"
cp -r "$OLD_BASE/prompts/bible_prompts/" "$NEW_BASE/modules/ai-bible/prompts/"

# Copy config files
echo "Copying configuration..."
cp "$OLD_BASE/config/bible_"*.yaml "$NEW_BASE/modules/ai-bible/data/"

echo "✅ AI Bible system files migrated"
echo "📝 Remember to update paths in the Python scripts"
