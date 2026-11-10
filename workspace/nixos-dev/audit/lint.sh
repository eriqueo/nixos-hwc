#!/usr/bin/env bash
# Permanent operator entry; the canonical charter checker owns current rules.
set -euo pipefail
root=$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")/../../.." && pwd)
exec "$root/workspace/nixos-dev/charter-lint.sh" "$@"
