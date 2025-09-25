#!/usr/bin/env bash

# HWC Charter-compliant script for adding packages to domains/home/apps
# Usage: ./scripts/add-home-app.sh [package-name]

set -eo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory and repo root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Temporary files for cleanup
readonly TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

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

debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1" >&2
    fi
}

# Check if all required dependencies are available
check_dependencies() {
    local missing_deps=()
    
    for cmd in jq nix git; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please install these tools and try again"
        exit 1
    fi
}

# Convert package name to directory name (kebab-case)
to_kebab_case() {
    local input="$1"
    
    # Handle empty input
    if [[ -z "$input" ]]; then
        echo "unknown-app"
        return
    fi
    
    # Convert to lowercase, replace non-alphanumeric with hyphens, clean up
    echo "$input" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g' \
        | sed 's/--*/-/g' \
        | sed 's/^-\+\|-\+$//g' \
        | sed 's/^$/unknown-app/'
}

# Convert package name to camelCase for options
to_camel_case() {
    local input="$1"
    
    # Handle empty input
    if [[ -z "$input" ]]; then
        echo "unknownApp"
        return
    fi
    
    # Split on non-alphanumeric characters and convert to camelCase
    local words=()
    while IFS= read -r -d '' word; do
        [[ -n "$word" ]] && words+=("$word")
    done < <(echo "$input" | tr -c '[:alnum:]' '\0' | tr '[:upper:]' '[:lower:]')
    
    if [[ ${#words[@]} -eq 0 ]]; then
        echo "unknownApp"
        return
    fi
    
    local result="${words[0]}"
    for ((i=1; i<${#words[@]}; i++)); do
        local word="${words[i]}"
        if [[ -n "$word" ]]; then
            result="${result}$(tr '[:lower:]' '[:upper:]' <<< "${word:0:1}")${word:1}"
        fi
    done
    
    echo "$result"
}

# Search for packages using nix search with better error handling
search_packages() {
    local query="$1"
    local search_file="$TEMP_DIR/search_results.json"
    
    log "Searching for packages matching '$query'..." >&2
    
    # Save the query for later use in filtering
    echo "$query" > "$TEMP_DIR/search_query.txt"
    
    # Perform search with timeout and proper error handling
    if ! timeout 30 nix search nixpkgs "$query" --json 2>/dev/null > "$search_file"; then
        error "Failed to search packages. Check your query and network connection." >&2
        return 1
    fi
    
    # Verify the file exists and has content
    if [[ ! -s "$search_file" ]]; then
        error "No search results found for '$query'" >&2
        return 1
    fi
    
    # Validate JSON structure
    if ! jq empty "$search_file" 2>/dev/null; then
        error "Search returned invalid JSON" >&2
        debug "JSON content: $(head -n 5 "$search_file")" >&2
        return 1
    fi
    
    # Check if results are empty
    local result_count
    result_count=$(jq 'length' "$search_file" 2>/dev/null || echo "0")
    
    if [[ "$result_count" == "0" ]]; then
        error "No packages found matching '$query'" >&2
        return 1
    fi
    
    debug "Found $result_count potential matches" >&2
    echo "$search_file"
}

# Parse and format search results with robust error handling
format_search_results() {
    local search_file="$1"
    local formatted_file="$TEMP_DIR/formatted_results.jsonl"
    local query_file="$TEMP_DIR/search_query.txt"
    
    # Read the original query for intelligent filtering
    local original_query=""
    if [[ -f "$query_file" ]]; then
        original_query=$(cat "$query_file")
    fi
    
    # First, let's debug what we're working with
    debug "Raw search file content:" >&2
    if [[ "${DEBUG:-}" == "1" ]]; then
        head -n 3 "$search_file" >&2
    fi
    debug "Original query: '$original_query'" >&2
    
    # Try a simpler, more permissive jq filter first with intelligent filtering
    if ! jq -r --arg query "$original_query" '
        to_entries | 
        map(
            {
                key: .key,
                attr: (.key | split(".") | if length > 2 then .[2:] | join(".") else .[-1] end),
                pname: (.value.pname // .value.name // (.key | split(".") | last)),
                version: (.value.version // "unknown"),
                description: (.value.description // .value.meta.description // "No description available"),
                # Add scoring for relevance
                relevance_score: (
                    # Exact match gets highest score
                    if (.value.pname // .value.name // (.key | split(".") | last)) == $query then 100
                    # Main package variants get high score
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | test("^" + $query + "$") then 90
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | test("^" + $query + "-") then 80
                    # Avoid dictionaries, libs, and development packages for simple queries
                    elif (.value.description // "") | test("dictionary|dict|hyphen|thesaurus"; "i") then 20
                    elif (.key | split(".") | last) | test("Dicts|dicts|Dict") then 20
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | test("lib|dev|debug|unwrapped"; "i") then 30
                    # Main packages get medium-high score
                    else 50
                    end
                )
            } |
            select(.pname and .pname != "" and .pname != null)
        ) | 
        # Sort by relevance score (descending), then by name
        sort_by([-.relevance_score, .pname]) |
        # For common queries, only show top results to reduce noise
        if length > 20 and ($query | test("^(firefox|chrome|libreoffice|vscode|discord|slack|zoom)$")) then
            map(select(.relevance_score >= 40)) | .[0:10]
        else . end |
        .[] | 
        @json
    ' "$search_file" > "$formatted_file" 2>"$TEMP_DIR/jq_error.log"; then
        error "Failed to format search results" >&2
        debug "JQ error log:" >&2
        if [[ "${DEBUG:-}" == "1" ]] && [[ -f "$TEMP_DIR/jq_error.log" ]]; then
            cat "$TEMP_DIR/jq_error.log" >&2
        fi
        
        # Try an even more basic approach as fallback
        warn "Trying fallback formatting approach..." >&2
        if ! jq -r 'to_entries | .[] | @json' "$search_file" > "$formatted_file" 2>/dev/null; then
            error "Even basic JSON parsing failed - search results may be corrupted" >&2
            return 1
        fi
    fi
    
    # Verify we have results
    if [[ ! -s "$formatted_file" ]]; then
        error "No valid packages found after filtering" >&2
        debug "Search file size: $(wc -c < "$search_file") bytes" >&2
        debug "Formatted file size: $(wc -c < "$formatted_file") bytes" >&2
        return 1
    fi
    
    local result_count
    result_count=$(wc -l < "$formatted_file")
    debug "Formatted $result_count packages" >&2
    
    # Show a hint about what was filtered for common queries
    if [[ "$result_count" -lt 20 && "$original_query" =~ ^(firefox|chrome|libreoffice|vscode|discord|slack|zoom)$ ]]; then
        log "Showing top results for '$original_query' (filtered out dictionaries and dev packages)" >&2
    fi
    
    echo "$formatted_file"
}

# Display search results and let user choose - writes selection to a file
select_package() {
    local results_file="$1"
    local output_file="$2"
    local -a packages=()
    local i=1
    
    debug "Starting package selection from file: $results_file" >&2
    debug "Will write selection to: $output_file" >&2
    debug "File size: $(wc -c < "$results_file") bytes" >&2
    debug "File contents:" >&2
    if [[ "${DEBUG:-}" == "1" ]]; then
        cat "$results_file" >&2
    fi
    
    log "Found packages:"
    echo
    
    # Read packages into array with validation
    while IFS= read -r line; do
        debug "Processing line: $line" >&2
        if [[ -n "$line" ]] && jq empty <<< "$line" 2>/dev/null; then
            packages+=("$line")
            
            # Extract and display package info safely - handle both formats
            local pname version description attr key
            
            # Try to extract from the formatted structure first
            pname=$(jq -r '.pname // empty' <<< "$line" 2>/dev/null || echo "")
            version=$(jq -r '.version // "unknown"' <<< "$line" 2>/dev/null || echo "unknown")
            description=$(jq -r '.description // empty' <<< "$line" 2>/dev/null || echo "")
            attr=$(jq -r '.attr // empty' <<< "$line" 2>/dev/null || echo "")
            key=$(jq -r '.key // empty' <<< "$line" 2>/dev/null || echo "")
            
            # Fallback to raw search result format if needed
            if [[ -z "$pname" ]]; then
                debug "Trying raw search result format extraction" >&2
                pname=$(jq -r '.value.pname // .value.name // empty' <<< "$line" 2>/dev/null || echo "")
                version=$(jq -r '.value.version // "unknown"' <<< "$line" 2>/dev/null || echo "unknown")
                description=$(jq -r '.value.description // .value.meta.description // "No description available"' <<< "$line" 2>/dev/null || echo "No description available")
                attr=$(jq -r '.key | split(".") | if length > 1 then .[1:] | join(".") else . end' <<< "$line" 2>/dev/null || echo "")
                key=$(jq -r '.key // empty' <<< "$line" 2>/dev/null || echo "")
            fi
            
            # Use fallbacks for missing info
            [[ -z "$pname" ]] && pname="unknown"
            [[ -z "$version" ]] && version="unknown"
            [[ -z "$description" ]] && description="No description available"
            [[ -z "$attr" ]] && attr="${key##*.}"
            
            debug "Extracted - pname: '$pname', version: '$version', attr: '$attr'" >&2
            
            printf "%2d) %s (%s)\n" "$i" "$pname" "$version"
            printf "    %s\n" "$description"
            printf "    Attribute: %s\n" "$attr"
            echo
            ((i++))
        else
            debug "Skipping invalid JSON line: $line" >&2
        fi
    done < "$results_file"
    
    debug "Total packages processed: ${#packages[@]}" >&2
    debug "About to show selection prompt" >&2
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        error "No valid packages available for selection"
        return 1
    fi
    
    # Get user selection with validation
    local choice
    while true; do
        printf "Select package number (1-${#packages[@]}), or 'q' to quit: "
        read -r choice
        
        debug "User entered: '$choice'" >&2
        
        case "$choice" in
            [qQ])
                log "Cancelled by user"
                exit 0
                ;;
            ''|*[!0-9]*)
                warn "Please enter a valid number or 'q' to quit"
                continue
                ;;
            *)
                if [[ "$choice" -ge 1 && "$choice" -le ${#packages[@]} ]]; then
                    debug "Valid selection: $choice" >&2
                    break
                else
                    warn "Please enter a number between 1 and ${#packages[@]}"
                    continue
                fi
                ;;
        esac
    done
    
    local selected="${packages[$((choice-1))]}"
    debug "Selected package: $selected" >&2
    
    # Write selection to output file
    echo "$selected" > "$output_file"
    debug "Wrote selection to $output_file" >&2
}

# Extract package information with validation from a JSON string
extract_package_info() {
    local package_json="$1"
    local attr_var="$2"
    local pname_var="$3"
    local version_var="$4"
    local description_var="$5"
    
    debug "Extracting info from: $package_json" >&2
    
    local attr pname version description
    
    # Try formatted structure first
    attr=$(jq -r '.attr // empty' <<< "$package_json" 2>/dev/null || echo "")
    pname=$(jq -r '.pname // empty' <<< "$package_json" 2>/dev/null || echo "")
    version=$(jq -r '.version // "unknown"' <<< "$package_json" 2>/dev/null || echo "unknown")
    description=$(jq -r '.description // empty' <<< "$package_json" 2>/dev/null || echo "")
    
    # If that didn't work, try raw search result format
    if [[ -z "$attr" || -z "$pname" ]]; then
        debug "Trying raw search result format extraction" >&2
        local key
        key=$(jq -r '.key // empty' <<< "$package_json" 2>/dev/null || echo "")
        pname=$(jq -r '.value.pname // .value.name // empty' <<< "$package_json" 2>/dev/null || echo "")
        version=$(jq -r '.value.version // "unknown"' <<< "$package_json" 2>/dev/null || echo "unknown")
        description=$(jq -r '.value.description // .value.meta.description // "No description available"' <<< "$package_json" 2>/dev/null || echo "No description available")
        
        # Extract attribute from key
        if [[ -n "$key" ]]; then
            # For keys like "legacyPackages.x86_64-linux.proton-authenticator", extract just "proton-authenticator"
            attr=$(jq -r 'split(".") | if length > 2 then .[2:] | join(".") else .[-1] end' <<< "\"$key\"" 2>/dev/null || echo "")
        fi
    fi
    
    # Final fallbacks and validation
    [[ -z "$version" ]] && version="unknown"
    [[ -z "$description" ]] && description="No description available"
    
    # Validate required fields
    if [[ -z "$attr" || -z "$pname" ]]; then
        error "Failed to extract required package information" >&2
        debug "Extracted attr: '$attr'" >&2
        debug "Extracted pname: '$pname'" >&2
        debug "Package JSON: $package_json" >&2
        return 1
    fi
    
    # Validate that attr is a proper nixpkgs attribute
    if [[ ! "$attr" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error "Invalid package attribute: $attr" >&2
        return 1
    fi
    
    debug "Successfully extracted package info:" >&2
    debug "  attr: $attr" >&2
    debug "  pname: $pname" >&2
    debug "  version: $version" >&2
    debug "  description: $description" >&2
    
    # Use printf to assign to the variable names passed as parameters
    printf -v "$attr_var" '%s' "$attr"
    printf -v "$pname_var" '%s' "$pname"
    printf -v "$version_var" '%s' "$version"
    printf -v "$description_var" '%s' "$description"
    
    return 0
}

# Generate options.nix file with validation
generate_options_nix() {
    local option_name="$1"
    local description="$2"
    local output_file="$3"
    
    # Validate inputs
    if [[ -z "$option_name" || -z "$output_file" ]]; then
        error "Missing required parameters for options.nix generation"
        return 1
    fi
    
    # Escape description for Nix string
    local escaped_description
    escaped_description=$(printf '%s' "$description" | sed 's/"/\\"/g')
    
    cat > "$output_file" << EOF
{ lib, ... }:

{
  options.hwc.home.apps.$option_name = {
    enable = lib.mkEnableOption "$escaped_description";
  };
}
EOF
    
    # Verify file was created successfully
    if [[ ! -s "$output_file" ]]; then
        error "Failed to create options.nix file"
        return 1
    fi
    
    # Validate Nix syntax
    if ! nix-instantiate --parse "$output_file" >/dev/null 2>&1; then
        error "Generated options.nix has invalid Nix syntax"
        return 1
    fi
    
    debug "Generated valid options.nix file"
}

# Generate index.nix file with validation
generate_index_nix() {
    local option_name="$1"
    local package_attr="$2"
    local output_file="$3"
    
    # Validate inputs
    if [[ -z "$option_name" || -z "$package_attr" || -z "$output_file" ]]; then
        error "Missing required parameters for index.nix generation"
        return 1
    fi
    
    cat > "$output_file" << EOF
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
    
    # Verify file was created successfully
    if [[ ! -s "$output_file" ]]; then
        error "Failed to create index.nix file"
        return 1
    fi
    
    # Validate Nix syntax
    if ! nix-instantiate --parse "$output_file" >/dev/null 2>&1; then
        error "Generated index.nix has invalid Nix syntax"
        return 1
    fi
    
    debug "Generated valid index.nix file"
}

# Add import to home.nix profile with better error handling
add_to_home_profile() {
    local option_name="$1"
    local dir_name="$2"
    local home_profile="$REPO_ROOT/profiles/home.nix"
    
    # Validate inputs
    if [[ -z "$option_name" ]]; then
        error "Missing option name for home profile update"
        return 1
    fi
    
    # Check if home profile exists
    if [[ ! -f "$home_profile" ]]; then
        error "Home profile not found at $home_profile"
        return 1
    fi
    
    # Check if already added
    if grep -q "hwc\.home\.apps\.$option_name\.enable" "$home_profile"; then
        warn "Package already enabled in home profile"
        return 0
    fi
    
    # Create backup
    local backup_file="$home_profile.backup.$(date +%s)"
    cp "$home_profile" "$backup_file"
    debug "Created backup at $backup_file"
    
    # NOTE: Import functionality commented out since user auto-imports all index.nix files
    # # Add import first - find the imports section
    # local import_added=false
    # if grep -q "imports = \[" "$home_profile"; then
    #     # Check if import already exists
    #     if ! grep -q "../../domains/home/apps/$dir_name" "$home_profile"; then
    #         # Find the imports section and add our import
    #         local imports_end_line
    #         imports_end_line=$(grep -n "imports = \[" "$home_profile" | head -1 | cut -d: -f1)
    #         if [[ -n "$imports_end_line" ]]; then
    #             sed -i "${imports_end_line}a\\    ../../domains/home/apps/$dir_name" "$home_profile"
    #             import_added=true
    #             debug "Added import for $dir_name to imports section"
    #         fi
    #     else
    #         import_added=true
    #         debug "Import for $dir_name already exists"
    #     fi
    # fi
    # 
    # if [[ "$import_added" != "true" ]]; then
    #     error "Failed to add import to home profile - could not find or modify imports section"
    #     cp "$backup_file" "$home_profile"
    #     return 1
    # fi
    
    # Look for a flag comment to insert new apps, or find the last hwc.home.apps entry
    local insertion_line
    if grep -q "# INSERT_NEW_APPS_HERE" "$home_profile"; then
        # Use the flag if it exists
        insertion_line=$(grep -n "# INSERT_NEW_APPS_HERE" "$home_profile" | head -1 | cut -d: -f1)
        debug "Found INSERT_NEW_APPS_HERE flag at line $insertion_line"
    else
        # Fall back to finding the last hwc.home.apps entry within the users.eric block
        # First find the users.eric block start
        local eric_start
        eric_start=$(grep -n "users\.eric = {" "$home_profile" | head -1 | cut -d: -f1)
        
        if [[ -n "$eric_start" ]]; then
            # Find the last hwc.home.apps line after the users.eric block starts
            insertion_line=$(sed -n "${eric_start},\$p" "$home_profile" | grep -n "hwc\.home\.apps\." | tail -1 | cut -d: -f1)
            if [[ -n "$insertion_line" ]]; then
                # Adjust line number to be relative to the whole file
                insertion_line=$((eric_start + insertion_line - 1))
                debug "Found last app entry in users.eric block at line $insertion_line"
            fi
        fi
    fi
    
    if [[ -z "$insertion_line" ]]; then
        error "Could not find insertion point for new app entry"
        cp "$backup_file" "$home_profile"
        return 1
    fi
    
    # Insert the new app entry with proper indentation
    sed -i "${insertion_line}a\\      hwc.home.apps.$option_name.enable = true;" "$home_profile"
    
    # Validate the modification
    if ! grep -q "hwc\.home\.apps\.$option_name\.enable" "$home_profile"; then
        error "Failed to add entry to home profile"
        # Restore backup
        cp "$backup_file" "$home_profile"
        return 1
    fi
    
    # Validate Nix syntax of modified file
    if ! nix-instantiate --parse "$home_profile" >/dev/null 2>&1; then
        error "Modified home profile has invalid Nix syntax"
        # Restore backup
        cp "$backup_file" "$home_profile"
        return 1
    fi
    
    success "Added hwc.home.apps.$option_name.enable = true to home profile"
    rm -f "$backup_file"
}

# Test that the package exists and is accessible
test_package_availability() {
    local package_attr="$1"
    
    log "Verifying package availability..."
    
    # Test if package can be evaluated
    if ! nix eval "nixpkgs#$package_attr.pname" --raw >/dev/null 2>&1; then
        error "Package '$package_attr' is not available or has evaluation errors"
        return 1
    fi
    
    debug "Package '$package_attr' is available"
    return 0
}

# Enhanced build test with better feedback
test_build() {
    local build_target="${1:-hwc-laptop}"
    
    log "Testing build configuration..."
    
    # First, try a dry run
    if ! nix flake check ".#$build_target" --no-build 2>/dev/null; then
        warn "Flake check failed, attempting build anyway..."
    fi
    
    # Attempt the build (nixos-rebuild build doesn't support --no-link)
    if sudo nixos-rebuild build --flake ".#$build_target"; then
        success "Build test passed!"
        return 0
    else
        error "Build test failed!"
        warn "The configuration may have syntax errors or missing dependencies"
        warn "Check the build output above for specific errors"
        return 1
    fi
}

# Enhanced commit with better error handling
commit_changes() {
    local package_name="$1"
    local package_attr="$2"
    local package_version="$3"
    local package_description="$4"
    local dir_name="$5"
    local option_name="$6"
    
    log "Staging changes for commit..."
    
    # Check git status
    if ! git status --porcelain | grep -q .; then
        warn "No changes to commit"
        return 0
    fi
    
    # Add files with validation
    if ! git add "domains/home/apps/$dir_name/" "profiles/home.nix"; then
        error "Failed to stage files for commit"
        return 1
    fi
    
    # Create commit message
    local commit_msg="Add $package_name app module

- Create domains/home/apps/$dir_name structure following HWC Charter
- Add options.nix with hwc.home.apps.$option_name namespace
- Add index.nix aggregator with home.packages implementation
- Enable in home.nix profile

Package: $package_attr ($package_version)
Description: $package_description

🤖 Generated with add-home-app.sh script

Co-Authored-By: Claude <noreply@anthropic.com>"
    
    # Commit changes
    if git commit -m "$commit_msg"; then
        success "Committed changes to git"
        return 0
    else
        error "Failed to commit changes"
        return 1
    fi
}

# Main script logic with comprehensive error handling
main() {
    local package_query="${1:-}"
    
    # Change to repo root
    cd "$REPO_ROOT" || {
        error "Failed to change to repo root: $REPO_ROOT"
        exit 1
    }
    
    log "HWC Charter-compliant package installer"
    log "Repository: $REPO_ROOT"
    echo
    
    # Get package query if not provided
    if [[ -z "$package_query" ]]; then
        echo -n "Enter package name to search for: "
        read -r package_query
    fi
    
    if [[ -z "$package_query" ]]; then
        error "Package name cannot be empty"
        exit 1
    fi
    
    # Search for packages
    local search_file
    debug "About to search for packages..." >&2
    if ! search_file=$(search_packages "$package_query"); then
        exit 1
    fi
    debug "Search completed, file: $search_file" >&2
    
    # Format search results
    local results_file
    debug "About to format search results..." >&2
    if ! results_file=$(format_search_results "$search_file"); then
        exit 1
    fi
    debug "Formatting completed, file: $results_file" >&2
    
    # Let user select package - write to temp file to avoid subshell issues
    local selection_file="$TEMP_DIR/selected_package.json"
    debug "About to call select_package..." >&2
    if ! select_package "$results_file" "$selection_file"; then
        exit 1
    fi
    debug "Package selection completed" >&2
    
    # Read the selected package from file
    local selected_package
    selected_package=$(cat "$selection_file")
    debug "Selected package content: $selected_package" >&2
    
    # Extract package information using separate variables
    local package_attr package_name package_version package_description
    if ! extract_package_info "$selected_package" package_attr package_name package_version package_description; then
        exit 1
    fi
    
    log "Selected: $package_name ($package_version)"
    log "Description: $package_description"
    log "Attribute: $package_attr"
    echo
    
    # Test package availability
    if ! test_package_availability "$package_attr"; then
        exit 1
    fi
    
    # Confirm selection
    local confirm
    echo -n "Proceed with adding this package? (y/N): "
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log "Cancelled by user"
        exit 0
    fi
    
    # Generate names with validation
    local dir_name option_name
    dir_name=$(to_kebab_case "$package_name")
    option_name=$(to_camel_case "$package_name")
    
    if [[ -z "$dir_name" || -z "$option_name" ]]; then
        error "Failed to generate valid directory or option names"
        exit 1
    fi
    
    local app_dir="$REPO_ROOT/domains/home/apps/$dir_name"
    
    log "Creating module structure..."
    log "Directory: domains/home/apps/$dir_name"
    log "Option: hwc.home.apps.$option_name"
    echo
    
    # Check if directory already exists
    if [[ -d "$app_dir" ]]; then
        error "Directory already exists: $app_dir"
        error "Package may already be configured"
        exit 1
    fi
    
    # Create directory structure
    if ! mkdir -p "$app_dir"; then
        error "Failed to create directory: $app_dir"
        exit 1
    fi
    
    # Generate module files
    if ! generate_options_nix "$option_name" "$package_description" "$app_dir/options.nix"; then
        error "Failed to generate options.nix"
        exit 1
    fi
    
    if ! generate_index_nix "$option_name" "$package_attr" "$app_dir/index.nix"; then
        error "Failed to generate index.nix"
        exit 1
    fi
    
    success "Created Charter-compliant module files"
    
    # Add to home profile
    if ! add_to_home_profile "$option_name" "$dir_name"; then
        error "Failed to update home profile"
        exit 1
    fi
    
    # Commit changes BEFORE testing build (flake needs committed files)
    if ! commit_changes "$package_name" "$package_attr" "$package_version" "$package_description" "$dir_name" "$option_name"; then
        warn "Failed to commit changes"
        # Don't exit here, still try the build
    fi
    
    # Test the build AFTER committing
    if ! test_build "hwc-laptop"; then
        error "Build test failed - the committed changes have issues"
        warn "You may need to manually fix the configuration or revert the commit"
        exit 1
    fi
    
    echo
    success "Package '$package_name' successfully added to HWC configuration!"
    log "Location: domains/home/apps/$dir_name"
    log "Option: hwc.home.apps.$option_name.enable"
    log "Status: Enabled in profiles/home.nix"
    echo
    log "To apply changes, run: sudo nixos-rebuild switch --flake '.#hwc-laptop'"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check dependencies first
    check_dependencies
    
    # Run main function with all arguments
    main "$@"
fi
