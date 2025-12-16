#!/usr/bin/env bash

# HWC Charter-compliant script for adding packages to domains/home/apps
# Version: 2.0 - Complete rewrite with enhanced features
# Usage: ./scripts/add-home-app.sh [OPTIONS] [package-name]

set -eo pipefail

#==============================================================================
# CONFIGURATION & CONSTANTS
#==============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script version
readonly VERSION="2.1.0"

#==============================================================================
# ENVIRONMENT SETUP
#==============================================================================

# Script directory (resolve symlinks) and repo root (robust)
get_script_dir() {
  local src="${BASH_SOURCE[0]}"
  while [[ -h "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

discover_repo_root() {
  local start="${1:-$(pwd)}"
  # Prefer Git if available
  local git_root
  git_root="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_root" ]]; then
    echo "$git_root"
    return
  fi
  # Fallback: walk up until a sentinel is found
  local d="$start"
  while [[ "$d" != "/" ]]; do
    if [[ -e "$d/flake.nix" || -d "$d/.git" || -d "$d/profiles" ]]; then
      echo "$d"
      return
    fi
    d="$(dirname "$d")"
  done
  echo "$start"
}

readonly SCRIPT_DIR="$(get_script_dir)"
readonly REPO_ROOT="$(discover_repo_root "$SCRIPT_DIR")"

# Temporary files for cleanup
readonly TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Global flags
DRY_RUN=false
SKIP_COMMIT=false
SKIP_INTERACTIVE=false
SKIP_BUILD_TEST=false
TEMPLATE_TYPE="auto"  # auto, simple, standard, complete

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log() {
    echo -e "${BLUE}[HWC]${NC} $1" >&2
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1" >&2
    fi
}

#==============================================================================
# HELP & VERSION
#==============================================================================

show_help() {
    cat << EOF
${BLUE}HWC Add Home App${NC} - Charter-compliant package installer v${VERSION}

${CYAN}USAGE:${NC}
    add-home-app.sh [OPTIONS] [package-name]

${CYAN}OPTIONS:${NC}
    --dry-run              Show what would be done without making changes
    --no-commit            Skip automatic git commit
    --no-interactive       Skip interactive configuration wizard
    --no-build-test        Skip build testing (faster, less safe)
    --template TYPE        Force template type: simple, standard, complete, auto
    --debug                Enable debug output
    -v, --version          Show version information
    -h, --help             Show this help message

${CYAN}TEMPLATES:${NC}
    auto        Automatically detect best template (default)
    simple      Basic enable option + package
    standard    Add parts/ directory and common options
    complete    Full template with sys.nix and advanced options

${CYAN}EXAMPLES:${NC}
    ${GREEN}# Interactive mode${NC}
    add-home-app.sh

    ${GREEN}# Search for package${NC}
    add-home-app.sh firefox

    ${GREEN}# Dry run to preview changes${NC}
    add-home-app.sh --dry-run libreoffice

    ${GREEN}# Skip commit for manual review${NC}
    add-home-app.sh --no-commit gimp

    ${GREEN}# Force complete template${NC}
    add-home-app.sh --template complete vscode

${CYAN}WORKFLOW:${NC}
    1. Search nixpkgs for package
    2. Detect app type (GUI, CLI, service, etc.)
    3. Generate Charter-compliant module structure
    4. Smart category detection and profile integration
    5. Test configuration before committing
    6. Optional: Commit changes
    7. Optional: Apply to system

${CYAN}MORE INFO:${NC}
    See: CLAUDE.md and CHARTER.md in repository root

EOF
}

show_version() {
    echo "HWC Add Home App v${VERSION}"
}

#==============================================================================
# DEPENDENCY CHECKS
#==============================================================================

check_dependencies() {
    local missing_deps=()

    for cmd in jq nix git rg; do
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

#==============================================================================
# STRING CONVERSION UTILITIES
#==============================================================================

# Convert package name to directory name (kebab-case)
to_kebab_case() {
    local input="$1"

    if [[ -z "$input" ]]; then
        echo "unknown-app"
        return
    fi

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

    if [[ -z "$input" ]]; then
        echo "unknownApp"
        return
    fi

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

#==============================================================================
# MACHINE DETECTION
#==============================================================================

# Detect current machine hostname and validate against flake
detect_machine() {
    local hostname
    hostname=$(hostname)

    debug "Detected hostname: $hostname"

    local flake_json
    if ! flake_json=$(nix flake show --json "path:$REPO_ROOT" 2>/dev/null); then
        warn "Could not query flake outputs; defaulting to hostname '$hostname'"
        echo "$hostname"
        return 0
    fi

    # Check if this matches a flake configuration
    if echo "$flake_json" | jq -e ".nixosConfigurations.\"$hostname\"" &>/dev/null; then
        echo "$hostname"
        return 0
    fi

    # Fallback: list available configurations
    local configs
    configs=$(echo "$flake_json" | jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo "")

    if [[ -n "$configs" ]]; then
        warn "Current hostname '$hostname' not found in flake configurations"
        info "Available machines:"
        echo "$configs" | while read -r conf; do
            echo "  - $conf"
        done
        echo
        echo -n "Enter target machine name: "
        read -r hostname
        echo "$hostname"
        return 0
    else
        error "Could not detect available machines from flake"
        return 1
    fi
}

#==============================================================================
# PACKAGE SEARCH & SELECTION
#==============================================================================

# Search for packages using nix search with better error handling
search_packages() {
    local query="$1"
    local search_file="$TEMP_DIR/search_results.json"

    log "Searching for packages matching '$query'..." >&2

    echo "$query" > "$TEMP_DIR/search_query.txt"

    if ! timeout 30 nix search nixpkgs "$query" --json 2>/dev/null > "$search_file"; then
        error "Failed to search packages. Check your query and network connection."
        return 1
    fi

    if [[ ! -s "$search_file" ]]; then
        error "No search results found for '$query'"
        return 1
    fi

    if ! jq empty "$search_file" 2>/dev/null; then
        error "Search returned invalid JSON"
        return 1
    fi

    local result_count
    result_count=$(jq 'length' "$search_file" 2>/dev/null || echo "0")

    if [[ "$result_count" == "0" ]]; then
        error "No packages found matching '$query'"
        return 1
    fi

    debug "Found $result_count potential matches"
    echo "$search_file"
}

# Parse and format search results with robust error handling
format_search_results() {
    local search_file="$1"
    local formatted_file="$TEMP_DIR/formatted_results.jsonl"
    local query_file="$TEMP_DIR/search_query.txt"
    local jq_errors="$TEMP_DIR/jq_errors.txt"

    local original_query=""
    if [[ -f "$query_file" ]]; then
        original_query=$(cat "$query_file")
    fi

    debug "Formatting results for query: $original_query"

    # IMPROVED: Show errors instead of hiding them with 2>/dev/null
    if ! jq -r --arg query "$original_query" '
        to_entries |
        map(
            {
                key: .key,
                attr: (.key | split(".") | if length > 2 then .[2:] | join(".") else .[-1] end),
                pname: (.value.pname // .value.name // (.key | split(".") | last)),
                version: (.value.version // "unknown"),
                description: (.value.description // .value.meta.description // "No description available"),
                relevance_score: (
                    # IMPROVED: Better relevance scoring
                    if (.value.pname // .value.name // (.key | split(".") | last)) == $query then 100
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | test("^" + $query + "$") then 95
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | test("^" + $query + "-") then 85
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | contains($query) then 75
                    # Penalize unwanted variants
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | test("unwrapped|debug|dev-bin|static"; "i") then 25
                    elif (.value.pname // .value.name // (.key | split(".") | last)) | test("lib$|headers$"; "i") then 20
                    # Penalize dict/lang packs unless searching for them
                    elif (.value.description // "") | test("dictionary|dict|hyphen|thesaurus|language pack"; "i") and ($query | test("dict|lang|thesaurus"; "i") | not) then 15
                    elif (.key | split(".") | last) | test("Dicts|dicts|Dict|Hunspell") and ($query | test("dict|spell"; "i") | not) then 15
                    else 50
                    end
                )
            }
        ) |
        map(select(.pname and .pname != "" and .pname != null and .pname != "null")) |
        sort_by([-.relevance_score, .pname]) |
        # IMPROVED: Better result limiting
        if length > 15 then
            if ($query | test("^(firefox|chrome|chromium|libreoffice|vscode|code|discord|slack|zoom|gimp|inkscape|blender|obs)$"; "i")) then
                map(select(.relevance_score >= 50)) | .[0:10]
            else
                .[0:15]
            end
        else
            .
        end |
        .[] |
        @json
    ' "$search_file" > "$formatted_file" 2>"$jq_errors"; then
        error "Failed to format search results"
        if [[ -s "$jq_errors" ]]; then
            warn "Formatting errors:"
            cat "$jq_errors" | head -10
        fi
        return 1
    fi

    if [[ ! -s "$formatted_file" ]]; then
        error "No valid packages found after filtering"
        warn "This might mean:"
        echo "  - All results were filtered out (unwrapped, debug, lib variants)"
        echo "  - Try a more specific search term"
        return 1
    fi

    local formatted_count
    formatted_count=$(wc -l < "$formatted_file")
    info "Showing $formatted_count most relevant results"

    echo "$formatted_file"
}

# Display search results and let user choose - IMPROVED UI
select_package() {
    local results_file="$1"
    local output_file="$2"
    local -a packages=()
    local i=1

    echo
    log "${CYAN}Available Packages:${NC}"
    echo

    while IFS= read -r line; do
        if [[ -n "$line" ]] && jq empty <<< "$line" 2>/dev/null; then
            packages+=("$line")

            local pname version description attr score
            pname=$(jq -r '.pname // empty' <<< "$line" 2>/dev/null || echo "")
            version=$(jq -r '.version // "unknown"' <<< "$line" 2>/dev/null || echo "unknown")
            description=$(jq -r '.description // empty' <<< "$line" 2>/dev/null || echo "")
            attr=$(jq -r '.attr // empty' <<< "$line" 2>/dev/null || echo "")
            score=$(jq -r '.relevance_score // 0' <<< "$line" 2>/dev/null || echo "0")

            [[ -z "$pname" ]] && pname="unknown"
            [[ -z "$description" ]] && description="No description available"

            # IMPROVED: Better visual layout
            printf "%2d) ${GREEN}%-24s${NC} ${CYAN}v%-14s${NC}" "$i" "$pname" "$version"

            # Show relevance indicator
            if [[ $score -ge 95 ]]; then
                printf " ${GREEN}⭐ EXACT MATCH${NC}\n"
            elif [[ $score -ge 75 ]]; then
                printf " ${CYAN}✓ Close Match${NC}\n"
            else
                printf "\n"
            fi

            # Wrap description intelligently
            if [[ ${#description} -le 76 ]]; then
                printf "    %s\n" "$description"
            else
                printf "    %s\n" "${description:0:73}..."
            fi
            printf "    ${YELLOW}nixpkgs.%s${NC}\n" "$attr"
            echo
            ((i++))
        fi
    done < "$results_file"

    if [[ ${#packages[@]} -eq 0 ]]; then
        error "No valid packages available for selection"
        return 1
    fi

    local choice
    while true; do
        printf "${CYAN}Select [1-${#packages[@]}], 's' to search again, or 'q' to quit:${NC} "
        read -r choice

        case "$choice" in
            [qQ])
                log "Cancelled by user"
                exit 0
                ;;
            [sS])
                info "Re-searching..."
                return 2  # Signal to restart search
                ;;
            ''|*[!0-9]*)
                warn "Please enter a number, 's' to search again, or 'q' to quit"
                continue
                ;;
            *)
                if [[ "$choice" -ge 1 && "$choice" -le ${#packages[@]} ]]; then
                    break
                else
                    warn "Please enter a number between 1 and ${#packages[@]}"
                    continue
                fi
                ;;
        esac
    done

    local selected="${packages[$((choice-1))]}"
    echo "$selected" > "$output_file"
    return 0
}

# Extract package information from JSON
extract_package_info() {
    local package_json="$1"
    local attr_var="$2"
    local pname_var="$3"
    local version_var="$4"
    local description_var="$5"

    local attr pname version description

    attr=$(jq -r '.attr // empty' <<< "$package_json" 2>/dev/null || echo "")
    pname=$(jq -r '.pname // empty' <<< "$package_json" 2>/dev/null || echo "")
    version=$(jq -r '.version // "unknown"' <<< "$package_json" 2>/dev/null || echo "unknown")
    description=$(jq -r '.description // empty' <<< "$package_json" 2>/dev/null || echo "")

    if [[ -z "$attr" || -z "$pname" ]]; then
        local key
        key=$(jq -r '.key // empty' <<< "$package_json" 2>/dev/null || echo "")
        pname=$(jq -r '.value.pname // .value.name // empty' <<< "$package_json" 2>/dev/null || echo "")
        version=$(jq -r '.value.version // "unknown"' <<< "$package_json" 2>/dev/null || echo "unknown")
        description=$(jq -r '.value.description // .value.meta.description // "No description available"' <<< "$package_json" 2>/dev/null || echo "No description available")

        if [[ -n "$key" ]]; then
            attr=$(jq -r 'split(".") | if length > 2 then .[2:] | join(".") else .[-1] end' <<< "\"$key\"" 2>/dev/null || echo "")
        fi
    fi

    [[ -z "$version" ]] && version="unknown"
    [[ -z "$description" ]] && description="No description available"

    if [[ -z "$attr" || -z "$pname" ]]; then
        error "Failed to extract required package information"
        return 1
    fi

    if [[ ! "$attr" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error "Invalid package attribute: $attr"
        return 1
    fi

    printf -v "$attr_var" '%s' "$attr"
    printf -v "$pname_var" '%s' "$pname"
    printf -v "$version_var" '%s' "$version"
    printf -v "$description_var" '%s' "$description"

    return 0
}

#==============================================================================
# APP TYPE & CATEGORY DETECTION
#==============================================================================

# Check if Home Manager has native support for this package
check_home_manager_support() {
    local package_name="$1"
    local package_attr="$2"

    # Try to evaluate if programs.$package_name exists in Home Manager
    if nix eval "nixpkgs#home-manager" --apply "hm: hm ? nixosModules" &>/dev/null; then
        debug "Checking for native HM support for: $package_name"
        # This is a simplified check - in practice, you'd need more sophisticated detection
        # For now, check common ones manually
        case "$package_name" in
            firefox|chromium|git|vim|neovim|tmux|zsh|bash|fish|alacritty|kitty|vscode)
                echo "native"
                return 0
                ;;
        esac
    fi

    # Detect type from package metadata
    local description
    description=$(nix eval "nixpkgs#$package_attr.meta.description" --raw 2>/dev/null || echo "")

    if echo "$description" | grep -qi "gui\|desktop\|window\|graphical"; then
        echo "gui-app"
    elif echo "$description" | grep -qi "cli\|command\|terminal\|console"; then
        echo "cli-tool"
    elif echo "$description" | grep -qi "service\|daemon\|server"; then
        echo "service"
    else
        echo "simple"
    fi
}

# Detect app category for profile organization
detect_app_category() {
    local package_attr="$1"
    local package_name="$2"

    # Check common patterns first
    case "$package_name" in
        *browser|firefox|chromium|chrome|brave|vivaldi|edge|librewolf)
            echo "Web Browsers"
            return 0
            ;;
        *mail|thunderbird|betterbird|aerc|neomutt|mutt|himalaya)
            echo "Mail Clients"
            return 0
            ;;
        *office|libreoffice|onlyoffice|calligra)
            echo "Productivity & Office"
            return 0
            ;;
        *terminal|kitty|alacritty|foot|wezterm|konsole)
            echo "Terminal Emulators"
            return 0
            ;;
        *file*manager|thunar|nautilus|dolphin|pcmanfm|ranger|yazi)
            echo "File Management"
            return 0
            ;;
    esac

    # Check description for keywords
    local description
    description=$(nix eval "nixpkgs#$package_attr.meta.description" --raw 2>/dev/null || echo "")

    if echo "$description" | grep -qi "browser\|web"; then
        echo "Web Browsers"
    elif echo "$description" | grep -qi "mail\|email\|imap\|smtp"; then
        echo "Mail Clients"
    elif echo "$description" | grep -qi "editor\|ide\|development"; then
        echo "Development & Automation"
    elif echo "$description" | grep -qi "office\|document\|spreadsheet\|presentation"; then
        echo "Productivity & Office"
    elif echo "$description" | grep -qi "terminal\|console\|tty"; then
        echo "Terminal Emulators"
    elif echo "$description" | grep -qi "file manager\|file browser"; then
        echo "File Management"
    elif echo "$description" | grep -qi "security\|password\|encryption\|gpg\|authenticator"; then
        echo "Security"
    elif echo "$description" | grep -qi "media\|video\|audio\|music"; then
        echo "Media"
    elif echo "$description" | grep -qi "communication\|chat\|messaging\|slack\|discord"; then
        echo "Communication"
    elif echo "$description" | grep -qi "utility\|tool"; then
        echo "Utilities"
    else
        echo "Other"
    fi
}

#==============================================================================
# DUPLICATE DETECTION
#==============================================================================

check_for_duplicates() {
    local package_name="$1"
    local package_attr="$2"

    log "Checking for existing installations..."

    local found=false

    # Check in domains/home/apps/
    if rg -q "\\b$package_attr\\b" "$REPO_ROOT/domains/home/apps/" 2>/dev/null; then
        warn "Package '$package_attr' appears to be already configured in home apps"
        found=true
    fi

    # Check in system packages
    if rg -q "\\b$package_attr\\b" "$REPO_ROOT/domains/system/" 2>/dev/null; then
        warn "Package '$package_attr' appears to be in system domain"
        found=true
    fi

    # Check if module already exists
    local dir_name
    dir_name=$(to_kebab_case "$package_name")
    if [[ -d "$REPO_ROOT/domains/home/apps/$dir_name" ]]; then
        warn "Module directory already exists: domains/home/apps/$dir_name"
        found=true
    fi

    if [[ "$found" == "true" ]]; then
        echo
        echo -n "Continue anyway? (y/N): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log "Cancelled by user"
            return 1
        fi
    fi

    return 0
}

#==============================================================================
# MODULE GENERATION - options.nix templates
#==============================================================================

generate_options_nix() {
    local option_name="$1"
    local description="$2"
    local output_file="$3"
    local package_name="$4"
    local package_attr="$5"
    local app_type="$6"

    local escaped_description
    escaped_description=$(printf '%s' "$description" | sed 's/"/\\"/g')

    case "$app_type" in
        native)
            generate_options_native "$option_name" "$package_name" "$escaped_description" "$output_file"
            ;;
        gui-app)
            generate_options_gui "$option_name" "$escaped_description" "$output_file"
            ;;
        cli-tool)
            generate_options_cli "$option_name" "$escaped_description" "$output_file"
            ;;
        service)
            generate_options_service "$option_name" "$escaped_description" "$output_file"
            ;;
        *)
            generate_options_simple "$option_name" "$escaped_description" "$output_file"
            ;;
    esac

    # Validate syntax
    if ! nix-instantiate --parse "$output_file" >/dev/null 2>&1; then
        error "Generated options.nix has invalid Nix syntax"
        return 1
    fi
}

generate_options_native() {
    local option_name="$1"
    local package_name="$2"
    local description="$3"
    local output_file="$4"

    cat > "$output_file" << EOF
{ lib, ... }:

{
  options.hwc.home.apps.$option_name = {
    enable = lib.mkEnableOption "$description";

    # NOTE: This package has native Home Manager support via programs.$package_name
    # Consider migrating to use programs.$package_name.enable for better integration
    # See: https://nix-community.github.io/home-manager/options.xhtml

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = ''
        Additional configuration to pass to programs.$package_name.
        Will be merged with default configuration.
      '';
    };
  };
}
EOF
}

generate_options_gui() {
    local option_name="$1"
    local description="$2"
    local output_file="$3"

    cat > "$output_file" << EOF
{ lib, ... }:

{
  options.hwc.home.apps.$option_name = {
    enable = lib.mkEnableOption "$description";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package to use for $option_name.
        If null, uses the default from nixpkgs.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Additional packages to install alongside $option_name.
        Useful for plugins, extensions, or dependencies.
      '';
    };
  };
}
EOF
}

generate_options_cli() {
    local option_name="$1"
    local description="$2"
    local output_file="$3"

    cat > "$output_file" << EOF
{ lib, ... }:

{
  options.hwc.home.apps.$option_name = {
    enable = lib.mkEnableOption "$description";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package to use for $option_name.
        If null, uses the default from nixpkgs.
      '';
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Shell aliases for $option_name";
    };
  };
}
EOF
}

generate_options_service() {
    local option_name="$1"
    local description="$2"
    local output_file="$3"

    cat > "$output_file" << EOF
{ lib, ... }:

{
  options.hwc.home.apps.$option_name = {
    enable = lib.mkEnableOption "$description";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package to use for $option_name.
        If null, uses the default from nixpkgs.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start the service automatically";
    };
  };
}
EOF
}

generate_options_simple() {
    local option_name="$1"
    local description="$2"
    local output_file="$3"

    cat > "$output_file" << EOF
{ lib, ... }:

{
  options.hwc.home.apps.$option_name = {
    enable = lib.mkEnableOption "$description";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package to use for $option_name.
        If null, uses the default from nixpkgs.
      '';
    };
  };
}
EOF
}

#==============================================================================
# MODULE GENERATION - index.nix templates
#==============================================================================

generate_index_nix() {
    local option_name="$1"
    local package_attr="$2"
    local output_file="$3"
    local app_type="$4"
    local package_name="$5"

    case "$app_type" in
        native)
            generate_index_native "$option_name" "$package_name" "$output_file"
            ;;
        gui-app)
            generate_index_gui "$option_name" "$package_attr" "$output_file"
            ;;
        cli-tool)
            generate_index_cli "$option_name" "$package_attr" "$output_file"
            ;;
        service)
            generate_index_service "$option_name" "$package_attr" "$output_file"
            ;;
        *)
            generate_index_simple "$option_name" "$package_attr" "$output_file"
            ;;
    esac

    # Validate syntax
    if ! nix-instantiate --parse "$output_file" >/dev/null 2>&1; then
        error "Generated index.nix has invalid Nix syntax"
        return 1
    fi
}

generate_index_native() {
    local option_name="$1"
    local package_name="$2"
    local output_file="$3"

    cat > "$output_file" << 'EOF'
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.OPTION_NAME;
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
    # Use Home Manager's native programs.PACKAGE_NAME module
    programs.PACKAGE_NAME = {
      enable = true;
    } // cfg.extraConfig;

    assertions = [
      {
        assertion = config.programs.PACKAGE_NAME.enable or false;
        message = "hwc.home.apps.OPTION_NAME requires programs.PACKAGE_NAME to be enabled";
      }
    ];
  };
}
EOF

    sed -i "s/OPTION_NAME/$option_name/g" "$output_file"
    sed -i "s/PACKAGE_NAME/$package_name/g" "$output_file"
}

generate_index_gui() {
    local option_name="$1"
    local package_attr="$2"
    local output_file="$3"

    cat > "$output_file" << 'EOF'
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.OPTION_NAME;
  package = if cfg.package != null then cfg.package else pkgs.PACKAGE_ATTR;
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
    home.packages = [ package ] ++ cfg.extraPackages;

    # TODO: Add application-specific configuration
    # Examples:
    # - xdg.configFile for config files
    # - xdg.desktopEntries for custom launchers
    # - Theme integration with config.hwc.home.theme
    assertions = [
      {
        assertion = cfg.package != null || (pkgs ? PACKAGE_ATTR);
        message = "Package PACKAGE_ATTR not found in nixpkgs and no custom package provided";
      }
    ];
  };
}
EOF

    sed -i "s/OPTION_NAME/$option_name/g" "$output_file"
    sed -i "s/PACKAGE_ATTR/$package_attr/g" "$output_file"
}

generate_index_cli() {
    local option_name="$1"
    local package_attr="$2"
    local output_file="$3"

    cat > "$output_file" << 'EOF'
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.OPTION_NAME;
  package = if cfg.package != null then cfg.package else pkgs.PACKAGE_ATTR;
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
    home.packages = [ package ];

    # Shell integration
    programs.zsh.shellAliases = cfg.aliases;
    programs.bash.shellAliases = cfg.aliases;

    # TODO: Add tool-specific configuration
    # Examples:
    # - xdg.configFile for config files
    # - Shell completions
    # - Environment variables
    assertions = [
      {
        assertion = cfg.package != null || (pkgs ? PACKAGE_ATTR);
        message = "Package PACKAGE_ATTR not found in nixpkgs and no custom package provided";
      }
    ];
  };
}
EOF

    sed -i "s/OPTION_NAME/$option_name/g" "$output_file"
    sed -i "s/PACKAGE_ATTR/$package_attr/g" "$output_file"
}

generate_index_service() {
    local option_name="$1"
    local package_attr="$2"
    local output_file="$3"

    cat > "$output_file" << 'EOF'
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.OPTION_NAME;
  package = if cfg.package != null then cfg.package else pkgs.PACKAGE_ATTR;
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
    home.packages = [ package ];

    # TODO: Add systemd user service configuration
    # Example:
    # systemd.user.services.OPTION_NAME = lib.mkIf cfg.autoStart {
    #   Unit = {
    #     Description = "OPTION_NAME service";
    #     After = [ "graphical-session-pre.target" ];
    #     PartOf = [ "graphical-session.target" ];
    #   };
    #   Service = {
    #     ExecStart = "${package}/bin/PACKAGE_ATTR";
    #     Restart = "on-failure";
    #   };
    #   Install.WantedBy = [ "graphical-session.target" ];
    # };
    assertions = [
      {
        assertion = cfg.package != null || (pkgs ? PACKAGE_ATTR);
        message = "Package PACKAGE_ATTR not found in nixpkgs and no custom package provided";
      }
    ];
  };
}
EOF

    sed -i "s/OPTION_NAME/$option_name/g" "$output_file"
    sed -i "s/PACKAGE_ATTR/$package_attr/g" "$output_file"
}

generate_index_simple() {
    local option_name="$1"
    local package_attr="$2"
    local output_file="$3"

    cat > "$output_file" << 'EOF'
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.OPTION_NAME;
  package = if cfg.package != null then cfg.package else pkgs.PACKAGE_ATTR;
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
    home.packages = [ package ];
    assertions = [
      {
        assertion = cfg.package != null || (pkgs ? PACKAGE_ATTR);
        message = "Package PACKAGE_ATTR not found in nixpkgs and no custom package provided";
      }
    ];
  };
}
EOF

    sed -i "s/OPTION_NAME/$option_name/g" "$output_file"
    sed -i "s/PACKAGE_ATTR/$package_attr/g" "$output_file"
}

#==============================================================================
# SMART PROFILE INTEGRATION
#==============================================================================

add_to_home_profile() {
    local option_name="$1"
    local dir_name="$2"
    local package_attr="$3"
    local package_description="$4"
    local home_profile="$REPO_ROOT/profiles/home.nix"

    if [[ ! -f "$home_profile" ]]; then
        error "Home profile not found at $home_profile"
        return 1
    fi

    # Check if already added
    if grep -q "$option_name\.enable = lib\.mkDefault" "$home_profile"; then
        warn "Package already enabled in home profile"
        return 0
    fi

    # Detect category
    local category
    category=$(detect_app_category "$package_attr" "$option_name")
    info "Category: $category"

    # Create backup
    local backup_file="$home_profile.backup.$(date +%s)"
    cp "$home_profile" "$backup_file"

    # Generate short description
    local short_desc
    short_desc=$(echo "$package_description" | head -c 40)

    # Find insertion point
    local insertion_line
    if grep -q "# $category" "$home_profile"; then
        # Category exists
        local category_start
        category_start=$(grep -n "# $category" "$home_profile" | head -1 | cut -d: -f1)

        # Find last enable line in this category
        local next_category
        next_category=$(sed -n "$((category_start + 1)),\$p" "$home_profile" | grep -n "^[[:space:]]*# " | head -1 | cut -d: -f1)

        if [[ -n "$next_category" ]]; then
            local category_end=$((category_start + next_category - 1))
            insertion_line=$(sed -n "${category_start},${category_end}p" "$home_profile" | \
                grep -n "\.enable = lib\.mkDefault" | tail -1 | cut -d: -f1)
            if [[ -n "$insertion_line" ]]; then
                insertion_line=$((category_start + insertion_line - 1))
            else
                insertion_line=$category_start
            fi
        else
            insertion_line=$(sed -n "${category_start},\$p" "$home_profile" | \
                grep -n "\.enable = lib\.mkDefault" | tail -1 | cut -d: -f1)
            if [[ -n "$insertion_line" ]]; then
                insertion_line=$((category_start + insertion_line - 1))
            else
                insertion_line=$category_start
            fi
        fi
    else
        # Category doesn't exist - find last app entry
        insertion_line=$(grep -n "\.enable = lib\.mkDefault" "$home_profile" | tail -1 | cut -d: -f1)
    fi

    if [[ -z "$insertion_line" ]]; then
        error "Could not find insertion point"
        cp "$backup_file" "$home_profile"
        return 1
    fi

    # Calculate padding for aligned comments
    local enable_text="          $option_name.enable = lib.mkDefault true;"
    local padding_needed=$((58 - ${#enable_text}))
    [[ $padding_needed -lt 2 ]] && padding_needed=2
    local padding=$(printf '%*s' "$padding_needed" '')

    # Insert the line
    sed -i "${insertion_line}a\\          $option_name.enable = lib.mkDefault true;${padding}# $short_desc" "$home_profile"

    # Validate
    if ! grep -q "$option_name\.enable = lib\.mkDefault" "$home_profile"; then
        error "Failed to add entry to home profile"
        cp "$backup_file" "$home_profile"
        return 1
    fi

    if ! nix-instantiate --parse "$home_profile" >/dev/null 2>&1; then
        error "Modified home profile has invalid Nix syntax"
        cp "$backup_file" "$home_profile"
        return 1
    fi

    success "Added to profiles/home.nix (category: $category)"
    echo "$backup_file"
    return 0
}

#==============================================================================
# TESTING & VALIDATION
#==============================================================================

test_package_availability() {
    local package_attr="$1"

    log "Verifying package availability..."

    if ! nix eval "nixpkgs#$package_attr.pname" --raw >/dev/null 2>&1; then
        error "Package '$package_attr' is not available or has evaluation errors"
        return 1
    fi

    success "Package is available in nixpkgs"
    return 0
}

test_configuration_quick() {
    local build_target="$1"

    log "Running quick configuration validation..."

    # Evaluate only the target host to avoid unrelated host failures
    local flake_ref="path:$REPO_ROOT#nixosConfigurations.${build_target}.config.system.build.toplevel"

    if nix eval "$flake_ref" >/dev/null 2>&1; then
        success "Configuration validation passed"
        return 0
    else
        error "Configuration validation failed"
        # Provide context without overwhelming the user
        nix eval "$flake_ref" 2>&1 | tee "$TEMP_DIR/flake-check.log" >/dev/null || true
        cat "$TEMP_DIR/flake-check.log"
        return 1
    fi
}

test_full_build() {
    local build_target="$1"

    log "Running full build test (this may take a while)..."

    if sudo nixos-rebuild build --flake ".#$build_target" 2>&1 | tee "$TEMP_DIR/build.log"; then
        success "Full build test passed"
        return 0
    else
        error "Build test failed"
        return 1
    fi
}

#==============================================================================
# ROLLBACK MECHANISM
#==============================================================================

perform_rollback() {
    local rollback_file="$1"

    warn "Performing rollback..."

    while IFS= read -r line; do
        case "$line" in
            MODULE_CREATED:*)
                local module_dir="${line#MODULE_CREATED:}"
                if [[ -d "$module_dir" ]]; then
                    rm -rf "$module_dir"
                    log "Removed: $module_dir"
                fi
                ;;
            PROFILE_BACKUP:*)
                local backup_file="${line#PROFILE_BACKUP:}"
                if [[ -f "$backup_file" ]]; then
                    cp "$backup_file" "$REPO_ROOT/profiles/home.nix"
                    log "Restored: profiles/home.nix"
                fi
                ;;
        esac
    done < "$rollback_file"

    success "Rollback complete"
}

#==============================================================================
# GIT OPERATIONS
#==============================================================================

commit_changes() {
    local package_name="$1"
    local package_attr="$2"
    local package_version="$3"
    local package_description="$4"
    local dir_name="$5"
    local option_name="$6"

    if [[ "$SKIP_COMMIT" == "true" ]]; then
        info "Skipping commit (--no-commit flag)"
        return 0
    fi

    log "Staging changes for commit..."

    if ! git status --porcelain | grep -q .; then
        warn "No changes to commit"
        return 0
    fi

    if ! git add "domains/home/apps/$dir_name/" "profiles/home.nix"; then
        error "Failed to stage files for commit"
        return 1
    fi

    local commit_msg="feat(home.apps.$option_name): add $package_name module

- Create domains/home/apps/$dir_name following HWC Charter
- Add options.nix with hwc.home.apps.$option_name namespace
- Add index.nix with proper VALIDATION section
- Enable in profiles/home.nix

Package: $package_attr ($package_version)
Description: $package_description

Generated with add-home-app.sh v${VERSION}

Co-Authored-By: Claude <noreply@anthropic.com>"

    if git commit -m "$commit_msg"; then
        success "Changes committed to git"
        return 0
    else
        error "Failed to commit changes"
        return 1
    fi
}

#==============================================================================
# POST-INSTALLATION GUIDANCE
#==============================================================================

show_configuration_hints() {
    local package_name="$1"
    local package_attr="$2"
    local option_name="$3"
    local app_dir="$4"

    echo
    log "${CYAN}Configuration Guidance:${NC}"
    echo

    # Try to get homepage
    local homepage
    homepage=$(nix eval "nixpkgs#$package_attr.meta.homepage" --raw 2>/dev/null || echo "")
    if [[ -n "$homepage" && "$homepage" != "null" ]]; then
        info "Homepage: $homepage"
    fi

    # Check for Home Manager module
    case "$package_name" in
        firefox|chromium|git|vim|neovim|tmux|zsh|bash)
            warn "Home Manager has a native module for $package_name"
            info "Consider using programs.$package_name for better integration"
            info "See: https://nix-community.github.io/home-manager/options.xhtml"
            ;;
    esac

    echo
    info "Module location: $app_dir"
    info "To customize, edit: $app_dir/options.nix and $app_dir/index.nix"
    echo
}

#==============================================================================
# MAIN WORKFLOW
#==============================================================================

main() {
    local package_query="${1:-}"

    # Change to repo root
    cd "$REPO_ROOT" || {
        error "Failed to change to repo root: $REPO_ROOT"
        exit 1
    }

    log "${CYAN}HWC Add Home App${NC} v${VERSION}"
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

    # Detect machine
    local target_machine
    if ! target_machine=$(detect_machine); then
        exit 1
    fi
    info "Target machine: $target_machine"
    echo

    # IMPROVED: Loop to allow re-searching
    local selected_package
    while true; do
        # Search for packages
        local search_file
        if ! search_file=$(search_packages "$package_query"); then
            exit 1
        fi

        # Format search results
        local results_file
        if ! results_file=$(format_search_results "$search_file"); then
            exit 1
        fi

        # Let user select package
        local selection_file="$TEMP_DIR/selected_package.json"
        local select_result
        select_package "$results_file" "$selection_file"
        select_result=$?

        if [[ $select_result -eq 2 ]]; then
            # User wants to re-search
            echo
            echo -n "Enter new search term: "
            read -r package_query
            if [[ -z "$package_query" ]]; then
                error "Search term cannot be empty"
                exit 1
            fi
            continue  # Restart search loop
        elif [[ $select_result -ne 0 ]]; then
            exit 1
        else
            break  # Selection successful
        fi
    done

    local selected_package
    selected_package=$(cat "$selection_file")

    # Extract package information
    local package_attr package_name package_version package_description
    if ! extract_package_info "$selected_package" package_attr package_name package_version package_description; then
        exit 1
    fi

    echo
    success "Selected: ${GREEN}$package_name${NC} ${CYAN}($package_version)${NC}"
    info "Description: $package_description"
    info "Attribute: $package_attr"
    echo

    # Test package availability
    if ! test_package_availability "$package_attr"; then
        exit 1
    fi

    # Detect app type
    local app_type
    app_type=$(check_home_manager_support "$package_name" "$package_attr")
    info "App type: $app_type"

    # Check for duplicates
    if ! check_for_duplicates "$package_name" "$package_attr"; then
        exit 1
    fi

    # Confirm selection
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        echo -n "Proceed with adding this package? (y/N): "
        read -r confirm

        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log "Cancelled by user"
            exit 0
        fi
    fi

    # Generate names
    local dir_name option_name
    dir_name=$(to_kebab_case "$package_name")
    option_name=$(to_camel_case "$package_name")

    local app_dir="$REPO_ROOT/domains/home/apps/$dir_name"

    echo
    log "Module configuration:"
    info "Directory: domains/home/apps/$dir_name"
    info "Namespace: hwc.home.apps.$option_name"
    info "Type: $app_type"
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN - Would create module and update profile"
        exit 0
    fi

    # Setup rollback tracking
    local rollback_state="$TEMP_DIR/rollback_state.txt"
    echo "INITIAL" > "$rollback_state"

    # Check if directory already exists
    if [[ -d "$app_dir" ]]; then
        error "Directory already exists: $app_dir"
        exit 1
    fi

    # Create directory
    if ! mkdir -p "$app_dir"; then
        error "Failed to create directory: $app_dir"
        exit 1
    fi
    echo "MODULE_CREATED:$app_dir" >> "$rollback_state"

    # Generate module files
    if ! generate_options_nix "$option_name" "$package_description" "$app_dir/options.nix" \
        "$package_name" "$package_attr" "$app_type"; then
        perform_rollback "$rollback_state"
        exit 1
    fi

    if ! generate_index_nix "$option_name" "$package_attr" "$app_dir/index.nix" \
        "$app_type" "$package_name"; then
        perform_rollback "$rollback_state"
        exit 1
    fi

    success "Created module files"

    # Add to home profile
    local backup_file
    if ! backup_file=$(add_to_home_profile "$option_name" "$dir_name" "$package_attr" "$package_description"); then
        perform_rollback "$rollback_state"
        exit 1
    fi
    echo "PROFILE_BACKUP:$backup_file" >> "$rollback_state"

    # TEST BEFORE COMMITTING
    if [[ "$SKIP_BUILD_TEST" != "true" ]]; then
        echo
        log "Testing configuration..."
        if ! test_configuration_quick "$target_machine"; then
            error "Configuration test failed"
            warn "Rolling back changes..."
            perform_rollback "$rollback_state"
            exit 1
        fi

        # Offer full build test
        echo
        echo -n "Run full build test? (slower but thorough) (y/N): "
        read -r do_full_build

        if [[ "$do_full_build" == "y" || "$do_full_build" == "Y" ]]; then
            if ! test_full_build "$target_machine"; then
                error "Full build test failed"
                warn "Rolling back changes..."
                perform_rollback "$rollback_state"
                exit 1
            fi
        fi
    fi

    # Commit changes
    echo
    if ! commit_changes "$package_name" "$package_attr" "$package_version" \
        "$package_description" "$dir_name" "$option_name"; then
        warn "Failed to commit, but files are in working state"
    fi

    # Show configuration hints
    show_configuration_hints "$package_name" "$package_attr" "$option_name" "$app_dir"

    # Summary
    echo
    success "Package '$package_name' successfully added!"
    echo
    info "Next steps:"
    echo "  1. Review generated files in: domains/home/apps/$dir_name"
    echo "  2. Customize options in: $app_dir/options.nix"
    echo "  3. Add configuration in: $app_dir/index.nix"
    echo "  4. Apply changes: sudo nixos-rebuild switch --flake '.#$target_machine'"
    echo

    # Offer to apply now
    echo -n "Apply configuration now? (y/N): "
    read -r apply_now

    if [[ "$apply_now" == "y" || "$apply_now" == "Y" ]]; then
        log "Applying configuration..."
        if sudo nixos-rebuild switch --flake ".#$target_machine"; then
            success "Configuration applied successfully!"
        else
            error "Failed to apply configuration"
            warn "Your changes are committed but not active"
            warn "Review errors and try: sudo nixos-rebuild switch --flake '.#$target_machine'"
        fi
    fi
}

#==============================================================================
# SCRIPT ENTRY POINT
#==============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-commit)
                SKIP_COMMIT=true
                shift
                ;;
            --no-interactive)
                SKIP_INTERACTIVE=true
                shift
                ;;
            --no-build-test)
                SKIP_BUILD_TEST=true
                shift
                ;;
            --template)
                TEMPLATE_TYPE="$2"
                shift 2
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done

    # Check dependencies
    check_dependencies

    # Run main function
    main "$@"
fi
