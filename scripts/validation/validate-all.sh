#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/compare-configs.sh"
bash "$SCRIPT_DIR/compare-services.sh"
# quick-check may fail if nixos-rebuild is missing but we still attempt it
if ! bash "$SCRIPT_DIR/quick-check.sh"; then
  echo "quick-check.sh failed; ensure nixos-rebuild is installed" >&2
fi
