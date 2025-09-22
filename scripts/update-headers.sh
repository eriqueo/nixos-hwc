#!/usr/bin/env bash
# Charter v4 Header Standardization Script
# Updates module headers to Charter v4 format

set -euo pipefail

# Function to determine domain from file path
get_domain() {
    local filepath="$1"
    if [[ "$filepath" =~ domains/infrastructure/ ]]; then
        echo "infrastructure"
    elif [[ "$filepath" =~ domains/services/ ]]; then
        echo "services" 
    elif [[ "$filepath" =~ domains/home/ ]]; then
        echo "home"
    elif [[ "$filepath" =~ domains/system/ ]]; then
        echo "system"
    elif [[ "$filepath" =~ domains/security/ ]]; then
        echo "security"
    elif [[ "$filepath" =~ domains/schema/ ]]; then
        echo "schema"
    else
        echo "unknown"
    fi
}

# Function to get service name from filepath
get_service_name() {
    local filepath="$1"
    local filename=$(basename "$filepath" .nix)
    echo "$filename"
}

# Function to create Charter v4 header
create_header() {
    local filepath="$1"
    local domain=$(get_domain "$filepath")
    local service=$(get_service_name "$filepath")
    
    # Generate relative path from repo root
    local relative_path=$(echo "$filepath" | sed 's|^\./||')
    
    cat << EOF
# nixos-hwc/$relative_path
#
# $(echo "$service" | tr 'a-z-' 'A-Z ') - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (domains/system/paths.nix)
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
}

# Function to add section headers to a file
add_section_headers() {
    local filepath="$1"
    local tmpfile=$(mktemp)
    
    # Extract existing content after the { config, lib, pkgs, ... }: line
    awk '
    BEGIN { in_content = 0; printed_import = 0 }
    /^{ config, lib, pkgs.*}:/ { 
        if (!printed_import) {
            print $0
            printed_import = 1
        }
        next 
    }
    printed_import == 1 { 
        if (in_content == 0) {
            print ""
            print "let"
            print "  # TODO: Add local variables here"
            print "in {"
            print "  #============================================================================"
            print "  # OPTIONS - What can be configured"  
            print "  #============================================================================"
            print "  # TODO: Add options.hwc.domain.service = { ... };"
            print ""
            print "  #============================================================================"
            print "  # IMPLEMENTATION - What actually gets configured"
            print "  #============================================================================"
            print "  # TODO: Add config = lib.mkIf cfg.enable { ... };"
            print ""
            print "  #============================================================================"
            print "  # VALIDATION - Assertions and checks"
            print "  #============================================================================"
            print "  # TODO: Add assertions = [ ... ];"
            in_content = 1
        }
        print $0
    }
    printed_import == 0 { print $0 }
    ' "$filepath" > "$tmpfile"
    
    mv "$tmpfile" "$filepath"
}

# Main processing function
process_file() {
    local filepath="$1"
    
    echo "Processing: $filepath"
    
    # Check if file already has Charter v4 header
    if grep -q "# DEPENDENCIES (Upstream):" "$filepath" 2>/dev/null; then
        echo "  ✓ Already has Charter v4 header"
        return
    fi
    
    local tmpfile=$(mktemp)
    local header_created=false
    
    # Process the file line by line
    while IFS= read -r line; do
        # If we hit the imports line and haven't created header yet
        if [[ "$line" =~ ^{\ config,.*}:$ ]] && [ "$header_created" = false ]; then
            # Write the new header
            create_header "$filepath"
            echo
            echo "$line"
            header_created=true
        else
            echo "$line"
        fi
    done < "$filepath" > "$tmpfile"
    
    # If no imports line found, add header at the top
    if [ "$header_created" = false ]; then
        {
            create_header "$filepath"
            echo
            cat "$filepath"
        } > "$tmpfile"
    fi
    
    mv "$tmpfile" "$filepath"
    echo "  ✓ Updated header"
}

# Main execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <file1.nix> [file2.nix ...]"
    echo "   or: $0 --all  (to update all modules)"
    exit 1
fi

if [ "$1" = "--all" ]; then
    echo "🔄 Updating headers for all modules..."
    find domains/ -name "*.nix" -not -path "*/.*" | while read -r file; do
        process_file "$file"
    done
    echo "✅ All module headers updated!"
else
    for file in "$@"; do
        if [ -f "$file" ]; then
            process_file "$file"
        else
            echo "⚠️  File not found: $file"
        fi
    done
fi

echo
echo "📋 Next steps:"
echo "1. Review generated headers and fill in TODO items"
echo "2. Add proper section headers with: ./scripts/add-section-headers.sh --all"
echo "3. Run validation: ./scripts/validate-charter-v4.sh"