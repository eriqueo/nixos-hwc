#!/usr/bin/env bash
# Configuration comparison script for laptop migration
# Compares production /etc/nixos vs refactored nixos-hwc

set -euo pipefail

PRODUCTION="/etc/nixos"
REFACTOR="/home/eric/03-tech/nixos-hwc"
OUTPUT_DIR="$REFACTOR/comparison-results"

echo "🔍 Laptop Configuration Comparison Tool"
echo "Production: $PRODUCTION"
echo "Refactor:   $REFACTOR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to extract configuration elements
extract_config() {
    local source_dir="$1"
    local output_file="$2"
    
    echo "# Configuration extraction from $source_dir" > "$output_file"
    echo "## Imports" >> "$output_file"
    find "$source_dir" -name "*.nix" -exec grep -l "imports.*=" {} \; | \
        xargs grep -h "imports.*=" | sort | uniq >> "$output_file"
    
    echo -e "\n## Services" >> "$output_file"
    find "$source_dir" -name "*.nix" -exec grep -l "services\." {} \; | \
        xargs grep -h "services\." | grep "enable.*=" | sort | uniq >> "$output_file"
    
    echo -e "\n## Hardware" >> "$output_file"
    find "$source_dir" -name "*.nix" -exec grep -l "hardware\." {} \; | \
        xargs grep -h "hardware\." | sort | uniq >> "$output_file"
    
    echo -e "\n## Boot" >> "$output_file"
    find "$source_dir" -name "*.nix" -exec grep -l "boot\." {} \; | \
        xargs grep -h "boot\." | sort | uniq >> "$output_file"
    
    echo -e "\n## System Packages" >> "$output_file"
    find "$source_dir" -name "*.nix" -exec grep -l "systemPackages" {} \; | \
        xargs grep -A 20 "systemPackages.*=" | grep -E "^\s*[a-zA-Z]" | sort | uniq >> "$output_file"
}

# Extract configurations
echo "📊 Extracting production configuration..."
extract_config "$PRODUCTION/hosts/laptop" "$OUTPUT_DIR/production-config.txt"

echo "📊 Extracting refactor configuration..."
extract_config "$REFACTOR/machines/laptop" "$OUTPUT_DIR/refactor-config.txt"
extract_config "$REFACTOR/profiles" "$OUTPUT_DIR/refactor-profiles.txt"
extract_config "$REFACTOR/modules" "$OUTPUT_DIR/refactor-modules.txt"

# Compare key differences
echo "🔄 Generating comparison report..."
cat > "$OUTPUT_DIR/comparison-report.md" << 'EOF'
# Laptop Configuration Comparison Report

## Critical Differences Found

### Hardware Configuration
- ✅ **FIXED**: Hardware configuration copied from production

### Missing in Refactor
EOF

# Check for missing services
echo "🔍 Checking for missing services..."
{
    echo -e "\n### Services Status"
    echo "| Service | Production | Refactor | Status |"
    echo "|---------|------------|----------|--------|"
    
    # Key services to check
    services=("greetd" "nvidia" "libvirtd" "samba" "printing" "tlp" "thermald" "pipewire")
    
    for service in "${services[@]}"; do
        prod_status=""
        ref_status=""
        
        if grep -q "$service" "$OUTPUT_DIR/production-config.txt" 2>/dev/null; then
            prod_status="✅"
        else
            prod_status="❌"
        fi
        
        if grep -q "$service" "$OUTPUT_DIR/refactor-"*.txt 2>/dev/null; then
            ref_status="✅"
        else
            ref_status="❌"
        fi
        
        if [[ "$prod_status" == "✅" && "$ref_status" == "❌" ]]; then
            status="🚨 MISSING"
        elif [[ "$prod_status" == "✅" && "$ref_status" == "✅" ]]; then
            status="✅ OK"
        else
            status="ℹ️  N/A"
        fi
        
        echo "| $service | $prod_status | $ref_status | $status |"
    done
} >> "$OUTPUT_DIR/comparison-report.md"

# Generate action items
cat >> "$OUTPUT_DIR/comparison-report.md" << 'EOF'

## Action Items Required

### 🔥 Critical (System Won't Work)
- [ ] Enable NVIDIA GPU configuration with PRIME
- [ ] Configure greetd login manager
- [ ] Fix container runtime (switch to Podman)

### 🚨 Important (Core Functionality)
- [ ] Enable libvirtd for VM support
- [ ] Configure Samba for SketchUp share
- [ ] Set up printing drivers
- [ ] Enable SOPS secrets management

### ⚠️ Nice-to-Have (Quality of Life)
- [ ] Add missing system packages
- [ ] Verify Home Manager equivalency
- [ ] Test all hardware features

EOF

echo "✅ Comparison complete! Results in: $OUTPUT_DIR/"
echo "📋 View report: cat $OUTPUT_DIR/comparison-report.md"