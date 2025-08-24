#!/usr/bin/env bash

# NixOS Purity Error Debugging Script
# Combines systematic analysis with targeted fixes

set -euo pipefail

echo "=== NixOS Purity Error Debugging ==="
echo

# Step 1: Find all /run references in your codebase
echo "1. Scanning for /run references..."
echo "================================"
rg -n --hidden -t nix -g '!**/.git/**' '/run/' | head -20
echo "... (showing first 20 matches)"
echo

# Step 2: Find path-typed options (the likely culprits)
echo "2. Finding path-typed options..."
echo "==============================="
echo "Options with types.path:"
rg -n --hidden -t nix -g '!**/.git/**' 'types\.path' || echo "None found"
echo
echo "Options with listOf types.path:"
rg -n --hidden -t nix -g '!**/.git/**' 'listOf\s+types\.path' || echo "None found"
echo

# Step 3: Check systemd service configs for /run paths
echo "3. Checking systemd services for /run paths..."
echo "=============================================="
echo "This requires impure evaluation for inspection:"
echo
echo "nix eval --impure --json \\"
echo "  .#nixosConfigurations.hwc-laptop.config.systemd.services.home-manager-eric.serviceConfig \\"
echo "| jq -r '"
echo "  to_entries[]"
echo "  | select("
echo "      ( .value|type == \"string\" )"
echo "      and ( .value|startswith(\"/run/\") or .value|startswith(\"/var/run/\") )"
echo "    )"
echo "  | \"\\(.key)=\\(.value)\"'"
echo
echo "If you don't have jq, use:"
echo "nix eval --impure \\"
echo "  .#nixosConfigurations.hwc-laptop.config.systemd.services.home-manager-eric.serviceConfig \\"
echo "| sed -n 's/.*\"\\([^\"]\+\\)\" *= *\"\\(\\/\\(var\\/\\)\\?run\\/[^\"]*\\)\".*/\\1=\\2/p'"
echo

# Step 4: Common fixes
echo "4. Common Fix Patterns"
echo "====================="
echo

echo "A. Change path-typed options to string-typed:"
echo "   # BAD"
echo "   myOption = lib.mkOption {"
echo "     type = lib.types.path;"
echo "     default = \"/run/agenix\";"
echo "   };"
echo "   # GOOD"
echo "   myOption = lib.mkOption {"
echo "     type = lib.types.str;"
echo "     default = \"/run/agenix\";"
echo "   };"
echo

echo "B. For EnvironmentFile (common culprit):"
echo "   # Use string path"
echo "   systemd.services.\"my-service\".serviceConfig.EnvironmentFile ="
echo "     \"/run/agenix/secrets.env\";"
echo "   # OR use secret manager path (preferred)"
echo "   systemd.services.\"my-service\".serviceConfig.EnvironmentFile ="
echo "     config.age.secrets.\"my-secret\".path;"
echo

echo "C. Add proper service dependencies (for runtime stability):"
echo "   systemd.services.my-service.after = [ \"agenix.service\" ];"
echo "   systemd.services.my-service.requires = [ \"agenix.service\" ];"
echo

# Step 5: Test build
echo "5. Test the build"
echo "================"
echo "After making changes, test with:"
echo "nix build --extra-experimental-features 'nix-command flakes' \\"
echo "  .#nixosConfigurations.hwc-laptop.config.system.build.toplevel"
echo

echo "=== End of Debugging Guide ==="
