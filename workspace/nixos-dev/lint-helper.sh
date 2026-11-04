#!/usr/bin/env bash
# Compatibility entry point. The canonical scanner emits structured results.
set -euo pipefail
exec "$(dirname -- "${BASH_SOURCE[0]}")/charter-lint.sh" "$@"
