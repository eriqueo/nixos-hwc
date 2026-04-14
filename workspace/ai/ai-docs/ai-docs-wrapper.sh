#!/usr/bin/env bash
# Wrapper for AI documentation generator to ensure proper Python environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PYTHONPATH="/run/current-system/sw/lib/python3.13/site-packages:$PYTHONPATH"
/run/current-system/sw/bin/python3 "${SCRIPT_DIR}/ai-narrative-docs.py" "$@"
