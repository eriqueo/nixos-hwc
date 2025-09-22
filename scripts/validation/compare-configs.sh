#!/usr/bin/env bash

echo "=== Configuration Comparison Report ==="
echo "Date: $(date)"
echo ""

OLD_COUNT=$(find /etc/nixos -name "*.nix" -type f | xargs grep -l "services\." | wc -l)
NEW_COUNT=$(find /etc/nixos-next/domains/services -name "*.nix" | wc -l)

echo "Service Modules:"
echo "  Old structure: $OLD_COUNT files"
echo "  New structure: $NEW_COUNT modules"
echo ""

echo "Profiles created:"
ls -1 /etc/nixos-next/profiles/*.nix 2>/dev/null | xargs -n1 basename

echo ""
echo "Build sizes:"
OLD_SIZE=$(du -sh /etc/nixos/result 2>/dev/null | cut -f1)
NEW_SIZE=$(du -sh /etc/nixos-next/result 2>/dev/null | cut -f1)
echo "  Old: $OLD_SIZE"
echo "  New: $NEW_SIZE"

echo ""
echo "Storage modules:"
ls -la /etc/nixos-next/domains/infrastructure/

echo ""
echo "✅ Day 5 Progress: Media stack architecture complete"
