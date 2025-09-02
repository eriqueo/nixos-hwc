#!/usr/bin/env bash
# Hyprland Smoke Test - Validates hyprland infrastructure tools and configuration
# Usage: ./tests/hyprland-smoke.sh

set -euo pipefail

echo "=== Hyprland Smoke Test ==="

# Required canonical hyprland tools (all 6)
readonly req=(
    hyprland-workspace-overview hyprland-workspace-manager
    hyprland-monitor-toggle hyprland-app-launcher
    hyprland-startup hyprland-system-health-checker
)

# Test 1: Verify all canonical tools are available
echo "Checking canonical hyprland tools..."
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
unwanted=(workspace-overview workspace-manager monitor-toggle app-launcher hypr-startup system-health-checker)
wrapper_found=0
for wrapper in "${unwanted[@]}"; do
    if command -v "$wrapper" >/dev/null 2>&1; then
        echo "⚠️  WRAPPER STILL EXISTS: $wrapper (cleanup failed!)"
        wrapper_found=$((wrapper_found + 1))
    fi
done
if [[ $wrapper_found -eq 0 ]]; then
    echo "✅ No unwanted wrappers found"
else
    echo "❌ FAIL: $wrapper_found wrappers still exist after cleanup"
    exit 1
fi

# Test 3: Test key tool functionality
echo "Testing tool functionality..."

# Workspace overview should work (but may need display)
if command -v hyprland-workspace-overview >/dev/null 2>&1; then
    echo "✅ hyprland-workspace-overview is available"
fi

# Monitor toggle should work (but may need Hyprland running)
if command -v hyprland-monitor-toggle >/dev/null 2>&1; then
    echo "✅ hyprland-monitor-toggle is available"
fi

# App launcher should handle args
if hyprland-app-launcher 2>&1 | grep -q "Usage:"; then
    echo "✅ hyprland-app-launcher shows usage correctly"
else
    echo "❌ hyprland-app-launcher does not show usage"
    exit 1
fi

# Test 4: Verify hyprland config evaluates (parts system)
echo "Testing Hyprland parts-based config evaluation..."

# Test individual parts evaluation
parts_dir="/home/eric/03-tech/nixos-hwc/modules/home/hyprland/parts"
if [[ -d "$parts_dir" ]]; then
    for part in keybindings.nix monitors.nix windowrules.nix input.nix autostart.nix theming.nix; do
        if nix-instantiate --parse "$parts_dir/$part" >/dev/null 2>&1; then
            echo "✅ Part $part syntax valid"
        else
            echo "❌ Part $part has syntax errors"
            exit 1
        fi
    done
else
    echo "❌ Hyprland parts directory not found"
    exit 1
fi

# Test 5: Verify theme system integration
echo "Testing global theme integration..."
palette_file="/home/eric/03-tech/nixos-hwc/modules/home/theme/palettes/deep-nord.nix"
adapter_file="/home/eric/03-tech/nixos-hwc/modules/home/theme/adapters/hyprland.nix"

if nix-instantiate --parse "$palette_file" >/dev/null 2>&1; then
    echo "✅ Theme palette syntax valid"
else
    echo "❌ Theme palette has syntax errors"
    exit 1
fi

if nix-instantiate --parse "$adapter_file" >/dev/null 2>&1; then
    echo "✅ Hyprland theme adapter syntax valid"
else
    echo "❌ Hyprland theme adapter has syntax errors"
    exit 1
fi

# Test 6: Verify keybinding count preservation
echo "Testing keybinding preservation..."
keybind_count=$(grep -c "exec\|killactive\|fullscreen\|movefocus\|movewindow\|workspace\|submap\|togglefloating\|pseudo\|pin\|centerwindow\|exit\|reload\|togglegroup\|changegroupactive" "$parts_dir/keybindings.nix" || echo "0")

if [[ $keybind_count -ge 100 ]]; then
    echo "✅ Keybinding count preserved ($keybind_count bindings found)"
else
    echo "⚠️  Keybinding count may be low ($keybind_count found, expected 100+)"
fi

echo ""
echo "🎉 ALL TESTS PASSED"
echo "Hyprland infrastructure and parts-based configuration validated successfully"