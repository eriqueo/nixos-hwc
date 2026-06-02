#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Rebuilding NixOS configuration..."
sudo nixos-rebuild switch --flake .#hwc-server

echo "📡 Checking listeners..."
ss -lntp | rg ':5030|:5031|:50300'

echo "🔍 Testing local slskd access..."
if ! curl -sSf http://127.0.0.1:5031/slskd/ >/dev/null; then
    echo "❌ Local slskd access failed"
    exit 1
fi

echo "🌐 Testing external slskd access..."
if ! curl -sSf https://hwc-server.ocelot-wahoo.ts.net/slskd/ >/dev/null; then
    echo "❌ External slskd access failed"
    exit 1
fi

echo "📦 Testing static assets..."
for asset in static/js/main static/css/main; do
    asset_url=$(curl -s https://hwc-server.ocelot-wahoo.ts.net/slskd/ | rg -o "${asset}\.[a-f0-9]+\.(js|css)" | head -1)
    if [ -n "$asset_url" ]; then
        if ! curl -sSf "https://hwc-server.ocelot-wahoo.ts.net/slskd/$asset_url" >/dev/null; then
            echo "❌ Asset $asset_url failed to load"
            exit 1
        fi
    fi
done

echo "🔌 Checking Soulseek port..."
if ! ss -lntp | rg -q '0\.0\.0\.0:50300'; then
    echo "❌ Soulseek port 50300 not listening"
    exit 1
fi

public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "")
if [ -n "$public_ip" ]; then
    if ! timeout 5 nc -zv "$public_ip" 50300 2>/dev/null; then
        echo "⚠️  Forward WAN TCP 50300 → host:50300 on your router."
    fi
else
    echo "⚠️  Forward WAN TCP 50300 → host:50300 on your router."
fi

echo "✅ slskd verification complete"