#!/usr/bin/env bash
# Simple Charter v4 Header Updater
# Adds Charter v4 headers to files that don't have them

set -euo pipefail

update_file() {
    local filepath="$1"
    echo "Processing: $filepath"
    
    # Check if already has Charter v4 header
    if grep -q "# DEPENDENCIES (Upstream):" "$filepath" 2>/dev/null; then
        echo "  ✓ Already has Charter v4 header"
        return
    fi
    
    # Determine domain and service
    local domain="unknown"
    local service=$(basename "$filepath" .nix)
    
    if [[ "$filepath" =~ modules/infrastructure/ ]]; then domain="infrastructure"
    elif [[ "$filepath" =~ modules/services/ ]]; then domain="services" 
    elif [[ "$filepath" =~ modules/home/ ]]; then domain="home"
    elif [[ "$filepath" =~ modules/system/ ]]; then domain="system"
    elif [[ "$filepath" =~ modules/security/ ]]; then domain="security"
    fi
    
    # Create temporary file with header
    local tmpfile=$(mktemp)
    
    # Generate relative path
    local relative_path=$(echo "$filepath" | sed 's|^\./||')
    
    # Write header
    cat > "$tmpfile" << EOF
# nixos-hwc/$relative_path
#
# $(echo "$service" | tr 'a-z-' 'A-Z ' | sed 's/  / /g') - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.$domain.$service.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../$relative_path
#
# USAGE:
#   hwc.$domain.$service.enable = true;
#   # TODO: Add specific usage examples

EOF
    
    # Append original file content
    cat "$filepath" >> "$tmpfile"
    
    # Replace original
    mv "$tmpfile" "$filepath"
    
    echo "  ✓ Added header"
}

# Main execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <file1.nix> [file2.nix ...]"
    echo "   or: $0 --all  (to update all modules without headers)"
    exit 1
fi

if [ "$1" = "--all" ]; then
    echo "🔄 Adding headers to modules without them..."
    
    # Find files without Charter v4 headers
    find modules/ -name "*.nix" -not -path "*/.*" | while read -r file; do
        if ! grep -q "# DEPENDENCIES (Upstream):" "$file" 2>/dev/null; then
            update_file "$file"
        fi
    done
    
    echo "✅ Headers added to all modules!"
else
    for file in "$@"; do
        if [ -f "$file" ]; then
            update_file "$file"
        else
            echo "⚠️  File not found: $file"
        fi
    done
fi

echo
echo "📋 Next steps:"
echo "1. Review generated headers and update TODO items"
echo "2. Run validation: ./scripts/validate-charter-v4.sh"