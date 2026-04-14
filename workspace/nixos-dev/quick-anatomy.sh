#!/usr/bin/env bash

# Quick Module Anatomy Fixes
# Targets the specific issues from linter output

# Remove strict error handling to debug issues
# set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE"
fi

FIXED_COUNT=0

# Files that need options.nix imports added
missing_imports=(
    "domains/home/mail/accounts/index.nix"
    "domains/home/mail/abook/index.nix"
    "domains/home/environment/shell/index.nix"
    "domains/home/theme/fonts/index.nix"
    "domains/server/containers/immich/index.nix"
    "domains/server/containers/qbittorrent/index.nix"
    "domains/server/containers/navidrome/index.nix"
    "domains/server/containers/radarr/index.nix"
    "domains/server/containers/prowlarr/index.nix"
    "domains/server/containers/sabnzbd/index.nix"
    "domains/server/containers/sonarr/index.nix"
    "domains/server/containers/slskd/index.nix"
    "domains/server/containers/jellyfin/index.nix"
    "domains/server/containers/lidarr/index.nix"
    "domains/server/containers/soularr/index.nix"
    "domains/server/containers/gluetun/index.nix"
    "domains/server/containers/caddy/index.nix"
    "domains/system/core/filesystem/index.nix"
    "domains/system/services/vpn/index.nix"
)

# Files that need section headers
missing_headers=(
    "domains/home/mail/accounts/index.nix"
    "domains/home/apps/chromium/index.nix"
    "domains/home/apps/thunar/index.nix"
    "domains/home/apps/librewolf/index.nix"
    "domains/home/environment/shell/index.nix"
    "domains/system/services/vpn/index.nix"
)

# Fix missing options.nix imports
fix_missing_import() {
    local file="$1"
    echo "Adding options.nix import to: $file"
    
    # Check if options.nix exists in the same directory
    local dir=$(dirname "$file")
    if [[ ! -f "$dir/options.nix" ]]; then
        echo "  ERROR: $dir/options.nix does not exist, skipping"
        return 1
    fi
    
    # Check if already has the import
    if grep -q "options\.nix" "$file"; then
        echo "  Already has options.nix import"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would add ./options.nix to imports"
        return 0
    fi
    
    # Backup
    cp "$file" "$file.backup"
    
    # Add import using a more robust approach
    if grep -q "imports.*\[" "$file"; then
        # Multi-line imports array exists
        sed -i '/imports = \[/a\    ./options.nix' "$file"
    elif grep -q "imports.*=" "$file"; then
        # Single import line - convert to array
        sed -i 's/imports = \(.*\);/imports = [\n    .\/options.nix\n    \1\n  ];/' "$file"
    else
        # No imports at all - add after opening brace
        sed -i '/{/a\  imports = [ ./options.nix ];\n' "$file"
    fi
    
    echo "  Added import"
    ((FIXED_COUNT++))
    return 0
}

# Fix missing section headers
fix_missing_headers() {
    local file="$1"
    echo "Adding section headers to: $file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would add section headers"
        return 0
    fi
    
    # Backup
    cp "$file" "$file.backup"
    
    local tmp_file=$(mktemp)
    local added_options=false
    local added_implementation=false
    
    while IFS= read -r line; do
        # Add OPTIONS header before imports
        if [[ "$line" =~ ^[[:space:]]*imports ]] && [[ "$added_options" == "false" ]]; then
            echo "  #=========================================================================="
            echo "  # OPTIONS"
            echo "  #=========================================================================="
            added_options=true
        fi
        
        # Add IMPLEMENTATION header before config
        if [[ "$line" =~ ^[[:space:]]*config ]] && [[ "$added_implementation" == "false" ]]; then
            echo ""
            echo "  #=========================================================================="
            echo "  # IMPLEMENTATION"
            echo "  #=========================================================================="
            added_implementation=true
        fi
        
        echo "$line"
    done < "$file" > "$tmp_file"
    
    # Add VALIDATION at the end
    if [[ "$added_options" == "true" || "$added_implementation" == "true" ]]; then
        # Remove last } and add validation section
        head -n -1 "$tmp_file" > "${tmp_file}.new"
        cat >> "${tmp_file}.new" << 'EOF'

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here

}
EOF
        mv "${tmp_file}.new" "$tmp_file"
    fi
    
    mv "$tmp_file" "$file"
    echo "  Added section headers"
    ((FIXED_COUNT++))
}

# Create missing options.nix files
create_missing_options() {
    local dirs_needing_options=(
        "domains/home/mail/abook"
        "domains/home/mail/accounts"
        "domains/server/containers/immich"
        "domains/server/containers/qbittorrent"
        "domains/server/containers/navidrome"
        "domains/server/containers/radarr"
        "domains/server/containers/prowlarr"
        "domains/server/containers/sabnzbd"
        "domains/server/containers/sonarr"
        "domains/server/containers/slskd"
        "domains/server/containers/jellyfin"
        "domains/server/containers/lidarr"
        "domains/server/containers/soularr"
        "domains/server/containers/gluetun"
        "domains/server/containers/caddy"
        "domains/system/core/filesystem"
    )
    
    for dir in "${dirs_needing_options[@]}"; do
        local options_file="$dir/options.nix"
        
        if [[ -f "$options_file" ]]; then
            continue
        fi
        
        echo "Creating missing: $options_file"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would create options.nix"
            continue
        fi
        
        # Generate namespace from directory path
        local namespace="hwc"
        IFS='/' read -ra path_parts <<< "$dir"
        for ((i=1; i<${#path_parts[@]}; i++)); do
            namespace="${namespace}.${path_parts[i]}"
        done
        
        # Create the options.nix file
        cat > "$options_file" << EOF
{ lib, ... }:

{
  options.$namespace = {
    enable = lib.mkEnableOption "${path_parts[-1]} functionality";
  };
}
EOF
        
        echo "  Created options.nix with namespace: $namespace"
        ((FIXED_COUNT++))
    done
}

# Main execution
echo "Quick Module Anatomy Fixes"
echo "=========================="

# Create missing options.nix files first
echo "Creating missing options.nix files..."
create_missing_options || echo "Error in create_missing_options, continuing..."

echo
echo "Fixing missing imports..."
for file in "${missing_imports[@]}"; do
    if [[ -f "$file" ]]; then
        fix_missing_import "$file" || echo "Error processing $file, continuing..."
    else
        echo "File not found: $file"
    fi
done

echo
echo "Fixing missing headers..."
for file in "${missing_headers[@]}"; do
    if [[ -f "$file" ]]; then
        fix_missing_headers "$file" || echo "Error processing $file, continuing..."
    else
        echo "File not found: $file"
    fi
done

echo
echo "Summary: $FIXED_COUNT fixes applied"

if [[ $FIXED_COUNT -gt 0 && "$DRY_RUN" == "false" ]]; then
    echo
    echo "Next steps:"
    echo "1. Test: nixos-rebuild dry-run"
    echo "2. Run linter to see progress"
fi
