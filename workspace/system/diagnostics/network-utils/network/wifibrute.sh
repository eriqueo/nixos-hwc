#!/usr/bin/env bash
set -euo pipefail
# Permanent compatibility entry for old paths; network/network owns the script.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$SCRIPT_DIR/../../network/network/wifibrute.sh" "$@"
