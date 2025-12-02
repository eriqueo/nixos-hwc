#!/usr/bin/env bash
# Simple container validation script
# Usage: ./scripts/validate-containers.sh

set -euo pipefail

echo "Container Validation Report"
echo "==========================="
echo ""

CONTAINERS_DIR="domains/server/containers"
charter_v6_count=0
mkcontainer_count=0
unknown_count=0

echo "Checking all containers for Charter v6 compliance..."
echo ""

for container_dir in "$CONTAINERS_DIR"/*/; do
  container=$(basename "$container_dir")

  # Skip _shared
  if [[ "$container" == _* ]]; then
    continue
  fi

  echo "Container: $container"

  # Check for Charter v6 pattern (assertions)
  if [[ -f "$container_dir/parts/config.nix" ]]; then
    if grep -q "ASSERTIONS AND VALIDATION" "$container_dir/parts/config.nix" 2>/dev/null; then
      echo "  ✅ Charter v6 compliant (has assertions)"
      charter_v6_count=$((charter_v6_count + 1))
    else
      echo "  ⚠️  Has parts/config.nix but no assertions"
      unknown_count=$((unknown_count + 1))
    fi
  elif [[ -f "$container_dir/sys.nix" ]]; then
    if grep -q "mkContainer" "$container_dir/sys.nix" 2>/dev/null; then
      echo "  📦 Uses mkContainer helper (needs migration)"
      mkcontainer_count=$((mkcontainer_count + 1))
    else
      echo "  ⚠️  Unknown pattern"
      unknown_count=$((unknown_count + 1))
    fi
  else
    echo "  ❌ Missing implementation file"
    unknown_count=$((unknown_count + 1))
  fi

  # Check networking
  if [[ -f "$container_dir/sys.nix" ]] || [[ -f "$container_dir/parts/config.nix" ]]; then
    config_file="${container_dir}/sys.nix"
    [[ -f "$container_dir/parts/config.nix" ]] && config_file="$container_dir/parts/config.nix"

    if grep -q "networkMode.*cfg.network.mode" "$config_file" 2>/dev/null; then
      echo "  🌐 Configurable network mode"
    elif grep -q "network=container:gluetun" "$config_file" 2>/dev/null; then
      echo "  🔒 VPN mode (hardcoded)"
    elif grep -q "network=media-network" "$config_file" 2>/dev/null; then
      echo "  📡 Media network (hardcoded)"
    fi
  fi

  echo ""
done

echo ""
echo "Summary:"
echo "--------"
echo "  Charter v6 compliant: $charter_v6_count"
echo "  Uses mkContainer: $mkcontainer_count (need migration)"
echo "  Unknown/Other: $unknown_count"
echo ""
total=$((charter_v6_count + mkcontainer_count + unknown_count))
if [[ $total -gt 0 ]]; then
  percentage=$((charter_v6_count * 100 / total))
  echo "  Charter v6 completion: $percentage%"
else
  echo "  Charter v6 completion: N/A"
fi
echo ""
echo "For detailed analysis, see: docs/architecture/CONTAINER_CONSISTENCY_ANALYSIS.md"
