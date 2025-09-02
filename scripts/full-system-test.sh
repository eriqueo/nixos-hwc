# scripts/full-system-test.sh
#!/usr/bin/env bash
set -euo pipefail

./scripts/validate-charter-v4.sh

machines=$(find machines/ -name "config.nix" | sed 's|machines/||; s|/config.nix||')
for m in $machines; do
  nixos-rebuild test --flake .#hwc-$m
done

echo "OK"
