#!/usr/bin/env bash
# Permanent shell entry for operators; PostgreSQL owns the exported catalog.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/export_catalog.py" "$@"
