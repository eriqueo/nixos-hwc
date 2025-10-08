#!/usr/bin/env bash

# Simple Section Header Addition Script
# Adds Charter v5 section headers to index.nix files

set -euo pipefail

DRY_RUN=false
TOTAL_PROCESSED=0
TOTAL_MODIFIED=0

# Parse arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE - No files will be modified"
fi

# Check if file already has section headers
has_headers() {
    local file="$1"
    grep -qE "#\s*(OPTIONS|IMPLEMENTATION|VALIDATION)" "$file" 2>/dev/null
}

# Add section headers to a file
add_headers() {
    local file="$1"
    local relative_path="${file#$(pwd)/}"
    
    echo "Processing: $relative_path"
    ((TOTAL_PROCESSED++))
    
    if has_headers "$file"; then
        echo "  Already has headers"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would add section headers"
        return 0
    fi
    
    # Create backup
    cp "$file" "${file}.backup" || {
        echo "  ERROR: Could not create backup"
        return 1
    }
    
    # Simple approach: add headers based on content patterns
    local tmp_file=$(mktemp)
    local added_options=false
    local added_implementation=false
    
    # Process line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Add OPTIONS header before imports or options
        if [[ "$line" =~ ^[[:space:]]*imports ]] && [[ "$added_options" == "false" ]]; then
            echo "  #=========================================================================="
            echo "  # OPTIONS"
            echo "  #=========================================================================="
            added_options=true
        fi
        
        # Add IMPLEMENTATION header before config
        if [[ "$line" =~ ^[[:space:]]*config ]] && [[ "$added_implementation" == "false" ]]; then
            if [[ "$added_options" == "true" ]]; then
                echo ""
            fi
            echo "  #=========================================================================="
            echo "  # IMPLEMENTATION"
            echo "  #=========================================================================="
            added_implementation=true
        fi
        
        echo "$line"
        
    done < "$file" > "$tmp_file"
    
    # Add VALIDATION section at end if we modified the file
    if [[ "$added_options" == "true" || "$added_implementation" == "true" ]]; then
        # Remove the last "}" and add VALIDATION section
        if head -n -1 "$tmp_file" > "${tmp_file}.tmp" 2>/dev/null; then
            {
                cat "${tmp_file}.tmp"
                echo ""
                echo "  #=========================================================================="
                echo "  # VALIDATION"
                echo "  #=========================================================================="
                echo "  # Add assertions and validation logic here"
                echo "}"
            } > "$tmp_file"
            rm -f "${tmp_file}.tmp"
        fi
    fi
    
    # Verify syntax before applying
    if nix-instantiate --parse "$tmp_file" >/dev/null 2>&1; then
        mv "$tmp_file" "$file"
        echo "  Added section headers"
        ((TOTAL_MODIFIED++))
    else
        echo "  ERROR: Would create invalid syntax, skipping"
        rm -f "$tmp_file"
        # Restore from backup
        mv "${file}.backup" "$file"
        return 1
    fi
    
    rm -f "${file}.backup"
    return 0
}

# Main execution
echo "Charter v5 Section Header Addition"
echo "=================================="

# Find all index.nix files
mapfile -t files < <(find domains/ -name "index.nix" -type f)

echo "Found ${#files[@]} index.nix files"
echo

# Process each file
for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        if ! add_headers "$file"; then
            echo "  Continuing with next file..."
        fi
    else
        echo "ERROR: File not found: $file"
    fi
done

echo
echo "Summary:"
echo "  Files processed: $TOTAL_PROCESSED"
echo "  Files modified: $TOTAL_MODIFIED"

if [[ $TOTAL_MODIFIED -gt 0 && "$DRY_RUN" == "false" ]]; then
    echo
    echo "Next steps:"
    echo "  1. Review changes: git diff"
    echo "  2. Test: nixos-rebuild dry-run"
    echo "  3. Run linter: ./scripts/lints/charter-lint.sh"
fi
