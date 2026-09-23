#!/usr/bin/env bash

# HWC Charter-compliant script for adding packages to domains/home/apps
# Version: 3.0 — repaired against Charter v12.6 repository contracts
# Usage: ./workspace/nixos-dev/add-home-app.sh [OPTIONS] [package-name]
#
# Entry point: the `add-app` zsh function
# (domains/home/core/shell/parts/zsh-init.nix). Regression suite:
# workspace/nixos-dev/tests/test-add-home-app.sh.
#
# What v3.0 repaired (all four were live breakage against the current repo):
#   * machine detection walked EVERY flake output via `nix flake show` — minutes
#     of evaluation, and one unrelated broken output took the whole tool down.
#     Now a targeted `nix eval #nixosConfigurations --apply builtins.attrNames`.
#   * package search resolved against the `nixpkgs` REGISTRY, which moves
#     independently of this repo. Now resolved from the revision flake.lock pins.
#   * `--no-interactive` set a flag nothing read; every prompt still blocked.
#     Now a real contract: exactly one exact top-level attribute, or a loud
#     failure with candidates and a stable exit code.
#   * generation emitted `options.nix` (Law 10 forbids it) and wrote to
#     `profiles/home.nix` (deleted in the roles refactor). Now the module goes
#     through domains/lib/mkSimpleApp.nix or a Law-6 native adapter, and the app
#     is enabled in machines/<machine>/home.nix.

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
readonly VERSION="3.0.0"

# Stable exit codes — the non-interactive contract is scriptable only if these
# do not move. Referenced by tests/test-add-home-app.sh.
readonly E_FAIL=1        # generic failure
readonly E_USAGE=2       # bad invocation
readonly E_NOMATCH=3     # --no-interactive: no exact top-level attribute
readonly E_AMBIGUOUS=4   # --no-interactive: more than one exact match
readonly E_MACHINE=5     # target machine not in the flake
readonly E_CONFLICT=7    # module directory already exists

#==============================================================================
# ENVIRONMENT SETUP
#==============================================================================

# NixOS puts nix in the system profile; cron/systemd/agent contexts often run
# with a PATH that has no profile bin on it at all.
if ! command -v nix >/dev/null 2>&1 && [[ -x /run/current-system/sw/bin/nix ]]; then
    PATH="/run/current-system/sw/bin:$PATH"
    export PATH
fi

# Every nix call goes through this so flake support does not depend on the
# caller's nix.conf.
NIX=(nix --extra-experimental-features "nix-command flakes")

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
# The invocation directory wins over the script's own location: the script is
# called through the `add-app` wrapper from whichever checkout or worktree the
# user is standing in, and that checkout is the one to write to.
REPO_ROOT="$(discover_repo_root "$(pwd)")"
if [[ ! -e "$REPO_ROOT/flake.nix" ]]; then
    REPO_ROOT="$(discover_repo_root "$SCRIPT_DIR")"
fi

readonly SYSTEM="$(uname -m)-linux"

# Temporary files for cleanup
readonly TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Global flags
DRY_RUN=false
SKIP_COMMIT=false
SKIP_INTERACTIVE=false
SKIP_BUILD_TEST=false
TEMPLATE_TYPE="auto"       # auto, simple, native
MACHINE_OVERRIDE=""

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

# die <exit-code> <message...>
die() {
    local code="$1"; shift
    error "$*"
    exit "$code"
}

#==============================================================================
# HELP & VERSION
#==============================================================================

show_help() {
    cat << EOF
${BLUE}HWC Add Home App${NC} - Charter-compliant module scaffolder v${VERSION}

${CYAN}USAGE:${NC}
    add-home-app.sh [OPTIONS] [package-name]

${CYAN}OPTIONS:${NC}
    --dry-run              Show what would be done without making changes
    --no-commit            Skip automatic git commit
    --no-interactive       Resolve one exact top-level attribute, never prompt
    --no-build-test        Skip build testing (faster, less safe)
    --machine NAME         Target flake machine (default: this host)
    --template TYPE        Force template: auto, simple, native
    --debug                Enable debug output
    -v, --version          Show version information
    -h, --help             Show this help message

${CYAN}TEMPLATES:${NC}
    auto        Pick from the locked home-manager (default)
    simple      One-package module via domains/lib/mkSimpleApp.nix
    native      Law-6 adapter over Home Manager's programs.<name>

    The v2 gui/cli/service/complete templates are gone: all three emitted an
    options.nix, which Charter Law 10 forbids. Anything needing more than an
    enable toggle is hand-written after scaffolding.

${CYAN}EXIT CODES:${NC}
    0 ok   ${E_FAIL} failure   ${E_USAGE} usage   ${E_NOMATCH} no exact match
    ${E_AMBIGUOUS} ambiguous match   ${E_MACHINE} unknown machine   ${E_CONFLICT} module exists

${CYAN}EXAMPLES:${NC}
    ${GREEN}# Interactive search-and-select${NC}
    add-app
    add-app firefox

    ${GREEN}# Deterministic, no stdin, no writes${NC}
    add-app --dry-run --no-interactive vesktop

${CYAN}WORKFLOW:${NC}
    1. Resolve the target machine from the flake (names only)
    2. Search the nixpkgs revision THIS repo locks
    3. Decide native (programs.<name>) vs one-package (mkSimpleApp)
    4. Generate domains/home/apps/<name>/{index.nix,README.md}
    5. Update domains/home/apps/README.md
    6. Enable in machines/<machine>/home.nix
    7. Optional: validate, commit

${CYAN}MORE INFO:${NC}
    See: CLAUDE.md and CHARTER.md in repository root
    Tests: workspace/nixos-dev/tests/test-add-home-app.sh

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

    for cmd in jq nix git rg awk; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please install these tools and try again"
        exit "$E_FAIL"
    fi
}

#==============================================================================
# STRING CONVERSION UTILITIES
#==============================================================================

# Convert package name to directory name (kebab-case).
# Law 2 makes this the namespace too: hwc.home.apps.<dir-name>. There is no
# camelCase step — domains/home/apps/claude-code declares
# hwc.home.apps.claude-code, not hwc.home.apps.claudeCode.
to_kebab_case() {
    local input="$1"

    if [[ -z "$input" ]]; then
        echo "unknown-app"
        return
    fi

    local out
    out="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' \
        | tr -c 'a-z0-9\n' '-' \
        | awk '{ gsub(/-+/, "-"); gsub(/^-|-$/, ""); print }')"

    [[ -z "$out" ]] && out="unknown-app"
    printf '%s\n' "$out"
}

# Escape a string for use inside a Nix "..." literal.
nix_escape() {
    printf '%s' "$1" | awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\$/, "\\$"); print }'
}

#==============================================================================
# LOCKED INPUT RESOLUTION
#==============================================================================
# Everything the tool looks up — package attributes, versions, descriptions,
# whether Home Manager has a native module — resolves from the revisions THIS
# repository locks. The `nixpkgs` registry entry is a moving target that has no
# relationship to what the machine will actually build.

lock_node() { # <input-name> -> the locked node object, or empty
    local name="$1"
    [[ -f "$REPO_ROOT/flake.lock" ]] || return 1
    jq -e -r --arg n "$name" '
        (.nodes.root.inputs[$n] // empty) as $ref
        | (if ($ref | type) == "array" then $ref[0] else $ref end) as $id
        | .nodes[$id].locked // empty
    ' "$REPO_ROOT/flake.lock" 2>/dev/null
}

lock_input_ref() { # <input-name> -> a flake reference string
    local node
    node="$(lock_node "$1")" || return 1
    jq -e -r '
        if   .type == "github" then "github:\(.owner)/\(.repo)/\(.rev)"
        elif .type == "gitlab" then "gitlab:\(.owner)/\(.repo)/\(.rev)"
        elif .type == "sourcehut" then "sourcehut:\(.owner)/\(.repo)/\(.rev)"
        elif .type == "git"    then "git+\(.url)?rev=\(.rev)"
        elif .type == "tarball" then .url
        elif .type == "path"   then "path:\(.path)"
        else empty end
    ' <<< "$node" 2>/dev/null
}

lock_input_dir() { # <input-name> -> a local directory holding that input
    local node type path
    node="$(lock_node "$1")" || return 1
    type="$(jq -r '.type // empty' <<< "$node")"
    if [[ "$type" == "path" ]]; then
        path="$(jq -r '.path // empty' <<< "$node")"
        [[ -z "$path" ]] && return 1
        [[ "$path" != /* ]] && path="$REPO_ROOT/$path"
        printf '%s\n' "$path"
        return 0
    fi
    local ref
    ref="$(lock_input_ref "$1")" || return 1
    "${NIX[@]}" flake metadata --json "$ref" 2>/dev/null | jq -e -r '.path // empty'
}

NIXPKGS_REF_CACHE=""
nixpkgs_ref() {
    if [[ -z "$NIXPKGS_REF_CACHE" ]]; then
        NIXPKGS_REF_CACHE="$(lock_input_ref nixpkgs || true)"
        [[ -z "$NIXPKGS_REF_CACHE" ]] && die "$E_FAIL" \
            "Could not resolve the nixpkgs revision from $REPO_ROOT/flake.lock"
        debug "locked nixpkgs: $NIXPKGS_REF_CACHE"
    fi
    printf '%s\n' "$NIXPKGS_REF_CACHE"
}

#==============================================================================
# MACHINE DETECTION
#==============================================================================
# Targeted: the attribute NAMES of nixosConfigurations and nothing else. The
# v2 code ran `nix flake show --json`, which walks every output — packages,
# checks, apps, every machine — so it paid minutes of evaluation for a list of
# five strings and died outright if any unrelated output was broken.

current_hostname() {
    local h=""
    if command -v hostname >/dev/null 2>&1; then
        h="$(hostname 2>/dev/null || true)"
    fi
    [[ -z "$h" ]] && h="$(uname -n 2>/dev/null || true)"
    [[ -z "$h" && -r /etc/hostname ]] && h="$(< /etc/hostname)"
    printf '%s\n' "${h%%.*}"
}

flake_machine_names() {
    "${NIX[@]}" eval --json "path:$REPO_ROOT#nixosConfigurations" \
        --apply 'builtins.attrNames' 2>/dev/null \
        | jq -r '.[]' 2>/dev/null
}

detect_machine() {
    # Progress before the first slow call, not after it.
    log "Resolving target machine from flake.nix (names only)..."

    local candidate="${MACHINE_OVERRIDE:-$(current_hostname)}"
    debug "candidate machine: $candidate"

    local names
    names="$(flake_machine_names)"
    if [[ -z "$names" ]]; then
        error "Could not read nixosConfigurations from $REPO_ROOT"
        return "$E_MACHINE"
    fi

    if rg -Fxq -- "$candidate" <<< "$names"; then
        printf '%s\n' "$candidate"
        return 0
    fi

    warn "Machine '$candidate' is not in this flake. Available:"
    while IFS= read -r conf; do info "  - $conf"; done <<< "$names"

    if [[ "$SKIP_INTERACTIVE" == "true" ]]; then
        error "--no-interactive: refusing to guess a machine. Pass --machine NAME."
        return "$E_MACHINE"
    fi

    echo -n "Enter target machine name: " >&2
    local chosen
    read -r chosen
    if ! rg -Fxq -- "$chosen" <<< "$names"; then
        error "'$chosen' is not in this flake either"
        return "$E_MACHINE"
    fi
    printf '%s\n' "$chosen"
}

# nixosConfigurations."hwc-laptop" is built from machines/laptop/.
machine_dir_for() {
    printf '%s\n' "${1#hwc-}"
}

#==============================================================================
# PACKAGE SEARCH & SELECTION
#==============================================================================

# Search the LOCKED nixpkgs. Regex is passed through to `nix search`.
nixpkgs_search_json() { # <regex> <outfile>
    local regex="$1" out="$2"
    timeout 300 "${NIX[@]}" search --json "$(nixpkgs_ref)" "$regex" \
        >"$out" 2>"$TEMP_DIR/search_stderr.txt" || return 1
    [[ -s "$out" ]] || return 1
    jq empty "$out" 2>/dev/null || return 1
    return 0
}

search_packages() {
    local query="$1"
    local search_file="$TEMP_DIR/search_results.json"

    log "Searching the locked nixpkgs ($(nixpkgs_ref)) for '$query'..."
    echo "$query" > "$TEMP_DIR/search_query.txt"

    if ! nixpkgs_search_json "$query" "$search_file"; then
        error "No usable search results for '$query'"
        [[ -s "$TEMP_DIR/search_stderr.txt" ]] && head -5 "$TEMP_DIR/search_stderr.txt" >&2
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

# Non-interactive resolution. The contract: exactly one EXACT top-level
# attribute in the locked nixpkgs. Zero or several is a loud, stable failure —
# never a silent "best guess", which is what makes this safe in a script.
#
# Top-level means the attribute path under packages.<system>/legacyPackages.
# <system> has no further dots, so python3Packages.foo can never be chosen by
# a bare `foo` query.
resolve_exact_match() { # <query> -> prints the chosen attr on stdout
    local query="$1"
    local exact_file="$TEMP_DIR/exact.json"

    log "Resolving '$query' to one exact top-level attribute..."

    if ! nixpkgs_search_json "^${query}\$" "$exact_file"; then
        echo '{}' > "$exact_file"
    fi

    local hits
    hits="$(jq -r --arg q "$query" --arg sys "$SYSTEM" '
        to_entries
        | map(select((.key | startswith("legacyPackages." + $sys + "."))
                  or (.key | startswith("packages." + $sys + "."))))
        | map(. + { attr: (.key | split(".") | .[2:] | join(".")) })
        | map(select(.attr == $q))
        | .[].key
    ' "$exact_file" 2>/dev/null)"

    local count=0
    [[ -n "$hits" ]] && count="$(wc -l <<< "$hits")"

    if [[ "$count" -eq 1 ]]; then
        local key attr
        key="$hits"
        attr="$(awk -F. '{ for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF ? "." : "\n") }' <<< "$key")"
        jq -r --arg k "$key" --arg a "$attr" '
            { attr: $a,
              pname: (.[$k].pname // $a),
              version: (.[$k].version // "unknown"),
              description: (.[$k].description // "No description available") }
        ' "$exact_file"
        return 0
    fi

    if [[ "$count" -gt 1 ]]; then
        error "'$query' has $count exact top-level matches in the locked nixpkgs:"
        while IFS= read -r k; do info "  - $k"; done <<< "$hits"
        error "Disambiguate by passing the attribute you want explicitly."
        return "$E_AMBIGUOUS"
    fi

    error "'$query': no exact top-level match in the locked nixpkgs ($(nixpkgs_ref))"
    local near_file="$TEMP_DIR/near.json"
    if nixpkgs_search_json "$query" "$near_file"; then
        local candidates
        candidates="$(jq -r 'to_entries | map(.key) | .[0:10] | .[]' "$near_file" 2>/dev/null)"
        if [[ -n "$candidates" ]]; then
            error "Closest candidates:"
            while IFS= read -r c; do info "  - $c"; done <<< "$candidates"
        fi
    else
        error "No near matches either."
    fi
    return "$E_NOMATCH"
}

# Parse and format search results for the interactive picker.
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

    if ! jq -r --arg query "$original_query" --arg sys "$SYSTEM" '
        to_entries |
        map(
            {
                key: .key,
                attr: (.key | split(".") | if length > 2 then .[2:] | join(".") else .[-1] end),
                pname: (.value.pname // (.key | split(".") | last)),
                version: (.value.version // "unknown"),
                description: (.value.description // "No description available"),
                relevance_score: (
                    (.key | split(".") | if length > 2 then .[2:] | join(".") else .[-1] end) as $attr |
                    if $attr == $query then 100
                    elif ($attr | test("^" + $query + "-")) then 85
                    elif ($attr | contains($query)) then 75
                    elif ($attr | test("unwrapped|debug|dev-bin|static"; "i")) then 25
                    elif ($attr | test("lib$|headers$"; "i")) then 20
                    else 50
                    end
                )
            }
        ) |
        map(select(.pname and .pname != "" and .pname != "null")) |
        sort_by([-.relevance_score, .pname]) |
        .[0:15] |
        .[] |
        @json
    ' "$search_file" > "$formatted_file" 2>"$jq_errors"; then
        error "Failed to format search results"
        if [[ -s "$jq_errors" ]]; then
            warn "Formatting errors:"
            head -10 "$jq_errors" >&2
        fi
        return 1
    fi

    if [[ ! -s "$formatted_file" ]]; then
        error "No valid packages found after filtering"
        return 1
    fi

    local formatted_count
    formatted_count=$(wc -l < "$formatted_file")
    info "Showing $formatted_count most relevant results"

    echo "$formatted_file"
}

# Display search results and let the user choose. Unchanged in spirit: this is
# the workflow Eric actually uses, and the repair must not cost it.
select_package() {
    local results_file="$1"
    local output_file="$2"
    local -a packages=()
    local i=1

    echo >&2
    log "${CYAN}Available Packages:${NC}"
    echo >&2

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

            printf "%2d) ${GREEN}%-24s${NC} ${CYAN}v%-14s${NC}" "$i" "$pname" "$version" >&2

            if [[ $score -ge 95 ]]; then
                printf " ${GREEN}⭐ EXACT MATCH${NC}\n" >&2
            elif [[ $score -ge 75 ]]; then
                printf " ${CYAN}✓ Close Match${NC}\n" >&2
            else
                printf "\n" >&2
            fi

            if [[ ${#description} -le 76 ]]; then
                printf "    %s\n" "$description" >&2
            else
                printf "    %s\n" "${description:0:73}..." >&2
            fi
            printf "    ${YELLOW}nixpkgs.%s${NC}\n\n" "$attr" >&2
            ((i++))
        fi
    done < "$results_file"

    if [[ ${#packages[@]} -eq 0 ]]; then
        error "No valid packages available for selection"
        return 1
    fi

    local choice
    while true; do
        printf "${CYAN}Select [1-${#packages[@]}], 's' to search again, or 'q' to quit:${NC} " >&2
        read -r choice

        case "$choice" in
            [qQ]) log "Cancelled by user"; exit 0 ;;
            [sS]) info "Re-searching..."; return 2 ;;
            ''|*[!0-9]*) warn "Please enter a number, 's' to search again, or 'q' to quit"; continue ;;
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

extract_package_info() {
    local package_json="$1"
    local attr_var="$2" pname_var="$3" version_var="$4" description_var="$5"

    local attr pname version description
    attr=$(jq -r '.attr // empty' <<< "$package_json" 2>/dev/null || echo "")
    pname=$(jq -r '.pname // empty' <<< "$package_json" 2>/dev/null || echo "")
    version=$(jq -r '.version // "unknown"' <<< "$package_json" 2>/dev/null || echo "unknown")
    description=$(jq -r '.description // empty' <<< "$package_json" 2>/dev/null || echo "")

    [[ -z "$pname" ]] && pname="$attr"
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
# APP TYPE DETECTION
#==============================================================================
# v2 carried a hardcoded list of a dozen package names. It was written before
# most of this repo's apps existed and had already gone stale — vesktop, the
# app this repo most recently added through programs.<name>, was not on it.
#
# The authoritative signal is home-manager's own module tree at the revision
# flake.lock pins: programs.<name> exists iff modules/programs/<name>.nix does.

check_home_manager_support() {
    local app_name="$1"

    local hm_dir
    if ! hm_dir="$(lock_input_dir home-manager)" || [[ -z "$hm_dir" ]]; then
        warn "Could not resolve the locked home-manager; assuming no native module"
        echo "simple"
        return 0
    fi
    debug "home-manager source: $hm_dir"

    # Home Manager uses BOTH layouts for programs.<name>: a flat
    # modules/programs/<name>.nix (kitty, firefoxpwa) and a directory
    # modules/programs/<name>/ (firefox, vesktop). Checking only the flat form
    # silently reports "simple" for every directory-shaped module — which is
    # how a first pass of this repair called vesktop a plain one-package app.
    if [[ -f "$hm_dir/modules/programs/$app_name.nix" \
       || -d "$hm_dir/modules/programs/$app_name" ]]; then
        echo "native"
    else
        echo "simple"
    fi
}

#==============================================================================
# DUPLICATE DETECTION
#==============================================================================

check_for_duplicates() {
    local app_name="$1"
    local package_attr="$2"

    log "Checking for existing installations..."
    local found=false

    if rg -q "\\b$package_attr\\b" "$REPO_ROOT/domains/home/apps/" 2>/dev/null; then
        warn "'$package_attr' already appears in domains/home/apps/"
        found=true
    fi
    if rg -q "\\b$package_attr\\b" "$REPO_ROOT/domains/system/" 2>/dev/null; then
        warn "'$package_attr' already appears in domains/system/"
        found=true
    fi
    if [[ -d "$REPO_ROOT/domains/home/apps/$app_name" ]]; then
        # A dry run describes; it does not enforce. Reporting the collision is
        # the useful answer — exiting non-zero would make `--dry-run` unusable
        # for inspecting an app the repo already carries.
        if [[ "$DRY_RUN" == "true" ]]; then
            warn "Module directory already exists: domains/home/apps/$app_name"
            warn "A real run would refuse here."
            return 0
        fi
        error "Module directory already exists: domains/home/apps/$app_name"
        return "$E_CONFLICT"
    fi

    if [[ "$found" == "true" ]]; then
        if [[ "$SKIP_INTERACTIVE" == "true" ]]; then
            warn "--no-interactive: continuing past the duplicate warning"
            return 0
        fi
        echo >&2
        echo -n "Continue anyway? (y/N): " >&2
        local confirm
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log "Cancelled by user"
            return "$E_FAIL"
        fi
    fi
    return 0
}

#==============================================================================
# WORKTREE DISCIPLINE
#==============================================================================
# `main` is not a working surface in this repo. If the caller is standing on it,
# generation moves to a dedicated feature worktree rather than refusing outright
# — the point is that main stays untouched, not that the user gets turned away.

current_branch() {
    git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

ensure_feature_worktree() { # <app-name>  — may reassign REPO_ROOT
    local app_name="$1"
    local branch
    branch="$(current_branch)"

    if [[ -z "$branch" ]]; then
        warn "Not a git checkout; skipping worktree discipline"
        return 0
    fi

    if [[ "$branch" != "main" && "$branch" != "master" ]]; then
        info "On feature branch '$branch' — generating here"
        return 0
    fi

    local wt_branch="add-app/$app_name"
    local wt_root wt_path
    wt_root="$(dirname "$REPO_ROOT")/.nixos-worktrees"
    wt_path="$wt_root/$app_name"

    warn "Refusing to write to '$branch'."
    log "Creating a dedicated feature worktree: $wt_path (branch $wt_branch)"

    mkdir -p "$wt_root"
    if [[ -d "$wt_path" ]]; then
        error "Worktree path already exists: $wt_path"
        return "$E_FAIL"
    fi
    if ! git -C "$REPO_ROOT" worktree add -b "$wt_branch" "$wt_path" HEAD >&2; then
        error "Failed to create worktree at $wt_path"
        return "$E_FAIL"
    fi

    REPO_ROOT="$wt_path"
    success "Generating in $REPO_ROOT (branch $wt_branch); '$branch' untouched"
    return 0
}

#==============================================================================
# MODULE GENERATION
#==============================================================================
# Two producers, both Charter-current. No options.nix is emitted by either —
# Law 10 puts option declarations in index.nix, and the v2 templates that
# emitted a sibling options.nix are the machine-generated precedent §0.13 names.

generate_index_simple() { # <app-name> <attr> <description> <outfile>
    local app_name="$1" package_attr="$2" description="$3" output_file="$4"
    local desc; desc="$(nix_escape "$description")"

    cat > "$output_file" <<EOF
# domains/home/apps/$app_name/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "$app_name";
  description = "$desc";
  package = pkgs: pkgs.$package_attr;
}
EOF
}

generate_index_native() { # <app-name> <description> <outfile>
    local app_name="$1" description="$2" output_file="$3"
    local desc; desc="$(nix_escape "$description")"

    cat > "$output_file" <<EOF
# domains/home/apps/$app_name/index.nix
{ config, lib, ... }:
let
  cfg = config.hwc.home.apps.$app_name;
in
{
  # OPTIONS
  options.hwc.home.apps.$app_name = {
    enable = lib.mkEnableOption "$desc";
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    programs.$app_name.enable = true;

    # VALIDATION
    assertions = [
      {
        assertion = config.programs.$app_name.enable;
        message = "programs.$app_name must remain enabled when hwc.home.apps.$app_name is enabled";
      }
    ];
  };
}
EOF
}

generate_index_nix() { # <app-name> <attr> <description> <app-type> <outfile>
    local app_name="$1" package_attr="$2" description="$3" app_type="$4" output_file="$5"

    case "$app_type" in
        native) generate_index_native "$app_name" "$description" "$output_file" ;;
        *)      generate_index_simple "$app_name" "$package_attr" "$description" "$output_file" ;;
    esac

    if command -v nix-instantiate >/dev/null 2>&1; then
        if ! nix-instantiate --parse "$output_file" >/dev/null 2>&1; then
            error "Generated index.nix has invalid Nix syntax"
            return 1
        fi
    fi
    return 0
}

# Law 12: every domains/home/apps/<name>/ carries a README with these four
# sections. Generating it is not a nicety — the charter-law12 check fails the
# commit without it.
generate_app_readme() { # <app-name> <attr> <description> <app-type> <outfile>
    local app_name="$1" package_attr="$2" description="$3" app_type="$4" output_file="$5"
    local today; today="$(date +%F)"

    if [[ "$app_type" == "native" ]]; then
        cat > "$output_file" <<EOF
# $app_name

## Purpose

$description. Installed through Home Manager's native \`programs.$app_name\`
module; this module is the HWC adapter over it (Law 6).

## Boundaries

- ✅ Manages \`hwc.home.apps.$app_name.enable\` and delegates installation to \`programs.$app_name\`.
- ❌ Does not manage application state, credentials, or in-app settings.

## Structure

- \`index.nix\` — HWC enable option and native Home Manager integration.

## Changelog

- $today: Added the $app_name module (scaffolded by \`workspace/nixos-dev/add-home-app.sh\` v$VERSION).
EOF
    else
        cat > "$output_file" <<EOF
# $app_name

## Purpose

$description. One-package Home Manager app generated by the shared
\`domains/lib/mkSimpleApp.nix\` factory (Law 2: name = folder).

## Boundaries

- ✅ Manages: \`hwc.home.apps.$app_name.enable\` → \`pkgs.$package_attr\` on \`home.packages\`.
- ❌ Does not manage: $app_name configuration, keybinds, or MIME/default-application associations.

## Structure

- \`index.nix\` — mkSimpleApp call: name, description, package selector.

## Changelog

- $today: Added the $app_name module (scaffolded by \`workspace/nixos-dev/add-home-app.sh\` v$VERSION).
EOF
    fi
}

# domains/home/apps/README.md is the directory index: a fenced tree under
# ## Structure and a dated ## Changelog. Both get one line.
update_apps_readme() { # <app-name> <description>
    local app_name="$1" description="$2"
    local readme="$REPO_ROOT/domains/home/apps/README.md"
    local today; today="$(date +%F)"

    if [[ ! -f "$readme" ]]; then
        warn "No domains/home/apps/README.md to update"
        return 0
    fi

    local short="$description"
    [[ ${#short} -gt 60 ]] && short="${short:0:57}..."

    local tmp="$TEMP_DIR/apps_readme.md"
    awk -v app="$app_name" -v desc="$short" '
        !inserted && /^└── / {
            entry = "├── " app "/"
            pad = 21 - length(entry)
            if (pad < 2) pad = 2
            printf "%s%*s# %s\n", entry, pad, "", desc
            inserted = 1
        }
        { print }
        END { if (!inserted) exit 3 }
    ' "$readme" > "$tmp" || {
        warn "Could not find the tree terminator in domains/home/apps/README.md; Structure left alone"
        cp "$readme" "$tmp"
    }

    printf -- '- %s: Added %s — %s\n' "$today" "$app_name" "$short" >> "$tmp"
    cp "$tmp" "$readme"
    success "Updated domains/home/apps/README.md"
}

# The roles refactor deleted profiles/home.nix. Per-machine enables live in
# machines/<machine>/home.nix. Current files use either a grouped
# `hwc.home.apps = { ... }` block or direct `hwc.home.apps.<name>.enable`
# assignments; preserve whichever shape the target machine already uses.
enable_in_machine() { # <app-name> <machine-config-name>
    local app_name="$1" machine="$2"
    local dir; dir="$(machine_dir_for "$machine")"
    local target="$REPO_ROOT/machines/$dir/home.nix"

    if [[ ! -f "$target" ]]; then
        error "No machine home file at machines/$dir/home.nix"
        return 1
    fi

    if rg -q "^\s*$app_name\.enable\s*=" "$target" 2>/dev/null; then
        warn "$app_name is already enabled in machines/$dir/home.nix"
        return 0
    fi

    local backup="$TEMP_DIR/machine_home.nix.bak"
    cp "$target" "$backup"

    local tmp="$TEMP_DIR/machine_home.nix"
    if ! awk -v app="$app_name" '
        { print }
        !done && /^[[:space:]]*hwc\.home\.apps[[:space:]]*=[[:space:]]*\{[[:space:]]*$/ {
            printf "    %s.enable = true;\n", app; done = 1
        }
        END { if (!done) exit 3 }
    ' "$target" > "$tmp"; then
        if ! awk -v app="$app_name" '
            !done && /^}[[:space:]]*$/ {
                printf "  hwc.home.apps.%s.enable = true;\n", app; done = 1
            }
            { print }
            END { if (!done) exit 3 }
        ' "$target" > "$tmp"; then
            error "machines/$dir/home.nix has no supported app-enable insertion seam"
            return 1
        fi
    fi

    cp "$tmp" "$target"

    if command -v nix-instantiate >/dev/null 2>&1; then
        if ! nix-instantiate --parse "$target" >/dev/null 2>&1; then
            error "Edited machines/$dir/home.nix has invalid Nix syntax; reverting"
            cp "$backup" "$target"
            return 1
        fi
    fi

    success "Enabled $app_name in machines/$dir/home.nix"
    return 0
}

#==============================================================================
# THE INTEGRATION HUNK
#==============================================================================
# One function owns every write. Revert it to a stub and every generation case
# in tests/test-add-home-app.sh fails — that is the wiring proof. Keep it that
# way: writes that leak back out into main() make the suite pass on a tool that
# does nothing.

integrate_app() { # <app-name> <attr> <description> <app-type> <machine>
    local app_name="$1" package_attr="$2" description="$3" app_type="$4" machine="$5"
    local app_dir="$REPO_ROOT/domains/home/apps/$app_name"
    local apps_readme="$REPO_ROOT/domains/home/apps/README.md"
    local machine_dir; machine_dir="$(machine_dir_for "$machine")"
    local machine_home="$REPO_ROOT/machines/$machine_dir/home.nix"
    local apps_readme_backup="$TEMP_DIR/apps_readme.integration.bak"
    local machine_home_backup="$TEMP_DIR/machine_home.integration.bak"

    [[ -f "$apps_readme" ]] && cp "$apps_readme" "$apps_readme_backup"
    [[ -f "$machine_home" ]] && cp "$machine_home" "$machine_home_backup"

    mkdir -p "$app_dir" || { error "Failed to create $app_dir"; return 1; }

    generate_index_nix "$app_name" "$package_attr" "$description" "$app_type" \
        "$app_dir/index.nix" || { rm -rf "$app_dir"; return 1; }

    generate_app_readme "$app_name" "$package_attr" "$description" "$app_type" \
        "$app_dir/README.md" || { rm -rf "$app_dir"; return 1; }

    success "Created domains/home/apps/$app_name/{index.nix,README.md}"

    if ! update_apps_readme "$app_name" "$description" \
       || ! enable_in_machine "$app_name" "$machine"; then
        rm -rf "$app_dir"
        [[ -f "$apps_readme_backup" ]] && cp "$apps_readme_backup" "$apps_readme"
        [[ -f "$machine_home_backup" ]] && cp "$machine_home_backup" "$machine_home"
        error "Integration failed; rolled back generated and edited files"
        return 1
    fi
    return 0
}

#==============================================================================
# TESTING & VALIDATION
#==============================================================================

test_package_availability() {
    local package_attr="$1"
    log "Verifying '$package_attr' exists in the locked nixpkgs..."
    if ! "${NIX[@]}" eval --raw "$(nixpkgs_ref)#legacyPackages.$SYSTEM.$package_attr.name" \
            >/dev/null 2>&1; then
        error "'$package_attr' is not available in $(nixpkgs_ref) or fails to evaluate"
        return 1
    fi
    success "Package is available in the locked nixpkgs"
    return 0
}

test_configuration_quick() {
    local build_target="$1"
    log "Evaluating homeConfigurations.\"eric@$build_target\" ..."
    local flake_ref="path:$REPO_ROOT#homeConfigurations.\"eric@$build_target\".activationPackage"
    if "${NIX[@]}" eval --raw "$flake_ref.drvPath" >/dev/null 2>&1; then
        success "Home Manager configuration evaluates"
        return 0
    fi
    error "Home Manager configuration failed to evaluate"
    "${NIX[@]}" eval --raw "$flake_ref.drvPath" 2>&1 | tail -30 >&2 || true
    return 1
}

#==============================================================================
# GIT OPERATIONS
#==============================================================================

commit_changes() { # <app-name> <attr> <version> <description> <machine>
    local app_name="$1" package_attr="$2" package_version="$3"
    local package_description="$4" machine="$5"

    if [[ "$SKIP_COMMIT" == "true" ]]; then
        info "Skipping commit (--no-commit)"
        return 0
    fi

    local dir; dir="$(machine_dir_for "$machine")"

    # Only the paths this run produced. Never `git add -A`: an unrelated dirty
    # edit riding along in the module commit is how review loses the plot.
    local -a paths=(
        "domains/home/apps/$app_name"
        "domains/home/apps/README.md"
        "machines/$dir/home.nix"
    )

    log "Staging ${#paths[@]} generated paths..."
    if ! git -C "$REPO_ROOT" add -- "${paths[@]}"; then
        error "Failed to stage files for commit"
        return 1
    fi

    if git -C "$REPO_ROOT" diff --cached --quiet; then
        warn "Nothing staged; skipping commit"
        return 0
    fi

    local commit_msg="feat(home.apps.$app_name): add $app_name module

- domains/home/apps/$app_name/index.nix (options declared in index.nix, Law 10)
- domains/home/apps/$app_name/README.md (Law 12)
- Enabled in machines/$dir/home.nix

Package: $package_attr ($package_version)
Description: $package_description

Generated with add-home-app.sh v${VERSION}"

    if git -C "$REPO_ROOT" commit -m "$commit_msg" >&2; then
        success "Committed"
        return 0
    fi
    error "Failed to commit changes"
    return 1
}

#==============================================================================
# POST-INSTALLATION GUIDANCE
#==============================================================================

show_configuration_hints() {
    local app_name="$1" package_attr="$2" app_dir="$3" app_type="$4"

    echo >&2
    log "${CYAN}Configuration Guidance:${NC}"

    local homepage
    homepage=$("${NIX[@]}" eval --raw \
        "$(nixpkgs_ref)#legacyPackages.$SYSTEM.$package_attr.meta.homepage" 2>/dev/null || echo "")
    [[ -n "$homepage" && "$homepage" != "null" ]] && info "Homepage: $homepage"

    if [[ "$app_type" == "native" ]]; then
        info "Native module: programs.$app_name — options at"
        info "  https://nix-community.github.io/home-manager/options.xhtml"
    fi
    info "Module: $app_dir/index.nix"
    echo >&2
}

#==============================================================================
# MAIN WORKFLOW
#==============================================================================

main() {
    local package_query="${1:-}"

    cd "$REPO_ROOT" || die "$E_FAIL" "Failed to change to repo root: $REPO_ROOT"

    log "${CYAN}HWC Add Home App${NC} v${VERSION}"
    log "Repository: $REPO_ROOT"

    if [[ -z "$package_query" ]]; then
        if [[ "$SKIP_INTERACTIVE" == "true" ]]; then
            die "$E_USAGE" "--no-interactive requires a package name argument"
        fi
        echo -n "Enter package name to search for: " >&2
        read -r package_query
    fi
    [[ -z "$package_query" ]] && die "$E_USAGE" "Package name cannot be empty"

    local target_machine rc
    target_machine=$(detect_machine) || { rc=$?; exit "$rc"; }
    info "Target machine: $target_machine"

    local package_attr package_name package_version package_description

    if [[ "$SKIP_INTERACTIVE" == "true" ]]; then
        local exact_json
        exact_json=$(resolve_exact_match "$package_query") || { rc=$?; exit "$rc"; }
        extract_package_info "$exact_json" package_attr package_name \
            package_version package_description || exit "$E_FAIL"
    else
        local selection_file="$TEMP_DIR/selected_package.json"
        while true; do
            local search_file results_file select_result
            search_file=$(search_packages "$package_query") || exit "$E_FAIL"
            results_file=$(format_search_results "$search_file") || exit "$E_FAIL"

            if select_package "$results_file" "$selection_file"; then
                select_result=0
            else
                select_result=$?
            fi

            if [[ $select_result -eq 2 ]]; then
                echo -n "Enter new search term: " >&2
                read -r package_query
                [[ -z "$package_query" ]] && die "$E_USAGE" "Search term cannot be empty"
                continue
            elif [[ $select_result -ne 0 ]]; then
                exit "$E_FAIL"
            fi
            break
        done
        extract_package_info "$(cat "$selection_file")" package_attr package_name \
            package_version package_description || exit "$E_FAIL"
    fi

    success "Selected: $package_name ($package_version)"
    info "Description: $package_description"
    info "Attribute: $package_attr"

    test_package_availability "$package_attr" || exit "$E_FAIL"

    local app_name
    app_name=$(to_kebab_case "$package_name")

    local app_type
    if [[ "$TEMPLATE_TYPE" == "auto" ]]; then
        app_type=$(check_home_manager_support "$app_name")
    else
        app_type="$TEMPLATE_TYPE"
    fi
    info "App type: $app_type"
    if [[ "$app_type" == "native" ]]; then
        info "Home Manager has a native module: programs.$app_name"
    fi

    check_for_duplicates "$app_name" "$package_attr" || { rc=$?; exit "$rc"; }

    local machine_dir; machine_dir="$(machine_dir_for "$target_machine")"
    log "Module plan:"
    info "  Directory: domains/home/apps/$app_name"
    info "  Namespace: hwc.home.apps.$app_name"
    info "  Producer:  $([[ "$app_type" == native ]] \
        && echo "native adapter over programs.$app_name" \
        || echo "domains/lib/mkSimpleApp.nix")"
    info "  Enable in: machines/$machine_dir/home.nix"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN — no files written, no git state changed"
        exit 0
    fi

    if [[ "$SKIP_INTERACTIVE" != "true" ]]; then
        echo -n "Proceed with adding this package? (y/N): " >&2
        local confirm
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log "Cancelled by user"
            exit 0
        fi
    fi

    ensure_feature_worktree "$app_name" || { rc=$?; exit "$rc"; }
    cd "$REPO_ROOT" || die "$E_FAIL" "Failed to enter $REPO_ROOT"

    local app_dir="$REPO_ROOT/domains/home/apps/$app_name"
    if ! integrate_app "$app_name" "$package_attr" "$package_description" \
            "$app_type" "$target_machine"; then
        error "Integration failed; no scoped changes were kept"
        exit "$E_FAIL"
    fi

    if [[ "$SKIP_BUILD_TEST" != "true" ]]; then
        test_configuration_quick "$target_machine" || \
            warn "Evaluation failed — files are on disk for inspection, not reverted"
    fi

    commit_changes "$app_name" "$package_attr" "$package_version" \
        "$package_description" "$target_machine" || \
        warn "Failed to commit, but files are in working state"

    show_configuration_hints "$app_name" "$package_attr" "$app_dir" "$app_type"

    success "'$app_name' added"
    info "Next: review the module, then apply with"
    info "  hms                      # HM-only change (this is one)"
    echo >&2
}

#==============================================================================
# SCRIPT ENTRY POINT
#==============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)        DRY_RUN=true; shift ;;
            --no-commit)      SKIP_COMMIT=true; shift ;;
            --no-interactive) SKIP_INTERACTIVE=true; shift ;;
            --no-build-test)  SKIP_BUILD_TEST=true; shift ;;
            --machine)
                [[ -n "${2:-}" ]] || die "$E_USAGE" "--machine needs a value"
                MACHINE_OVERRIDE="$2"; shift 2 ;;
            --template)
                [[ -n "${2:-}" ]] || die "$E_USAGE" "--template needs a value"
                case "$2" in
                    auto|simple|native) TEMPLATE_TYPE="$2" ;;
                    *) die "$E_USAGE" "--template must be auto, simple or native (got '$2')" ;;
                esac
                shift 2 ;;
            --debug)          DEBUG=1; shift ;;
            -v|--version)     show_version; exit 0 ;;
            -h|--help)        show_help; exit 0 ;;
            -*)               error "Unknown option: $1"; echo "Use --help for usage" >&2; exit "$E_USAGE" ;;
            *)                break ;;
        esac
    done

    check_dependencies
    main "$@"
fi
