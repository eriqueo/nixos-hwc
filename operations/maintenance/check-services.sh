#!/usr/bin/env bash

echo "=== Service Health Check ==="

SERVICES=(
    "prometheus"
    "grafana" 
    "jellyfin"
    "frigate"
    "ollama"
    "postgresql"
    "redis"
    "caddy"
)

FAILED=0

for service in "${SERVICES[@]}"; do
    printf "%-20s" "$service:"
    if systemctl is-active --quiet "$service"; then
        echo "✅ Active"
    else
        echo "❌ Inactive"
        ((FAILED++))
    fi
done

echo ""
if [ $FAILED -eq 0 ]; then
    echo "✅ All services healthy"
else
    echo "⚠️  $FAILED services need attention"
fi
