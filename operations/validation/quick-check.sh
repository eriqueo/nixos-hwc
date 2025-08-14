#!/usr/bin/env bash
echo "=== Quick Validation ==="
echo "Old repo builds: $(cd /etc/nixos && nixos-rebuild build --flake .#hwc-server &>/dev/null && echo \"✅\" || echo \"❌\")"
echo "New repo exists: $([ -d /etc/nixos-next ] && echo \"✅\" || echo \"❌\")"
echo "Git status clean: $(cd /etc/nixos-next && git status --porcelain | wc -l | grep -q \"^0$\" && echo \"✅\" || echo \"❌\")"
