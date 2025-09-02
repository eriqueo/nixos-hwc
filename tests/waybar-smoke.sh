#!/usr/bin/env bash
# Waybar Smoke Test - Validates waybar infrastructure tools and configuration
# Usage: ./tests/waybar-smoke.sh

set -euo pipefail

echo "=== Waybar Smoke Test ==="

# Required canonical waybar tools (all 13)
readonly req=(
    waybar-gpu-status waybar-gpu-toggle waybar-gpu-menu waybar-gpu-launch
    waybar-network-status waybar-network-settings  
    waybar-battery-health waybar-power-settings
    waybar-disk-usage-gui waybar-system-monitor
    waybar-resource-monitor waybar-sensor-viewer
    waybar-workspace-switcher
)

# Test 1: Verify all canonical tools are available
echo "Checking canonical waybar tools..."
missing=0
for tool in "${req[@]}"; do 
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ MISSING: $tool"
        missing=$((missing + 1))
    else
        echo "✅ FOUND: $tool"
    fi
done

if [[ $missing -gt 0 ]]; then
    echo "❌ FAIL: $missing canonical tools missing"
    exit 1
fi

# Test 2: Verify no unprefixed wrappers remain (should all be gone after cleanup)
echo "Checking for unwanted wrapper binaries..."
unwanted=(gpu-status gpu-toggle network-status battery-health system-monitor disk-usage-gui power-settings sensor-viewer workspace-switcher resource-monitor)
wrapper_found=0
for wrapper in "${unwanted[@]}"; do
    if command -v "$wrapper" >/dev/null 2>&1; then
        echo "⚠️  WRAPPER STILL EXISTS: $wrapper (will be removed on next system rebuild)"
        wrapper_found=$((wrapper_found + 1))
    fi
done
if [[ $wrapper_found -eq 0 ]]; then
    echo "✅ No unwanted wrappers found"
else
    echo "ℹ️  Found $wrapper_found wrappers (cleanup requires system rebuild)"
fi

# Test 3: Test key tool functionality
echo "Testing tool functionality..."

# GPU status should return JSON
if ! waybar-gpu-status | jq -e '.text' >/dev/null 2>&1; then
    echo "❌ waybar-gpu-status does not return valid JSON"
    exit 1
fi
echo "✅ waybar-gpu-status returns valid JSON"

# Network status should return JSON  
if ! waybar-network-status | jq -e '.text' >/dev/null 2>&1; then
    echo "❌ waybar-network-status does not return valid JSON"
    exit 1
fi
echo "✅ waybar-network-status returns valid JSON"

# Battery health should return JSON
if ! waybar-battery-health | jq -e '.text' >/dev/null 2>&1; then
    echo "❌ waybar-battery-health does not return valid JSON"
    exit 1
fi
echo "✅ waybar-battery-health returns valid JSON"

# Test 4: Verify waybar config builds (Home-Manager)
echo "Testing Home-Manager waybar config build..."
if ! nix build --no-link --show-trace \
    '.#homeConfigurations."eric".config.programs.waybar.settings' 2>/dev/null; then
    echo "❌ Waybar Home-Manager config failed to build"
    exit 1
fi
echo "✅ Waybar Home-Manager config builds successfully"

echo ""
echo "🎉 ALL TESTS PASSED"
echo "Waybar infrastructure and configuration validated successfully"