#!/usr/bin/env bash

SERVICE="ntfy"

echo "=== Service Comparison: $SERVICE ==="

# Check old config
echo "Old config location: /etc/nixos/hosts/server/domains/"
ls -la /etc/nixos/hosts/server/domains/*ntfy* 2>/dev/null || echo "No ntfy in old"

# Check new config  
echo "New config location: /etc/nixos-next/domains/services/"
ls -la /etc/nixos-next/domains/services/ntfy.nix

# Compare outputs
echo ""
echo "Old build size:"
du -sh /etc/nixos/result 2>/dev/null || echo "No result link"

echo "New build size:"
du -sh /etc/nixos-next/result 2>/dev/null || echo "No result link"

echo ""
echo "✅ Service migrated (not activated, just configured)"
