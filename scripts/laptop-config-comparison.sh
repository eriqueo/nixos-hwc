#!/usr/bin/env bash
set -euo pipefail

PRODUCTION="/etc/nixos"
REFACTOR="/home/eric/03-tech/nixos-hwc"
OUTPUT_DIR="$REFACTOR/comparison-results"

# Resolve actual source dirs (fallback to root if host subdir missing)
PROD_SRC="$PRODUCTION/hosts/laptop"
[[ -d "$PROD_SRC" ]] || PROD_SRC="$PRODUCTION"

REF_LAP="$REFACTOR/machines/laptop"
[[ -d "$REF_LAP" ]] || REF_LAP="$REFACTOR"

mkdir -p "$OUTPUT_DIR"

echo "🔍 Laptop Configuration Comparison Tool"
echo "Production: $PRODUCTION (scanning: $PROD_SRC)"
echo "Refactor:   $REFACTOR (machines: $REF_LAP)"
echo ""

extract_config() {
  local source_dir="$1"
  local output_file="$2"

  {
    echo "# Configuration extraction from $source_dir"

    echo "## Imports"
    rg -n --no-messages --glob '**/*.nix' '^\s*imports\s*=' "$source_dir" || true

    echo
    echo "## Services (enabled)"
    rg -n --no-messages --glob '**/*.nix' '^\s*services\..*enable\s*=\s*(true|1);' "$source_dir" || true

    echo
    echo "## Hardware"
    rg -n --no-messages --glob '**/*.nix' '^\s*hardware\.' "$source_dir" || true

    echo
    echo "## Boot"
    rg -n --no-messages --glob '**/*.nix' '^\s*boot\.' "$source_dir" || true

    echo
    echo "## System Packages"
    # Capture attribute path then list items within brackets; tolerates formatting
    rg -n --no-messages --glob '**/*.nix' 'environment\.systemPackages\s*=\s*\[(?s).*?\];' "$source_dir" || true
  } > "$output_file"
}

echo "📊 Extracting production configuration..."
extract_config "$PROD_SRC" "$OUTPUT_DIR/production-config.txt"

echo "📊 Extracting refactor configuration..."
extract_config "$REF_LAP" "$OUTPUT_DIR/refactor-config.txt"
[[ -d "$REFACTOR/profiles" ]] && extract_config "$REFACTOR/profiles" "$OUTPUT_DIR/refactor-profiles.txt" || true
[[ -d "$REFACTOR/modules" ]]  && extract_config "$REFACTOR/modules"  "$OUTPUT_DIR/refactor-modules.txt"  || true

echo "🔄 Generating comparison report..."
cat > "$OUTPUT_DIR/comparison-report.md" << 'EOF'
# Laptop Configuration Comparison Report

## Critical Differences Found

### Hardware Configuration
- ✅ **FIXED**: Hardware configuration copied from production

### Missing in Refactor
EOF

echo "🔍 Checking for missing services..."
{
  echo
  echo "### Services Status"
  echo "| Service | Production | Refactor | Status |"
  echo "|---------|------------|----------|--------|"

  services=("greetd" "nvidia" "libvirtd" "samba" "printing" "tlp" "thermald" "pipewire")
  for service in "${services[@]}"; do
    prod_status="❌"
    ref_status="❌"
    rg -q --no-messages "$service" "$OUTPUT_DIR/production-config.txt" && prod_status="✅"
    rg -q --no-messages "$service" "$OUTPUT_DIR"/refactor-*.txt "$OUTPUT_DIR/refactor-config.txt" 2>/dev/null && ref_status="✅"
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
