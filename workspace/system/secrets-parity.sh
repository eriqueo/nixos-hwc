#!/usr/bin/env bash
# secrets-parity.sh — self-consistency checks for the generated agenix layer.
#
# The recipient rules (secrets.nix) and the age.secrets mounts
# (domains/secrets/declarations/generated.nix) are both GENERATED from the tree
# of *.age files under domains/secrets/parts/ (see domains/secrets/lib.nix).
# This script asserts the generator stayed consistent with that tree:
#
#   1. every parts/**.age (excluding caddy/) has a recipient rule
#   2. every recipient rule points at a .age file that exists
#   3. every parts/**.age (excluding caddy/) is mounted in age.secrets
#   4. mount count == (parts .age excl caddy) + 2 caddy runtime mounts
#
# Run from the repo root. Read-only. Exit non-zero on any mismatch.
#
# For a preserve-first REFACTOR diff (prove the generated set equals a previous
# explicit set byte-for-byte), capture baselines from the old commit first:
#   nix eval --impure --json ".#nixosConfigurations.<host>.config.age.secrets" \
#     --apply 'ss: builtins.mapAttrs (n: s: { file = baseNameOf (toString s.file);
#              mode = s.mode; owner = s.owner; group = s.group; }) ss' > old-<host>.json
# then re-run on the new commit and diff old-<host>.json vs new-<host>.json.
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"
HOST="${1:-$(hostname)}"
fail=0

echo "== secrets parity ($HOST) =="

# Files on disk (excl caddy/ runtime certs)
mapfile -t partsfiles < <(
  cd domains/secrets/parts && find . -name '*.age' -type f \
    | sed 's|^\./||' | grep -v '^caddy/' | sort
)
echo "parts .age (excl caddy): ${#partsfiles[@]}"

# Recipient rule paths (keys of secrets.nix), basenames of mounts.
mapfile -t rulepaths < <(
  nix eval --impure --json --expr "builtins.attrNames (import $REPO/secrets.nix)" \
    | jq -r '.[]' | sort
)
mapfile -t mountnames < <(
  nix eval --impure --json ".#nixosConfigurations.$HOST.config.age.secrets" \
    --apply 'ss: builtins.attrNames ss' | jq -r '.[]' | sort
)
echo "recipient rules: ${#rulepaths[@]} | mounts: ${#mountnames[@]}"

# 1 + 2: rules <-> files on disk (rule key is the repo-relative path)
for f in "${partsfiles[@]}"; do
  printf '%s\n' "${rulepaths[@]}" | grep -qxF "domains/secrets/parts/$f" \
    || { echo "  MISSING RULE: $f"; fail=1; }
done
for r in "${rulepaths[@]}"; do
  [ -e "$r" ] || { echo "  DANGLING RULE (no file): $r"; fail=1; }
done

# 4: mount count == parts(excl caddy) + 2 caddy
expected=$(( ${#partsfiles[@]} + 2 ))
[ "${#mountnames[@]}" -eq "$expected" ] \
  || { echo "  MOUNT COUNT $((${#mountnames[@]})) != expected $expected"; fail=1; }

if [ "$fail" -eq 0 ]; then echo "✓ parity OK"; else echo "✗ parity FAILED"; fi
exit "$fail"
