#!/usr/bin/env bash

# HWC Charter-compliant script for adding packages to domains/home/apps
# Usage: ./scripts/add-home-app.sh [package-name]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log() {
    echo -e "${BLUE}[HWC]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Convert package name to directory name (kebab-case)
to_kebab_case() {
    echo "$1" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-\|-$//g'
}

# Convert package name to camelCase for options
to_camel_case() {
    local input="$1"
    # Remove non-alphanumeric characters and convert to words
    local words=($(echo "$input" | sed 's/[^a-zA-Z0-9]/ /g' | tr '[:upper:]' '[:lower:]'))
    
    if [ ${#words[@]} -eq 0 ]; then
        echo "app"
        return
    fi
    
    # First word lowercase, rest capitalized
    local result="${words[0]}"
    for ((i=1; i<${#words[@]}; i++)); do
        local word="${words[i]}"
        result="${result}$(echo "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}"
    done
    
    echo "$result"
}

# Search for packages using nix search
search_packages() {
    local query="$1"
    log "Searching for packages matching '$query'..."
    
    # Use nix search to find packages
    local search_results
    search_results=$(nix search nixpkgs "$query" --json 2>/dev/null | jq -r '
        to_entries | 
        map(select(.value.pname != null)) |
        map({
            attr: (.key | split(".") | .[1:] | join(".")),
            pname: .value.pname,
            version: .value.version // "unknown",
            description: .value.description // "No description available"
        }) |
        sort_by(.pname) |
        .[]
    ' 2>/dev/null) || {
        error "Failed to search packages. Make sure 'jq' is installed and nix search is working."
        return 1
    }
    
    if [ -z "$search_results" ]; then
        error "No packages found matching '$query'"
        return 1
    fi
    
    echo "$search_results"
}

# Display search results and let user choose
select_package() {
    local search_results="$1"
    
    log "Found packages:"
    echo
    
    local -a packages=()
    local i=1
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local attr=$(echo "$line" | jq -r '.attr')
            local pname=$(echo "$line" | jq -r '.pname')
            local version=$(echo "$line" | jq -r '.version')
            local description=$(echo "$line" | jq -r '.description')
            
            packages+=("$line")
            printf "%2d) %s (%s) - %s\n" "$i" "$pname" "$version" "$description"
            printf "    Attribute: %s\n" "$attr"
            echo
            ((i++))
        fi
    done <<< "$search_results"
    
    if [ ${#packages[@]} -eq 0 ]; then
        error "No valid packages found"
        return 1
    fi
    
    echo -n "Select package number (1-${#packages[@]}), or 'q' to quit: "
    read -r choice
    
    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
        log "Cancelled by user"
        exit 0
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#packages[@]} ]; then
        error "Invalid selection"
        return 1
    fi
    
    echo "${packages[$((choice-1))]}"
}

# Generate options.nix file
generate_options_nix() {
    local option_name="$1"
    local description="$2"
    
    cat > "$3" << EOF
{ lib, ... }:

{
  options.hwc.home.apps.$option_name = {
    enable = lib.mkEnableOption "$description";
  };
}
EOF
}

# Generate index.nix file
generate_index_nix() {
    local option_name="$1"
    local package_attr="$2"
    
    cat > "$3" << EOF
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.$option_name;
in
{
  #==========================================================================
  # OPTIONS 
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      $package_attr
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}
EOF
}

# Add import to home.nix profile
add_to_home_profile() {
    local option_name="$1"
    local home_profile="$REPO_ROOT/profiles/home.nix"
    
    if [ ! -f "$home_profile" ]; then
        error "Home profile not found at $home_profile"
        return 1
    fi
    
    # Check if already added
    if grep -q "hwc\.home\.apps\.$option_name\.enable" "$home_profile"; then
        warn "Package already enabled in home profile"
        return 0
    fi
    
    # Find the line with the last hwc.home.apps entry
    local last_app_line
    last_app_line=$(grep -n "hwc\.home\.apps\." "$home_profile" | tail -1 | cut -d: -f1)
    
    if [ -z "$last_app_line" ]; then
        error "Could not find existing app entries in home profile"
        return 1
    fi
    
    # Add the new entry after the last app entry
    sed -i "${last_app_line}a\\      hwc.home.apps.$option_name.enable = true;" "$home_profile"
    
    success "Added hwc.home.apps.$option_name.enable = true to home profile"
}

# Main script
main() {
    cd "$REPO_ROOT"
    
    log "HWC Charter-compliant package installer"
    echo
    
    local package_query="$1"
    
    if [ -z "$package_query" ]; then
        echo -n "Enter package name to search for: "
        read -r package_query
    fi
    
    if [ -z "$package_query" ]; then
        error "Package name cannot be empty"
        exit 1
    fi
    
    # Search for packages
    local search_results
    search_results=$(search_packages "$package_query") || exit 1
    
    # Let user select package
    local selected_package
    selected_package=$(select_package "$search_results") || exit 1
    
    # Extract package information
    local package_attr=$(echo "$selected_package" | jq -r '.attr')
    local package_name=$(echo "$selected_package" | jq -r '.pname')
    local package_version=$(echo "$selected_package" | jq -r '.version')
    local package_description=$(echo "$selected_package" | jq -r '.description')
    
    log "Selected: $package_name ($package_version)"
    log "Description: $package_description"
    log "Attribute: $package_attr"
    echo
    
    # Confirm selection
    echo -n "Proceed with adding this package? (y/N): "
    read -r confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "Cancelled by user"
        exit 0
    fi
    
    # Generate names
    local dir_name=$(to_kebab_case "$package_name")
    local option_name=$(to_camel_case "$package_name")
    local app_dir="$REPO_ROOT/domains/home/apps/$dir_name"
    
    log "Creating module structure..."
    log "Directory: domains/home/apps/$dir_name"
    log "Option: hwc.home.apps.$option_name"
    echo
    
    # Create directory structure
    if [ -d "$app_dir" ]; then
        error "Directory already exists: $app_dir"
        exit 1
    fi
    
    mkdir -p "$app_dir"
    
    # Generate files
    generate_options_nix "$option_name" "$package_description" "$app_dir/options.nix"
    generate_index_nix "$option_name" "$package_attr" "$app_dir/index.nix"
    
    success "Created Charter-compliant module files"
    
    # Add to home profile
    add_to_home_profile "$option_name"
    
    # Git operations
    log "Committing changes..."
    git add "domains/home/apps/$dir_name/" "profiles/home.nix"
    git commit -m "Add $package_name app module

- Create domains/home/apps/$dir_name structure following HWC Charter
- Add options.nix with hwc.home.apps.$option_name namespace
- Add index.nix aggregator with home.packages implementation
- Enable in home.nix profile

Package: $package_attr ($package_version)
Description: $package_description

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
    
    success "Committed changes to git"
    
    # Test build
    log "Testing build..."
    if sudo nixos-rebuild build --flake ".#hwc-laptop"; then
        success "Build test passed!"
        echo
        success "Package '$package_name' successfully added to HWC configuration!"
        log "Location: domains/home/apps/$dir_name"
        log "Option: hwc.home.apps.$option_name.enable"
        log "Status: Enabled in profiles/home.nix"
    else
        error "Build test failed!"
        warn "You may need to manually fix the configuration"
        exit 1
    fi
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed"
    exit 1
fi

if ! command -v nix &> /dev/null; then
    error "nix is required but not installed"
    exit 1
fi

# Run main function
main "${1:-}"