#!/bin/bash
# Quick Start Script for NixOS Configuration Validation
# Usage: ./quick-start.sh <old-config-path> <new-config-path>

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <old-config-path> <new-config-path>"
    echo "Example: $0 /etc/nixos /home/eric/.nixos"
    exit 1
fi

OLD_CONFIG="$1"
NEW_CONFIG="$2"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="/tmp/config-validation-$TIMESTAMP"

echo "🔍 NixOS Configuration Validation - Quick Start"
echo "=============================================="
echo "Old config: $OLD_CONFIG"
echo "New config: $NEW_CONFIG"
echo "Results: $RESULTS_DIR"
echo

# Create results directory
mkdir -p "$RESULTS_DIR"

# Run static analysis
echo "📊 Running static configuration analysis..."
./config-extractor.py "$OLD_CONFIG" > "$RESULTS_DIR/old-config.json" 2>/dev/null || echo "⚠️  Old config analysis had warnings"
./config-extractor.py "$NEW_CONFIG" > "$RESULTS_DIR/new-config.json" 2>/dev/null || echo "⚠️  New config analysis had warnings"

# SABnzbd-specific validation
echo "🎬 Validating SABnzbd event system..."
./sabnzbd-analyzer.py "$OLD_CONFIG" > "$RESULTS_DIR/old-sabnzbd.json" 2>/dev/null || echo "⚠️  Old SABnzbd analysis had warnings"
./sabnzbd-analyzer.py "$NEW_CONFIG" > "$RESULTS_DIR/new-sabnzbd.json" 2>/dev/null || echo "⚠️  New SABnzbd analysis had warnings"

# Compare configurations
echo "🔄 Comparing configurations..."
./config-differ.sh "$RESULTS_DIR/old-config.json" "$RESULTS_DIR/new-config.json" > "$RESULTS_DIR/comparison.txt" 2>/dev/null || echo "⚠️  Comparison had warnings"

# Generate summary report
echo "📋 Generating validation summary..."
cat > "$RESULTS_DIR/summary.md" << EOF
# Configuration Validation Summary

**Timestamp**: $(date -Iseconds)  
**Old Config**: $OLD_CONFIG  
**New Config**: $NEW_CONFIG  

## Container Count Comparison
- Old: $(jq '.containers | length' "$RESULTS_DIR/old-config.json" 2>/dev/null || echo "unknown")
- New: $(jq '.containers | length' "$RESULTS_DIR/new-config.json" 2>/dev/null || echo "unknown")

## SABnzbd Events System Validation
### Old Config
- Events system working: $(jq -r '.validation.events_system_working' "$RESULTS_DIR/old-sabnzbd.json" 2>/dev/null || echo "unknown")
- Missing components: $(jq -r '.validation.missing_components | length' "$RESULTS_DIR/old-sabnzbd.json" 2>/dev/null || echo "unknown")

### New Config  
- Events system working: $(jq -r '.validation.events_system_working' "$RESULTS_DIR/new-sabnzbd.json" 2>/dev/null || echo "unknown")
- Missing components: $(jq -r '.validation.missing_components | length' "$RESULTS_DIR/new-sabnzbd.json" 2>/dev/null || echo "unknown")

## Service Count Comparison
- Old: $(jq '.systemd_services | length' "$RESULTS_DIR/old-config.json" 2>/dev/null || echo "unknown")
- New: $(jq '.systemd_services | length' "$RESULTS_DIR/new-config.json" 2>/dev/null || echo "unknown")

## Critical Services Check
- Old has media-orchestrator: $(jq -r '.systemd_services | has("media-orchestrator")' "$RESULTS_DIR/old-config.json" 2>/dev/null || echo "unknown")
- New has media-orchestrator: $(jq -r '.systemd_services | has("media-orchestrator")' "$RESULTS_DIR/new-config.json" 2>/dev/null || echo "unknown")

## Files Generated
- \`old-config.json\` - Complete old configuration analysis
- \`new-config.json\` - Complete new configuration analysis  
- \`old-sabnzbd.json\` - Old SABnzbd validation
- \`new-sabnzbd.json\` - New SABnzbd validation
- \`comparison.txt\` - Detailed comparison output
- \`summary.md\` - This summary

## Next Steps
1. Review \`comparison.txt\` for detailed differences
2. Check \`new-sabnzbd.json\` validation results
3. Fix any missing components in new config
4. Re-run validation until clean
5. Proceed with deployment only when validation passes
EOF

# Show quick results
echo
echo "✅ Validation Complete!"
echo "📁 Results saved to: $RESULTS_DIR"
echo
echo "🎯 Quick Summary:"
echo "   Old containers: $(jq '.containers | length' "$RESULTS_DIR/old-config.json" 2>/dev/null || echo "?")"
echo "   New containers: $(jq '.containers | length' "$RESULTS_DIR/new-config.json" 2>/dev/null || echo "?")"
echo "   Old SABnzbd OK: $(jq -r '.validation.events_system_working' "$RESULTS_DIR/old-sabnzbd.json" 2>/dev/null || echo "?")"
echo "   New SABnzbd OK: $(jq -r '.validation.events_system_working' "$RESULTS_DIR/new-sabnzbd.json" 2>/dev/null || echo "?")"
echo
echo "📖 View full summary: cat $RESULTS_DIR/summary.md"
echo "🔍 View differences: cat $RESULTS_DIR/comparison.txt"
echo
if [[ "$(jq -r '.validation.events_system_working' "$RESULTS_DIR/new-sabnzbd.json" 2>/dev/null)" == "true" ]]; then
    echo "🟢 SABnzbd validation: PASSED"
else
    echo "🔴 SABnzbd validation: FAILED - Check missing components"
    echo "   Missing: $(jq -r '.validation.missing_components[]' "$RESULTS_DIR/new-sabnzbd.json" 2>/dev/null | paste -sd, -)"
fi