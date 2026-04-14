#!/usr/bin/env bash
# Debug SLSKD Container Issues

echo "🔍 Debugging SLSKD Container..."
echo "==============================="

# 1. Check container status
echo "1. Container status:"
sudo systemctl status podman-slskd.service

echo ""
echo "2. Container volume mounts:"
sudo podman inspect slskd | grep -A 15 "Mounts" | grep -E "(Source|Destination)"

echo ""
echo "3. Container environment variables:"
sudo podman inspect slskd | grep -A 20 '"Env"'

echo ""
echo "4. Check what's actually in the container's config directory:"
sudo podman exec slskd ls -la /app/ 2>/dev/null || echo "Cannot access /app directory"

echo ""
echo "5. Check container's data directory:"
sudo podman exec slskd ls -la /data/ 2>/dev/null || echo "Cannot access /data directory"

echo ""
echo "6. Recent container logs:"
sudo podman logs slskd --tail 20

echo ""
echo "📋 Expected vs Actual:"
echo "   Expected config location: /opt/downloads/slskd/slskd.yml (host)"
echo "   Container should see it at: /app/slskd.yml"
echo "   Container downloads dir: /data/downloads/soulseek"
echo "   Host downloads dir: /mnt/hot/downloads (based on your setup)"

echo ""
echo "🔧 Quick Fix Commands:"
echo "   Stop container:     sudo systemctl stop podman-slskd.service"
echo "   Remove container:   sudo podman rm slskd"
echo "   Check NixOS config: sudo nano /etc/nixos/hosts/server/modules/media-containers-v2.nix"
echo "   Rebuild system:     sudo nixos-rebuild switch"
