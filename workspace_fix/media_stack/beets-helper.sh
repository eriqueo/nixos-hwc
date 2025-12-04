#!/usr/bin/env bash
# Beets Music Library Helper Script
# Comprehensive automation for managing music with beets
#
# Usage:
#   ./beets-helper.sh find-duplicates        # Find duplicate tracks
#   ./beets-helper.sh clean-duplicates       # Interactive duplicate removal
#   ./beets-helper.sh analyze-library        # Analyze library health
#   ./beets-helper.sh fix-missing-art        # Download missing album art
#   ./beets-helper.sh normalize-tags         # Standardize all metadata
#   ./beets-helper.sh find-missing-tracks    # Find incomplete albums

set -euo pipefail

# Configuration
BEETS_CONFIG="${BEETS_CONFIG:-/opt/downloads/beets/config.yaml}"
MUSIC_DIR="${MUSIC_DIR:-/mnt/media/music}"
BEETS_DB="${BEETS_DB:-/opt/downloads/beets/beets-library.db}"
LOG_DIR="/var/log/beets-automation"
LOG_FILE="$LOG_DIR/beets-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Statistics
STATS_DUPLICATES=0
STATS_MISSING_ART=0
STATS_FIXED=0
STATS_ERRORS=0

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

info() {
  echo -e "${BLUE}ℹ${NC} $*"
  log "INFO: $*"
}

success() {
  echo -e "${GREEN}✅${NC} $*"
  log "SUCCESS: $*"
}

warning() {
  echo -e "${YELLOW}⚠️${NC}  $*"
  log "WARNING: $*"
}

error() {
  echo -e "${RED}❌${NC} $*"
  log "ERROR: $*"
}

# Check if beets is available
check_beets() {
  if ! command -v beet &> /dev/null; then
    error "beets not found. Install with: nix-shell -p beets"
    error "Or run inside the beets container"
    exit 1
  fi
}

# Find duplicate tracks
find_duplicates() {
  info "Searching for duplicate tracks..."
  echo ""

  local dup_file="/tmp/beets-duplicates-$$.txt"

  # Use beets duplicates plugin
  beet duplicates -f '$albumartist - $album - $title' > "$dup_file" 2>&1 || true

  local dup_count=$(wc -l < "$dup_file")

  if [ "$dup_count" -eq 0 ]; then
    success "No duplicates found!"
    rm -f "$dup_file"
    return 0
  fi

  echo "Found duplicates:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$dup_file"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  warning "Found $dup_count duplicate groups"
  echo ""
  echo "Actions:"
  echo "  1. Review duplicates above"
  echo "  2. Run './beets-helper.sh clean-duplicates' for interactive removal"
  echo "  3. Or manually remove with: beet remove <query>"
  echo ""

  STATS_DUPLICATES=$dup_count
  rm -f "$dup_file"
}

# Interactive duplicate cleaning
clean_duplicates() {
  info "Starting interactive duplicate removal..."
  echo ""
  warning "This will guide you through removing duplicates"
  echo ""

  # Get duplicates with full details
  local temp_dir="/tmp/beets-dup-clean-$$"
  mkdir -p "$temp_dir"

  # Find duplicates by checksum (most accurate)
  info "Computing checksums (this may take a while)..."
  beet duplicates -k > "$temp_dir/dup-list.txt" 2>&1 || true

  if [ ! -s "$temp_dir/dup-list.txt" ]; then
    success "No duplicates found!"
    rm -rf "$temp_dir"
    return 0
  fi

  echo ""
  info "Found duplicates. For each group:"
  echo "  1. You'll see all versions"
  echo "  2. Choose which to KEEP (others will be removed)"
  echo "  3. Or skip the group"
  echo ""

  # Process duplicates interactively
  local current_group=1
  local total_removed=0

  while IFS= read -r line; do
    if [ -z "$line" ]; then
      ((current_group++))
      continue
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Duplicate Group #$current_group:"
    echo "$line"
    echo ""

    # Show file details
    beet list -p "$line" 2>/dev/null | while read -r path; do
      if [ -f "$path" ]; then
        local size=$(du -h "$path" | cut -f1)
        local format=$(file -b "$path" | cut -d',' -f1)
        local bitrate=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$path" 2>/dev/null || echo "unknown")
        echo "  File: $path"
        echo "    Size: $size | Format: $format | Bitrate: $bitrate bps"
      fi
    done

    echo ""
    read -p "Action: [k]eep best quality, [s]kip group, [r]emove all, [q]uit: " action

    case "$action" in
      k|K)
        # Keep highest quality, remove others
        info "Keeping highest quality version..."
        # This would need more logic to determine best quality
        warning "Manual selection recommended for now"
        ;;
      s|S)
        info "Skipping group..."
        ;;
      r|R)
        warning "Removing ALL duplicates in this group..."
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
          beet remove -d "$line" && ((total_removed++))
        fi
        ;;
      q|Q)
        info "Exiting..."
        break
        ;;
      *)
        warning "Invalid choice, skipping..."
        ;;
    esac

    echo ""
  done < "$temp_dir/dup-list.txt"

  echo ""
  success "Duplicate cleaning complete!"
  echo "  Groups reviewed: $current_group"
  echo "  Items removed: $total_removed"

  rm -rf "$temp_dir"
}

# Analyze library health
analyze_library() {
  info "Analyzing music library health..."
  echo ""

  local report_file="/tmp/beets-analysis-$$.txt"

  {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "BEETS LIBRARY ANALYSIS REPORT"
    echo "Generated: $(date)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Total counts
    echo "📊 Library Statistics:"
    echo "  Total tracks:  $(beet stats -e | grep 'Total tracks' | awk '{print $3}')"
    echo "  Total albums:  $(beet stats -e | grep 'Total albums' | awk '{print $3}')"
    echo "  Total artists: $(beet stats -e | grep 'Total artists' | awk '{print $3}')"
    echo "  Total time:    $(beet stats -e | grep 'Total time' | cut -d':' -f2-)"
    echo "  Total size:    $(beet stats -e | grep 'Total size' | cut -d':' -f2-)"
    echo ""

    # Missing album art
    echo "🎨 Album Art Status:"
    local no_art=$(beet ls -a artpath:: 2>/dev/null | wc -l)
    echo "  Albums missing art: $no_art"
    STATS_MISSING_ART=$no_art
    echo ""

    # Format breakdown
    echo "🎵 Format Distribution:"
    beet ls -f '$format' | sort | uniq -c | sort -rn
    echo ""

    # Duplicates
    echo "🔍 Duplicate Detection:"
    local dup_count=$(beet duplicates 2>/dev/null | wc -l)
    echo "  Potential duplicates: $dup_count"
    STATS_DUPLICATES=$dup_count
    echo ""

    # Missing tracks in albums
    echo "📀 Album Completeness:"
    local incomplete=$(beet missing -a 2>/dev/null | wc -l)
    echo "  Incomplete albums: $incomplete"
    echo ""

    # Unmatched items
    echo "❓ Unmatched Items:"
    local unmatched=$(beet ls mb_albumid:: 2>/dev/null | wc -l)
    echo "  Tracks without MusicBrainz ID: $unmatched"
    echo ""

    # Quality issues
    echo "⚠️  Quality Issues:"
    echo "  Low bitrate MP3s (<192kbps):"
    beet ls format:MP3 bitrate:..192000 2>/dev/null | wc -l
    echo ""

    # Recently added
    echo "📥 Recent Additions (last 7 days):"
    beet ls -a added:-7d.. 2>/dev/null | head -10
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💡 Recommendations:"
    if [ $STATS_MISSING_ART -gt 0 ]; then
      echo "  • Run './beets-helper.sh fix-missing-art' to download album art"
    fi
    if [ $STATS_DUPLICATES -gt 0 ]; then
      echo "  • Run './beets-helper.sh find-duplicates' to review duplicates"
    fi
    if [ $unmatched -gt 0 ]; then
      echo "  • Run 'beet import -L' to match unmatched tracks"
    fi
    echo ""

  } | tee "$report_file"

  info "Full report saved to: $report_file"
}

# Fix missing album art
fix_missing_art() {
  info "Downloading missing album art..."
  echo ""

  # Find albums without art
  local albums_without_art=$(beet ls -a artpath:: 2>/dev/null)

  if [ -z "$albums_without_art" ]; then
    success "All albums have artwork!"
    return 0
  fi

  local count=$(echo "$albums_without_art" | wc -l)
  warning "Found $count albums without artwork"
  echo ""

  read -p "Download artwork for all albums? (yes/no): " confirm

  if [ "$confirm" != "yes" ]; then
    info "Cancelled by user"
    return 0
  fi

  info "Fetching artwork..."
  beet fetchart -q

  info "Embedding artwork into files..."
  beet embedart -q

  success "Album art updated!"
}

# Normalize/standardize tags
normalize_tags() {
  info "Normalizing metadata tags..."
  echo ""

  warning "This will:"
  echo "  • Scrub unnecessary metadata"
  echo "  • Standardize tag formats"
  echo "  • Write updated tags to files"
  echo ""

  read -p "Continue? (yes/no): " confirm

  if [ "$confirm" != "yes" ]; then
    info "Cancelled"
    return 0
  fi

  info "Scrubbing metadata..."
  beet scrub

  info "Writing tags..."
  beet write

  success "Tags normalized!"
}

# Find missing tracks in albums
find_missing_tracks() {
  info "Checking for incomplete albums..."
  echo ""

  local missing_file="/tmp/beets-missing-$$.txt"

  beet missing -a > "$missing_file" 2>&1 || true

  if [ ! -s "$missing_file" ]; then
    success "All albums complete!"
    rm -f "$missing_file"
    return 0
  fi

  echo "Incomplete Albums:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$missing_file"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local count=$(grep -c "^#" "$missing_file" || true)
  warning "Found $count incomplete albums"

  rm -f "$missing_file"
}

# Import new music
import_music() {
  local source_dir="${1:-}"

  if [ -z "$source_dir" ]; then
    error "Usage: $0 import <source_directory>"
    exit 1
  fi

  if [ ! -d "$source_dir" ]; then
    error "Directory not found: $source_dir"
    exit 1
  fi

  info "Importing music from: $source_dir"
  echo ""
  warning "This will:"
  echo "  • Move files from source to music library"
  echo "  • Match against MusicBrainz"
  echo "  • Organize according to beets config"
  echo "  • Fetch and embed album art"
  echo ""

  read -p "Continue? (yes/no): " confirm

  if [ "$confirm" != "yes" ]; then
    info "Cancelled"
    return 0
  fi

  info "Starting import..."
  beet import "$source_dir"

  success "Import complete!"
}

# Show usage
usage() {
  cat <<EOF
Beets Music Library Helper

USAGE:
  $0 <command> [options]

COMMANDS:
  analyze-library       Comprehensive library health analysis
  find-duplicates       Find duplicate tracks in library
  clean-duplicates      Interactive duplicate removal
  fix-missing-art       Download and embed missing album artwork
  normalize-tags        Standardize metadata tags
  find-missing-tracks   Find incomplete albums
  import <dir>          Import music from directory

EXAMPLES:
  # Analyze your library
  $0 analyze-library

  # Find duplicates
  $0 find-duplicates

  # Clean up duplicates interactively
  $0 clean-duplicates

  # Fix missing album art
  $0 fix-missing-art

  # Import new music
  $0 import /mnt/hot/manual/music/

NOTES:
  - Log files saved to: $LOG_DIR/
  - Beets config: $BEETS_CONFIG
  - Music library: $MUSIC_DIR

EOF
}

# Main command dispatcher
main() {
  local command="${1:-}"

  if [ -z "$command" ]; then
    usage
    exit 1
  fi

  check_beets

  info "Beets Helper - Starting: $command"
  info "Log: $LOG_FILE"
  echo ""

  case "$command" in
    analyze-library|analyze)
      analyze_library
      ;;
    find-duplicates|dupes|duplicates)
      find_duplicates
      ;;
    clean-duplicates|clean-dupes)
      clean_duplicates
      ;;
    fix-missing-art|fetchart|art)
      fix_missing_art
      ;;
    normalize-tags|normalize|scrub)
      normalize_tags
      ;;
    find-missing-tracks|missing)
      find_missing_tracks
      ;;
    import)
      import_music "${2:-}"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      error "Unknown command: $command"
      echo ""
      usage
      exit 1
      ;;
  esac

  echo ""
  info "Command completed: $command"
}

# Run main
main "$@"
