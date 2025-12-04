#!/usr/bin/env bash
set -euo pipefail

# Music Library Duplicate Detection Script
# Analyzes a music library for potential duplicates and issues
#
# Usage: music_duplicate_detector.sh [OPTIONS]
#
# Examples:
#   music_duplicate_detector.sh
#   music_duplicate_detector.sh --dir /path/to/music
#   music_duplicate_detector.sh --patterns "beatles,rolling stones,who"
#   music_duplicate_detector.sh --help

# Configuration (can be overridden by environment variables)
readonly DEFAULT_MUSIC_DIR="/mnt/media/music"
readonly DEFAULT_MIN_SIZE=$((1 * 1024 * 1024))  # 1MB
readonly DEFAULT_MAX_SPARSE_FILES=2
readonly DEFAULT_PATTERNS="giraffe,looking,ween,brian,beach,various"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging functions
log_header() { echo -e "\n${BOLD}${BLUE}=== $* ===${NC}"; }
log_info() { echo -e "${GREEN}$*${NC}"; }
log_warn() { echo -e "${YELLOW}$*${NC}"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Usage information
show_usage() {
    cat << EOF
${BOLD}Music Library Duplicate Detection Script${NC}

Analyzes a music library for potential duplicates and organizational issues.

${BOLD}USAGE:${NC}
    $(basename "$0") [OPTIONS]

${BOLD}OPTIONS:${NC}
    -d, --dir PATH              Music directory to analyze
                                (default: ${DEFAULT_MUSIC_DIR})
    -s, --min-size BYTES        Minimum size for duplicate detection
                                (default: ${DEFAULT_MIN_SIZE} bytes / 1MB)
    -m, --max-sparse FILES      Max files for "sparse folder" detection
                                (default: ${DEFAULT_MAX_SPARSE_FILES})
    -p, --patterns LIST         Comma-separated patterns to search
                                (default: ${DEFAULT_PATTERNS})
    -h, --help                  Show this help message

${BOLD}EXAMPLES:${NC}
    # Analyze default music directory
    $(basename "$0")

    # Analyze specific directory
    $(basename "$0") --dir /mnt/external/music

    # Custom patterns
    $(basename "$0") --patterns "beatles,stones,who,zeppelin"

    # Custom thresholds
    $(basename "$0") --min-size $((5 * 1024 * 1024)) --max-sparse 5

${BOLD}ENVIRONMENT VARIABLES:${NC}
    MUSIC_DIR           Override default music directory
    MIN_DUPLICATE_SIZE  Override minimum size for duplicates
    MAX_SPARSE_FILES    Override sparse folder threshold
    SEARCH_PATTERNS     Override search patterns

${BOLD}OUTPUT SECTIONS:${NC}
    1. Size-based duplicate detection
    2. Suspicious name patterns (case-insensitive matches)
    3. Specific pattern searches
    4. Empty or sparse folders
    5. Year-prefixed folders (potential misplaced albums)

EOF
}

# Parse command line arguments
parse_args() {
    MUSIC_DIR="${MUSIC_DIR:-$DEFAULT_MUSIC_DIR}"
    MIN_SIZE="${MIN_DUPLICATE_SIZE:-$DEFAULT_MIN_SIZE}"
    MAX_SPARSE="${MAX_SPARSE_FILES:-$DEFAULT_MAX_SPARSE_FILES}"
    PATTERNS="${SEARCH_PATTERNS:-$DEFAULT_PATTERNS}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dir)
                MUSIC_DIR="$2"
                shift 2
                ;;
            -s|--min-size)
                MIN_SIZE="$2"
                shift 2
                ;;
            -m|--max-sparse)
                MAX_SPARSE="$2"
                shift 2
                ;;
            -p|--patterns)
                PATTERNS="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_usage
                exit 2
                ;;
        esac
    done
}

# Validate configuration
validate_config() {
    if [[ ! -d "$MUSIC_DIR" ]]; then
        log_error "Music directory not found: $MUSIC_DIR"
        echo ""
        echo "Please specify a valid directory with --dir or set MUSIC_DIR environment variable"
        exit 1
    fi

    if [[ ! -r "$MUSIC_DIR" ]]; then
        log_error "Cannot read music directory: $MUSIC_DIR"
        echo "Check permissions and try again"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in find awk du tr sed grep basename wc sort uniq; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# Analysis 1: Size-based duplicate detection
analyze_size_duplicates() {
    log_header "1. SIZE-BASED DUPLICATE DETECTION"
    echo "Finding folders with identical sizes (min size: $((MIN_SIZE / 1024 / 1024))MB)..."

    local found_duplicates=false

    find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -type d -exec du -sb {} \; 2>/dev/null | \
        sort -n -k1,1 | \
        awk -v min_size="$MIN_SIZE" '
        {
            size = $1
            $1 = ""
            path = substr($0, 2)
            if (size == prev_size && size > min_size) {
                if (!shown[prev_size]) {
                    printf "\n%s SIZE: %s bytes (%.2f MB)\n", "'"${YELLOW}"'", prev_size, prev_size/(1024*1024)
                    printf "%s  %s%s\n", "'"${NC}"'", prev_path, "'"${NC}"'"
                    shown[prev_size] = 1
                }
                printf "  %s\n", path
            }
            prev_size = size
            prev_path = path
        }
        END {
            if (length(shown) == 0) {
                printf "%sNo size-based duplicates found%s\n", "'"${GREEN}"'", "'"${NC}"'"
            }
        }
        '
}

# Analysis 2: Suspicious name patterns
analyze_name_patterns() {
    log_header "2. SUSPICIOUS NAME PATTERNS"
    echo "Finding artists with similar names (case-insensitive)..."

    local found_similar=false
    local output

    output=$(ls -1 "$MUSIC_DIR" 2>/dev/null | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]//g' | \
        sort | \
        uniq -c | \
        sort -nr | \
        awk '$1 > 1 {print "SIMILAR: " $1 " matches - " $2}')

    if [[ -n "$output" ]]; then
        echo "$output"
    else
        log_info "No suspicious name patterns found"
    fi
}

# Analysis 3: Specific pattern searches
analyze_patterns() {
    log_header "3. SPECIFIC DUPLICATE CANDIDATES"
    echo "Searching for patterns: $PATTERNS"

    # Convert comma-separated patterns to array
    local -a pattern_array
    IFS=',' read -ra pattern_array <<< "$PATTERNS"

    local total_found=0

    for pattern in "${pattern_array[@]}"; do
        # Trim whitespace
        pattern=$(echo "$pattern" | xargs)

        echo ""
        echo "PATTERN: ${YELLOW}${pattern}${NC}"

        local found_count=0
        while IFS= read -r -d '' dir; do
            if [[ -d "$dir" ]]; then
                local name
                name=$(basename "$dir")
                local files
                files=$(find "$dir" \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" \) 2>/dev/null | wc -l)
                local size
                size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                echo "  $name: $files files, $size"
                ((found_count++))
                ((total_found++))
            fi
        done < <(find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -iname "*${pattern}*" -type d -print0 2>/dev/null)

        if [[ $found_count -eq 0 ]]; then
            echo "  (no matches)"
        fi
    done

    if [[ $total_found -eq 0 ]]; then
        log_info "No pattern matches found"
    fi
}

# Analysis 4: Empty or sparse folders
analyze_sparse_folders() {
    log_header "4. EMPTY OR SPARSE FOLDERS"
    echo "Finding folders with 0-${MAX_SPARSE} music files..."

    local sparse_count=0

    while IFS= read -r -d '' dir; do
        if [[ -d "$dir" ]]; then
            local name
            name=$(basename "$dir")
            local files
            files=$(find "$dir" \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.wav" \) 2>/dev/null | wc -l)

            if [[ $files -le $MAX_SPARSE ]]; then
                local size
                size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                echo "  ${YELLOW}$name${NC}: $files files, $size"
                ((sparse_count++))
            fi
        fi
    done < <(find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    if [[ $sparse_count -eq 0 ]]; then
        log_info "No sparse folders found"
    else
        log_warn "Found $sparse_count sparse folders"
    fi
}

# Analysis 5: Year-prefixed folders
analyze_year_folders() {
    log_header "5. YEAR-PREFIXED FOLDERS"
    echo "Finding folders starting with years (potential misplaced albums)..."

    local output
    output=$(ls -1 "$MUSIC_DIR" 2>/dev/null | grep "^[0-9][0-9][0-9][0-9]" || true)

    if [[ -n "$output" ]]; then
        echo "$output" | while IFS= read -r folder; do
            echo "  ${YELLOW}${folder}${NC}"
        done
    else
        log_info "No year-prefixed folders found"
    fi
}

# Generate summary
show_summary() {
    log_header "ANALYSIS COMPLETE"

    local total_folders
    total_folders=$(find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

    echo ""
    echo "${BOLD}Summary:${NC}"
    echo "  Music Directory: $MUSIC_DIR"
    echo "  Total Artists/Folders: $total_folders"
    echo "  Minimum Duplicate Size: $((MIN_SIZE / 1024 / 1024))MB"
    echo "  Sparse Folder Threshold: $MAX_SPARSE files"
    echo ""
    echo "Review the output above for potential duplicates and organizational issues."
    echo ""
    log_info "✓ Analysis complete"
}

# Main function
main() {
    # Parse arguments
    parse_args "$@"

    # Validate configuration
    validate_config

    # Check dependencies
    check_dependencies

    # Show header
    echo ""
    log_header "MUSIC LIBRARY DUPLICATE ANALYSIS"
    echo "Analyzing: ${BLUE}${MUSIC_DIR}${NC}"

    # Run analyses
    analyze_size_duplicates
    analyze_name_patterns
    analyze_patterns
    analyze_sparse_folders
    analyze_year_folders

    # Show summary
    show_summary

    exit 0
}

# Execute main function
main "$@"
