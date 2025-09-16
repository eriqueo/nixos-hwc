#!/usr/bin/env bash

SERVICE="ntfy"

echo "=== Service Comparison: $SERVICE ==="

# Check old config
echo "Old config location: /etc/nixos/hosts/server/modules/"
ls -la /etc/nixos/hosts/server/modules/*ntfy* 2>/dev/null || echo "No ntfy in old"

# Check new config  
echo "New config location: /etc/nixos-next/modules/services/"
ls -la /etc/nixos-next/modules/services/ntfy.nix

# Compare outputs
echo ""
echo "Old build size:"
du -sh /etc/nixos/result 2>/dev/null || echo "No result link"

echo "New build size:"
du -sh /etc/nixos-next/result 2>/dev/null || echo "No result link"

echo ""
echo "✅ Service migrated (not activated, just configured)"
