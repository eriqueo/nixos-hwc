#!/usr/bin/env bash
# Same rule producer as checks.<system>.charter-law*. No automatic fixes.
set -euo pipefail
root=$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")/../.." && pwd)
exec python3 "$root/workspace/nixos-dev/verification/charter.py" --root "$root" "$@"
