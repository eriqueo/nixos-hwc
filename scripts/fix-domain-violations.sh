#!/usr/bin/env bash
# Charter v4 Domain Violation Fixer
# Moves hardware scripts from home/ to infrastructure/

set -euo pipefail

echo "🔧 Fixing Charter v4 domain violations..."

# Function to extract writeScriptBin from files and move to infrastructure
extract_hardware_scripts() {
    local source_file="$1"
    local target_domain="$2"
    
    echo "Extracting hardware scripts from: $source_file"
    
    # Find hardware scripts in the file
    if grep -q "writeScriptBin\|writeShellScript" "$source_file"; then
        echo "  ⚠️  Found hardware scripts - manual intervention needed"
        echo "     Review: $source_file"
        echo "     These scripts should be moved to domains/infrastructure/"
    fi
}

# Function to remove hardware config from services
fix_hardware_in_services() {
    echo "Checking for hardware config in services..."
    
    if rg -q "hardware\." domains/services/; then
        echo "  ⚠️  Found hardware config in services:"
        rg -l "hardware\." domains/services/ | sed 's/^/     /'
        echo "     These should be moved to infrastructure/ or use capability flags"
    fi
}

# Function to remove system services from home
fix_system_services_in_home() {
    echo "Checking for system services in home..."
    
    if rg -q "systemd\.services" domains/home/; then
        echo "  ⚠️  Found system services in home:"
        rg -l "systemd\.services" domains/home/ | sed 's/^/     /'
        echo "     These should be moved to services/ domain"
    fi
}

echo "=== Domain Violation Analysis ==="

# Check home/ for hardware scripts
echo "1. Hardware scripts in home/ modules:"
find domains/home/ -name "*.nix" | while read -r file; do
    if grep -q "writeScriptBin\|writeShellScript" "$file"; then
        extract_hardware_scripts "$file" "infrastructure"
    fi
done

echo
echo "2. Hardware configuration in services/ modules:"
fix_hardware_in_services

echo
echo "3. System services in home/ modules:"
fix_system_services_in_home

echo
echo "=== Specific Violations Found ==="

# Analyze specific problematic files
echo "📁 domains/home/waybar/tools/gpu.nix"
if [ -f "domains/home/waybar/tools/gpu.nix" ]; then
    echo "  → This GPU tool should move to domains/infrastructure/waybar-gpu-tools.nix"
    echo "  → The waybar module should only reference the binary names"
fi

echo
echo "📁 domains/home/waybar/scripts.nix"
if [ -f "domains/home/waybar/scripts.nix" ]; then
    echo "  → Hardware monitoring scripts should move to domains/infrastructure/"
    echo "  → Keep only UI configuration in waybar/"
fi

echo
echo "📁 domains/services/media/gpu-consolidated.nix"
if [ -f "domains/services/media/gpu-consolidated.nix" ]; then
    echo "  → GPU configuration should move to domains/infrastructure/gpu.nix"
    echo "  → Services should consume GPU capabilities, not configure hardware"
fi

echo
echo "=== Recommended Actions ==="
echo "1. Move hardware scripts to infrastructure/ domain"
echo "2. Update waybar widgets to call binaries instead of embedding scripts"
echo "3. Use capability flags (hwc.infrastructure.gpu.accel) in services"
echo "4. Remove direct hardware configuration from services"
echo
echo "⚠️  These changes require manual intervention due to interdependencies"
echo "🔍 Run './scripts/validate-charter-v4.sh' after making changes"