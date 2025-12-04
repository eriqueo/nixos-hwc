#!/usr/bin/env bash

# Quick manual check for namespace safety
# Just run the grep commands directly

echo "=== Checking namespace usage manually ==="
echo

echo "1. Checking options.hwc.home.shell:"
echo "Definitions:"
grep -r "options\.hwc\.home\.shell" . --include="*.nix" | head -3
echo "Usage:"
grep -r "config\.hwc\.home\.shell" . --include="*.nix" | head -3
echo

echo "2. Checking options.hwc.home.productivity:"
echo "Definitions:"
grep -r "options\.hwc\.home\.productivity" . --include="*.nix" | head -3
echo "Usage:"
grep -r "config\.hwc\.home\.productivity" . --include="*.nix" | head -3
echo

echo "3. Checking options.hwc.home.development:"
echo "Definitions:"
grep -r "options\.hwc\.home\.development" . --include="*.nix" | head -3
echo "Usage:"
grep -r "config\.hwc\.home\.development" . --include="*.nix" | head -3
echo

echo "4. Checking options.hwc.home.fonts:"
echo "Definitions:"
grep -r "options\.hwc\.home\.fonts" . --include="*.nix" | head -3
echo "Usage:"
grep -r "config\.hwc\.home\.fonts" . --include="*.nix" | head -3
echo

echo "=== Analysis ==="
echo "If you see:"
echo "- Only 1 definition line and no usage lines = SAFE to automate"
echo "- Multiple definition lines = UNSAFE, manual review needed"  
echo "- Usage lines = CAUTION, must update all files together"
