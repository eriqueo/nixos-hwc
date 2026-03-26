#!/usr/bin/env bash
#
# photo-dedup - Interactive photo deduplication tool
#
# Finds and quarantines duplicate photos before adding to Immich.
# Uses rmlint (exact duplicates) and czkawka (similar images).
#
# Usage: photo-dedup [directory]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Defaults
DEFAULT_SIMILARITY="High"
DEFAULT_IMMICH_LIBRARY="/mnt/media/photos/archive"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/photo-dedup"

#=============================================================================
# Helper Functions
#=============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}  ${BOLD}photo-dedup${NC} - Photo Deduplication Tool                    ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_step() {
    echo -e "\n${BOLD}${CYAN}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local yn

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -rp "$prompt" yn
    yn="${yn:-$default}"

    [[ "$yn" =~ ^[Yy] ]]
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local value

    read -rp "$prompt [$default]: " value
    echo "${value:-$default}"
}

check_dependencies() {
    local missing=()

    command -v rmlint >/dev/null 2>&1 || missing+=("rmlint")
    command -v czkawka_cli >/dev/null 2>&1 || missing+=("czkawka")
    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo "Install with: nix-shell -p ${missing[*]}"
        exit 1
    fi
}

format_size() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    else
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    fi
}

#=============================================================================
# Main Functions
#=============================================================================

scan_directory() {
    local dir="$1"

    print_step "Scanning directory..."

    local file_count=$(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.raw" -o -iname "*.cr2" -o -iname "*.nef" -o -iname "*.arw" \) 2>/dev/null | wc -l)
    local total_size=$(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.raw" -o -iname "*.cr2" -o -iname "*.nef" -o -iname "*.arw" \) -exec stat --printf="%s\n" {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
    total_size="${total_size:-0}"

    echo "  Photos found: $file_count"
    echo "  Total size:   $(format_size "$total_size")"

    if [[ $file_count -eq 0 ]]; then
        print_warning "No photos found in directory!"
        exit 0
    fi
}

run_exact_dedup() {
    local source_dir="$1"
    local quarantine_dir="$2"
    local report_dir="$3"

    print_step "Phase 1: Finding exact duplicates (rmlint)..."

    mkdir -p "$quarantine_dir/exact"

    # Run rmlint
    rmlint "$source_dir" \
        --types duplicates \
        --output json:"$report_dir/exact-duplicates.json" \
        --output summary:"$report_dir/exact-summary.txt" \
        --output sh:"$report_dir/exact-remove.sh" \
        --no-followlinks \
        --hidden \
        2>/dev/null || true

    # Count duplicates
    if [[ -f "$report_dir/exact-duplicates.json" ]]; then
        local dup_count=$(jq '[.[] | select(.type == "duplicate_file")] | length' "$report_dir/exact-duplicates.json" 2>/dev/null || echo "0")
        local dup_size=$(jq '[.[] | select(.type == "duplicate_file")] | map(.size) | add // 0' "$report_dir/exact-duplicates.json" 2>/dev/null || echo "0")

        if [[ "$dup_count" -gt 0 ]]; then
            print_success "Found $dup_count exact duplicates ($(format_size "$dup_size"))"
            return 0
        fi
    fi

    print_success "No exact duplicates found"
    return 1
}

run_similar_dedup() {
    local source_dir="$1"
    local quarantine_dir="$2"
    local report_dir="$3"
    local similarity="$4"
    local reference_dirs=("${@:5}")

    print_step "Phase 2: Finding similar images (czkawka)..."

    mkdir -p "$quarantine_dir/similar"

    # Build reference args
    local ref_args=()
    for ref in "${reference_dirs[@]}"; do
        if [[ -n "$ref" && -d "$ref" ]]; then
            ref_args+=("-r" "$ref")
        fi
    done

    # Run czkawka
    czkawka_cli image \
        -d "$source_dir" \
        "${ref_args[@]}" \
        -s "$similarity" \
        -g Gradient \
        -c 16 \
        -p "$report_dir/similar-images.json" \
        2>/dev/null || true

    # Count similar images
    if [[ -f "$report_dir/similar-images.json" ]]; then
        local group_count=$(jq 'length' "$report_dir/similar-images.json" 2>/dev/null || echo "0")

        if [[ "$group_count" -gt 0 ]]; then
            print_success "Found $group_count groups of similar images"
            return 0
        fi
    fi

    print_success "No similar images found"
    return 1
}

quarantine_duplicates() {
    local source_dir="$1"
    local quarantine_dir="$2"
    local report_dir="$3"

    print_step "Quarantining duplicates..."

    local moved=0

    # Process exact duplicates
    if [[ -f "$report_dir/exact-duplicates.json" ]]; then
        # Move duplicate files (keep originals - filter by is_original == false)
        jq -r '.[] | select(.type == "duplicate_file" and .is_original == false) | .path' "$report_dir/exact-duplicates.json" 2>/dev/null | while read -r file; do
            if [[ -f "$file" ]]; then
                local rel_path="${file#$source_dir/}"
                local dest="$quarantine_dir/exact/$rel_path"
                mkdir -p "$(dirname "$dest")"
                mv "$file" "$dest" 2>/dev/null && ((moved++)) || true
            fi
        done
    fi

    # Process similar images - move all but first in each group
    if [[ -f "$report_dir/similar-images.json" ]]; then
        jq -r '.[] | .[1:][] | .path' "$report_dir/similar-images.json" 2>/dev/null | while read -r file; do
            if [[ -f "$file" ]]; then
                local rel_path="${file#$source_dir/}"
                local dest="$quarantine_dir/similar/$rel_path"
                mkdir -p "$(dirname "$dest")"
                mv "$file" "$dest" 2>/dev/null && ((moved++)) || true
            fi
        done
    fi

    print_success "Moved duplicates to: $quarantine_dir"
}

generate_report() {
    local source_dir="$1"
    local quarantine_dir="$2"
    local report_dir="$3"

    print_step "Generating report..."

    local report_file="$report_dir/dedup-report.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║           Photo Deduplication Report                       ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Timestamp:    $timestamp"
        echo "Source:       $source_dir"
        echo "Quarantine:   $quarantine_dir"
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo "EXACT DUPLICATES"
        echo "────────────────────────────────────────────────────────────────"

        if [[ -f "$report_dir/exact-duplicates.json" ]]; then
            local exact_count=$(jq '[.[] | select(.type == "duplicate_file")] | length' "$report_dir/exact-duplicates.json" 2>/dev/null || echo "0")
            local exact_size=$(jq '[.[] | select(.type == "duplicate_file")] | map(.size) | add // 0' "$report_dir/exact-duplicates.json" 2>/dev/null || echo "0")
            echo "Files:        $exact_count"
            echo "Space saved:  $(format_size "$exact_size")"
        else
            echo "Files:        0"
        fi

        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo "SIMILAR IMAGES"
        echo "────────────────────────────────────────────────────────────────"

        if [[ -f "$report_dir/similar-images.json" ]]; then
            local similar_groups=$(jq 'length' "$report_dir/similar-images.json" 2>/dev/null || echo "0")
            echo "Groups:       $similar_groups"
        else
            echo "Groups:       0"
        fi

        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo "NEXT STEPS"
        echo "────────────────────────────────────────────────────────────────"
        echo "1. Review quarantined files in: $quarantine_dir"
        echo "2. Delete quarantine when satisfied: rm -rf $quarantine_dir"
        echo "3. Add source directory as Immich external library"
        echo ""
    } > "$report_file"

    print_success "Report saved: $report_file"
}

print_summary() {
    local quarantine_dir="$1"

    echo -e "\n${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}Deduplication Complete${NC}                                    ${BOLD}${GREEN}║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"

    if [[ -d "$quarantine_dir" ]]; then
        local q_count=$(find "$quarantine_dir" -type f 2>/dev/null | wc -l)
        local q_size=$(du -sb "$quarantine_dir" 2>/dev/null | cut -f1)
        q_size="${q_size:-0}"

        echo -e "  ${BOLD}Quarantined:${NC} $q_count files ($(format_size "$q_size"))"
        echo -e "  ${BOLD}Location:${NC}    $quarantine_dir"
        echo ""
        echo -e "  ${YELLOW}Review the quarantined files, then:${NC}"
        echo -e "  • Keep originals:  ${CYAN}rm -rf \"$quarantine_dir\"${NC}"
        echo -e "  • Restore all:     ${CYAN}mv \"$quarantine_dir\"/* /path/to/source/${NC}"
    else
        echo -e "  ${GREEN}No duplicates found!${NC}"
    fi
    echo ""
}

#=============================================================================
# Main
#=============================================================================

show_help() {
    echo "photo-dedup - Interactive photo deduplication tool"
    echo ""
    echo "Usage: photo-dedup [directory]"
    echo ""
    echo "Finds and quarantines duplicate photos before adding to Immich."
    echo "Uses rmlint (exact duplicates) and czkawka (similar images)."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  photo-dedup                        # Interactive mode"
    echo "  photo-dedup /mnt/media/old-photos  # Specify directory"
    echo ""
    echo "See: ~/.nixos/workspace/utilities/photo-dedup/README.md"
}

main() {
    # Handle help
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi

    print_header
    check_dependencies

    # Get source directory
    local source_dir="${1:-}"

    if [[ -z "$source_dir" ]]; then
        echo -e "${BOLD}Enter the directory to deduplicate:${NC}"
        read -rp "> " source_dir
    fi

    # Validate directory
    if [[ ! -d "$source_dir" ]]; then
        print_error "Directory not found: $source_dir"
        exit 1
    fi

    source_dir=$(realpath "$source_dir")
    echo -e "\n${BOLD}Source directory:${NC} $source_dir"

    # Scan directory
    scan_directory "$source_dir"

    # Ask about reference directories (existing Immich library)
    echo ""
    local reference_dirs=()
    if prompt_yes_no "Check against existing Immich library?" "y"; then
        local immich_lib=$(prompt_input "Immich library path" "$DEFAULT_IMMICH_LIBRARY")
        if [[ -d "$immich_lib" ]]; then
            reference_dirs+=("$immich_lib")
            print_success "Will check against: $immich_lib"
        else
            print_warning "Directory not found, skipping reference check"
        fi
    fi

    # Ask about additional reference directories
    while prompt_yes_no "Add another reference directory?" "n"; do
        read -rp "Path: " extra_ref
        if [[ -d "$extra_ref" ]]; then
            reference_dirs+=("$extra_ref")
            print_success "Added: $extra_ref"
        else
            print_warning "Directory not found: $extra_ref"
        fi
    done

    # Similarity threshold
    echo ""
    echo -e "${BOLD}Similarity threshold for image matching:${NC}"
    echo "  1) VeryHigh - Only nearly identical (safest)"
    echo "  2) High     - Good balance (recommended)"
    echo "  3) Medium   - Catches more, may have false positives"
    echo "  4) Low      - Aggressive, review carefully"
    local sim_choice=$(prompt_input "Choice" "2")

    local similarity
    case "$sim_choice" in
        1) similarity="VeryHigh" ;;
        3) similarity="Medium" ;;
        4) similarity="Low" ;;
        *) similarity="High" ;;
    esac

    # Setup directories
    local timestamp=$(date '+%Y-%m-%d_%H%M%S')
    local quarantine_dir="$source_dir/.duplicates/$timestamp"
    local report_dir="$source_dir/.dedup-reports/$timestamp"
    mkdir -p "$quarantine_dir" "$report_dir"

    # Confirm
    echo ""
    echo -e "${BOLD}Ready to scan:${NC}"
    echo "  Source:      $source_dir"
    echo "  Similarity:  $similarity"
    echo "  References:  ${reference_dirs[*]:-none}"
    echo "  Quarantine:  $quarantine_dir"
    echo ""

    if ! prompt_yes_no "Proceed with deduplication?" "y"; then
        echo "Aborted."
        exit 0
    fi

    # Run deduplication
    local has_exact=false
    local has_similar=false

    run_exact_dedup "$source_dir" "$quarantine_dir" "$report_dir" && has_exact=true
    run_similar_dedup "$source_dir" "$quarantine_dir" "$report_dir" "$similarity" "${reference_dirs[@]}" && has_similar=true

    # Quarantine if duplicates found
    if [[ "$has_exact" == "true" || "$has_similar" == "true" ]]; then
        echo ""
        if prompt_yes_no "Move duplicates to quarantine?" "y"; then
            quarantine_duplicates "$source_dir" "$quarantine_dir" "$report_dir"
        else
            print_warning "Duplicates left in place. Review reports in: $report_dir"
        fi
    else
        # Clean up empty quarantine
        rmdir "$quarantine_dir" 2>/dev/null || true
        rmdir "$source_dir/.duplicates" 2>/dev/null || true
    fi

    # Generate report
    generate_report "$source_dir" "$quarantine_dir" "$report_dir"

    # Summary
    print_summary "$quarantine_dir"
}

main "$@"
