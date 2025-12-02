#!/usr/bin/env bash
# Charter v4 Section Header Addition Script
# Adds standard #=== section headers to modules

set -euo pipefail

add_section_headers() {
    local filepath="$1"
    echo "Processing: $filepath"
    
    # Check if already has section headers
    if grep -q "#============================================================================" "$filepath" 2>/dev/null; then
        echo "  ✓ Already has section headers"
        return
    fi
    
    local tmpfile=$(mktemp)
    local in_options=false
    local in_config=false
    local added_options_header=false
    local added_impl_header=false
    local added_validation_header=false
    
    while IFS= read -r line; do
        # Detect options section
        if [[ "$line" =~ ^[[:space:]]*options\. ]] && [ "$added_options_header" = false ]; then
            echo "  #============================================================================"
            echo "  # OPTIONS - What can be configured"
            echo "  #============================================================================"
            added_options_header=true
        fi
        
        # Detect config section
        if [[ "$line" =~ ^[[:space:]]*config[[:space:]]*= ]] && [ "$added_impl_header" = false ]; then
            if [ "$added_options_header" = true ]; then
                echo ""
            fi
            echo "  #============================================================================"
            echo "  # IMPLEMENTATION - What actually gets configured"
            echo "  #============================================================================"
            added_impl_header=true
        fi
        
        # Detect assertions section
        if [[ "$line" =~ assertions[[:space:]]*= ]] && [ "$added_validation_header" = false ]; then
            echo ""
            echo "    #=========================================================================="
            echo "    # VALIDATION - Assertions and checks"
            echo "    #=========================================================================="
            added_validation_header=true
        fi
        
        echo "$line"
        
    done < "$filepath" > "$tmpfile"
    
    mv "$tmpfile" "$filepath"
    echo "  ✓ Added section headers"
}

# Main execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <file1.nix> [file2.nix ...]"
    echo "   or: $0 --all  (to add section headers to all modules)"
    exit 1
fi

if [ "$1" = "--all" ]; then
    echo "🔄 Adding section headers to all modules..."
    
    find domains/ -name "*.nix" -not -path "*/.*" | while read -r file; do
        add_section_headers "$file"
    done
    
    echo "✅ Section headers added to all modules!"
else
    for file in "$@"; do
        if [ -f "$file" ]; then
            add_section_headers "$file"
        else
            echo "⚠️  File not found: $file"
        fi
    done
fi

echo
echo "📋 Next steps:"
echo "1. Review generated section headers"
echo "2. Run validation: ./scripts/validate-charter-v4.sh"