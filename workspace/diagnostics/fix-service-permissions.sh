#!/usr/bin/env bash
#
# fix-service-permissions.sh
# One-time migration script to change ownership of service data directories from service users to eric
#
# This is part of the permission simplification initiative to run all services as eric:users
# instead of individual service users (jellyfin, navidrome, etc.)
#
# IMPORTANT: Run this script BEFORE rebuilding with the new configuration!
# sudo bash workspace/utilities/fix-service-permissions.sh

set -euo pipefail

echo "=========================================="
echo "Service Permission Migration Script"
echo "=========================================="
echo ""
echo "This script will change ownership of service data directories to eric:users"
echo "for simplified permission management on single-user systems."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

# Function to change ownership if directory exists
fix_ownership() {
  local dir=$1
  local service_name=$2

  if [ -d "$dir" ]; then
    echo "[INFO] Fixing ownership: $dir ($service_name)"
    chown -R eric:users "$dir"
    echo "  ✓ Changed ownership of $dir to eric:users"
  else
    echo "[SKIP] Directory does not exist: $dir ($service_name)"
  fi
}

echo ""
echo "Starting ownership migration..."
echo ""

# Jellyfin
fix_ownership "/var/lib/jellyfin" "jellyfin"

# Navidrome (check both possible locations)
fix_ownership "/var/lib/navidrome" "navidrome"
fix_ownership "/opt/downloads/navidrome" "navidrome"

# Immich
fix_ownership "/var/lib/immich" "immich"

# Grafana
fix_ownership "/var/lib/grafana" "grafana"
fix_ownership "/var/lib/private/grafana" "grafana (private)"

# CouchDB
fix_ownership "/var/lib/couchdb" "couchdb"

# Caddy
fix_ownership "/var/lib/caddy" "caddy"

# Prometheus
fix_ownership "/var/lib/hwc/prometheus" "prometheus"
fix_ownership "/var/lib/prometheus2" "prometheus (alt)"

# Beets (already owned by eric, but check anyway)
fix_ownership "/var/lib/beets" "beets"

echo ""
echo "=========================================="
echo "Migration Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Build the new configuration: sudo nixos-rebuild build --flake .#hwc-server"
echo "2. If build succeeds, switch: sudo nixos-rebuild switch --flake .#hwc-server"
echo "3. Verify services are running: systemctl status jellyfin navidrome immich-server grafana"
echo ""
