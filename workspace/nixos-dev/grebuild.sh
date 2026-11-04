#!/usr/bin/env bash
# Explicitly staged commit, verified fast-forward integration, then system switch.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
message=""
candidate=HEAD
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message) message="${2:?commit message required}"; shift 2 ;;
    --candidate) candidate="${2:?candidate ref required}"; shift 2 ;;
    -h|--help)
      echo 'Usage: rebuild [-m "message"] [--candidate branch]'
      echo 'Stage exact paths yourself. The gate verifies before main moves or activation starts.'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
cd "$repo"
[[ $(git branch --show-current) == main ]] || { echo 'Run rebuild from the primary main checkout' >&2; exit 1; }
git diff --quiet || { echo 'Unstaged changes: stage exact paths before rebuild' >&2; exit 1; }
if ! git diff --cached --quiet; then
  [[ -n "$message" ]] || { echo 'Use -m for the explicitly staged commit' >&2; exit 1; }
  git commit -m "$message"
fi
python3 "$repo/workspace/nixos-dev/verification/release.py" deploy --repo "$repo" --candidate "$candidate"
git push origin main
