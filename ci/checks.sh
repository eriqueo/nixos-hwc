#!/usr/bin/env bash
set -euo pipefail

# Ensure primitive paths module exists and contains header

if [ ! -f domains/paths/paths.nix ]; then
  echo "domains/paths/paths.nix missing"
  exit 1
fi

if ! rg 'Primitive Module Exception' domains/paths/paths.nix >/dev/null 2>&1; then
  echo "paths.nix missing required Primitive Module Exception header"
  exit 1
fi

echo "CI checks: domains/paths OK"
