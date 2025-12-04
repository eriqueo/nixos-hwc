#!/usr/bin/env bash
# Media File Organization Script
# Based on AUTOMATION_RULES.md for nixos-hwc media server
#
# This script helps organize media files from /mnt/hot to /mnt/media
# following strict safety rules and naming conventions for *arr compatibility.
#
# Usage:
#   ./media-organizer.sh analyze /mnt/hot/manual/movies
#   ./media-organizer.sh organize /mnt/hot/manual/movies --dry-run
#   ./media-organizer.sh organize /mnt/hot/manual/movies --execute

set -euo pipefail

# Configuration
LOG_DIR="/var/log/media-automation"
LOG_FILE="$LOG_DIR/organize-$(date +%Y%m%d-%H%M%S).log"
CHECKSUM_FILE="/tmp/media-checksums-$$.txt"
HOT_ROOT="/mnt/hot"
MEDIA_ROOT="/mnt/media"
QUARANTINE_ROOT="$HOT_ROOT/quarantine"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Statistics
STATS_SUCCESS=0
STATS_FAILED=0
STATS_QUARANTINED=0
STATS_SKIPPED=0

# Ensure log directory exists
mkdir -p "$LOG_DIR"
mkdir -p "$QUARANTINE_ROOT"/{movies,tv,music}/{ambiguous,missing-metadata,corrupted}

# Logging function
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Colored output functions
info() {
  echo -e "${BLUE}ℹ${NC} $*"
  log "INFO" "$*"
}

success() {
  echo -e "${GREEN}✅${NC} $*"
  log "SUCCESS" "$*"
  ((STATS_SUCCESS++))
}

warning() {
  echo -e "${YELLOW}⚠️${NC}  $*"
  log "WARNING" "$*"
  ((STATS_SKIPPED++))
}

error() {
  echo -e "${RED}❌${NC} $*"
  log "ERROR" "$*"
  ((STATS_FAILED++))
}

# Check dependencies
check_dependencies() {
  local missing=()

  for cmd in rsync sha256sum jq curl mediainfo; do
    if ! command -v "$cmd" &> /dev/null; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing dependencies: ${missing[*]}"
    error "Install with: nix-shell -p rsync jq curl mediainfo"
    exit 1
  fi
}

# Check storage health
check_storage() {
  local hot_usage=$(df "$HOT_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
  local media_usage=$(df "$MEDIA_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')

  info "Storage status:"
  echo "  Hot storage:   $hot_usage% used"
  echo "  Media storage: $media_usage% used"

  if [ "$hot_usage" -gt 80 ] || [ "$media_usage" -gt 80 ]; then
    warning "Storage >80% - recommend cleanup before processing"
    return 1
  fi

  return 0
}

# Detect media type from file
detect_media_type() {
  local file="$1"
  local ext="${file##*.}"

  case "$ext" in
    mkv|mp4|avi|m4v|mov|wmv|flv|webm)
      # Video file - need to determine if movie or TV
      if echo "$file" | grep -qiE '[Ss][0-9]{2}[Ee][0-9]{2}'; then
        echo "tv"
      else
        echo "movie"
      fi
      ;;
    flac|mp3|m4a|opus|ogg|wav|aac)
      echo "music"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Clean filename (remove special characters, normalize spaces)
clean_filename() {
  local name="$1"

  # Remove filesystem-unsafe characters
  name=$(echo "$name" | sed 's/[?:\\/*"<>|]//g')

  # Replace dots with spaces (except last one for extension)
  name=$(echo "$name" | sed 's/\./ /g' | sed 's/ \([^. ]*\)$/.\1/')

  # Replace underscores with spaces
  name=$(echo "$name" | sed 's/_/ /g')

  # Collapse multiple spaces
  name=$(echo "$name" | sed 's/  */ /g')

  # Trim leading/trailing spaces
  name=$(echo "$name" | sed 's/^ *//;s/ *$//')

  echo "$name"
}

# Extract year from string
extract_year() {
  local str="$1"

  # Look for 4-digit year (1900-2099)
  if echo "$str" | grep -oE '\b(19|20)[0-9]{2}\b' | head -1; then
    return 0
  fi

  return 1
}

# Extract TV season/episode
extract_tv_info() {
  local str="$1"

  # Extract SXXEXX pattern
  if echo "$str" | grep -ioE 's[0-9]{2}e[0-9]{2}' | head -1 | tr '[:lower:]' '[:upper:]'; then
    return 0
  fi

  return 1
}

# Check file integrity
check_file_integrity() {
  local file="$1"

  if ! mediainfo "$file" &> /dev/null; then
    return 1
  fi

  # Check if file has duration (not corrupted)
  if ! mediainfo "$file" | grep -q "Duration"; then
    return 1
  fi

  return 0
}

# Safe file move with verification
safe_move() {
  local source="$1"
  local dest="$2"
  local dry_run="${3:-false}"

  if [ "$dry_run" = "true" ]; then
    info "Would move: $source → $dest"
    return 0
  fi

  # Calculate source checksum
  local src_sum=$(sha256sum "$source" | awk '{print $1}')
  echo "$src_sum  $source" >> "$CHECKSUM_FILE"

  # Ensure destination directory exists
  local dest_dir=$(dirname "$dest")
  mkdir -p "$dest_dir"

  # Copy with rsync
  if ! rsync -av --progress "$source" "$dest" 2>&1 | tee -a "$LOG_FILE"; then
    error "rsync failed for $source"
    return 1
  fi

  # Verify checksum
  local dst_sum=$(sha256sum "$dest" | awk '{print $1}')

  if [ "$src_sum" = "$dst_sum" ]; then
    success "Verified and moved: $(basename "$dest")"
    rm -f "$source"
    return 0
  else
    error "Checksum mismatch - keeping source: $source"
    rm -f "$dest"
    return 1
  fi
}

# Quarantine problematic file
quarantine_file() {
  local file="$1"
  local reason="$2"
  local media_type="$3"

  local dest="$QUARANTINE_ROOT/$media_type/$reason/$(basename "$file")"

  info "Quarantining: $(basename "$file") (reason: $reason)"

  if mv "$file" "$dest" 2>&1 | tee -a "$LOG_FILE"; then
    warning "Moved to quarantine: $dest"
    ((STATS_QUARANTINED++))
    return 0
  else
    error "Failed to quarantine: $file"
    return 1
  fi
}

# Analyze directory
analyze_directory() {
  local source_dir="$1"

  info "Analyzing directory: $source_dir"
  echo ""

  local total_files=0
  local ready_files=0
  local need_api=0
  local ambiguous=0

  # Find all media files
  while IFS= read -r -d '' file; do
    ((total_files++))

    local media_type=$(detect_media_type "$file")
    local basename=$(basename "$file")
    local cleaned=$(clean_filename "$basename")

    case "$media_type" in
      movie)
        if extract_year "$cleaned" > /dev/null; then
          echo "  ✅ Movie ready: $cleaned"
          ((ready_files++))
        else
          echo "  ⚠️  Movie needs API: $cleaned (missing year)"
          ((need_api++))
        fi
        ;;
      tv)
        if extract_tv_info "$cleaned" > /dev/null; then
          echo "  ✅ TV episode ready: $cleaned"
          ((ready_files++))
        else
          echo "  ⚠️  TV episode ambiguous: $cleaned (no SXXEXX pattern)"
          ((ambiguous++))
        fi
        ;;
      music)
        echo "  ✅ Music file: $cleaned"
        ((ready_files++))
        ;;
      *)
        echo "  ❌ Unknown type: $cleaned"
        ((ambiguous++))
        ;;
    esac
  done < <(find "$source_dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.flac" -o -name "*.mp3" -o -name "*.m4a" \) -print0)

  echo ""
  info "Analysis complete:"
  echo "  Total files:      $total_files"
  echo "  Ready to process: $ready_files"
  echo "  Need API lookup:  $need_api"
  echo "  Need review:      $ambiguous"
}

# Organize movies
organize_movies() {
  local source_dir="$1"
  local dry_run="${2:-false}"

  info "Organizing movies from: $source_dir"

  while IFS= read -r -d '' file; do
    local basename=$(basename "$file")
    local cleaned=$(clean_filename "$basename")
    local ext="${file##*.}"

    # Check file integrity
    if ! check_file_integrity "$file"; then
      quarantine_file "$file" "corrupted" "movies"
      continue
    fi

    # Extract year
    local year=$(extract_year "$cleaned")

    if [ -z "$year" ]; then
      warning "Missing year - needs API lookup: $basename"
      quarantine_file "$file" "missing-metadata" "movies"
      continue
    fi

    # Extract title (everything before year)
    local title=$(echo "$cleaned" | sed -E "s/\b$year\b.*//g" | sed 's/ *$//')
    title=$(echo "$title" | sed 's/[0-9]*p\|BluRay\|WEBRip\|HDTV\|x264\|x265\|HEVC//gi' | sed 's/  */ /g' | sed 's/ *$//')

    # Create destination
    local dest_dir="$MEDIA_ROOT/movies/$title ($year)"
    local dest_file="$dest_dir/$title ($year).$ext"

    # Move file
    safe_move "$file" "$dest_file" "$dry_run"

  done < <(find "$source_dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) -print0)
}

# Organize TV shows
organize_tv() {
  local source_dir="$1"
  local dry_run="${2:-false}"

  info "Organizing TV shows from: $source_dir"

  while IFS= read -r -d '' file; do
    local basename=$(basename "$file")
    local cleaned=$(clean_filename "$basename")
    local ext="${file##*.}"

    # Check file integrity
    if ! check_file_integrity "$file"; then
      quarantine_file "$file" "corrupted" "tv"
      continue
    fi

    # Extract SXXEXX
    local sxxexx=$(extract_tv_info "$cleaned")

    if [ -z "$sxxexx" ]; then
      warning "No SXXEXX pattern found: $basename"
      quarantine_file "$file" "missing-metadata" "tv"
      continue
    fi

    local season=$(echo "$sxxexx" | sed -E 's/S([0-9]{2})E[0-9]{2}/\1/')
    local episode=$(echo "$sxxexx" | sed -E 's/S[0-9]{2}E([0-9]{2})/\1/')

    # Extract series name (everything before SXXEXX)
    local series=$(echo "$cleaned" | sed -E "s/$sxxexx.*//gi" | sed 's/ *$//')
    series=$(echo "$series" | sed 's/[0-9]*p\|BluRay\|WEBRip\|HDTV\|x264\|x265//gi' | sed 's/  */ /g' | sed 's/ *$//')

    # TODO: Would need API to get series year and episode title
    # For now, use placeholder
    local year="YEAR"

    # Create destination
    local dest_dir="$MEDIA_ROOT/tv/$series ($year)/Season $season"
    local dest_file="$dest_dir/$series - $sxxexx - Episode Title.$ext"

    warning "TV show needs API for year and episode title: $series"
    warning "Would create: $dest_file"

    # For now, quarantine TV shows that need API
    quarantine_file "$file" "missing-metadata" "tv"

  done < <(find "$source_dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) -print0)
}

# Main command dispatcher
main() {
  local command="${1:-}"
  local source_dir="${2:-}"
  local flag="${3:-}"

  # Validate command
  if [ -z "$command" ] || [ -z "$source_dir" ]; then
    echo "Usage: $0 {analyze|organize} <source_directory> [--dry-run|--execute]"
    echo ""
    echo "Commands:"
    echo "  analyze   - Analyze files and show what would be done"
    echo "  organize  - Organize files (requires --dry-run or --execute)"
    echo ""
    echo "Examples:"
    echo "  $0 analyze /mnt/hot/manual/movies"
    echo "  $0 organize /mnt/hot/manual/movies --dry-run"
    echo "  $0 organize /mnt/hot/manual/movies --execute"
    exit 1
  fi

  # Check dependencies
  check_dependencies

  # Check storage
  check_storage || warning "Storage high - proceed with caution"

  echo ""
  info "Starting media organization"
  info "Source: $source_dir"
  info "Log: $LOG_FILE"
  echo ""

  case "$command" in
    analyze)
      analyze_directory "$source_dir"
      ;;
    organize)
      if [ "$flag" != "--dry-run" ] && [ "$flag" != "--execute" ]; then
        error "organize command requires --dry-run or --execute flag"
        exit 1
      fi

      local dry_run="false"
      if [ "$flag" = "--dry-run" ]; then
        dry_run="true"
        info "DRY RUN MODE - No files will be modified"
      else
        warning "EXECUTE MODE - Files will be moved!"
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
          info "Cancelled by user"
          exit 0
        fi
      fi

      echo ""

      # Detect media type and organize accordingly
      organize_movies "$source_dir" "$dry_run"
      organize_tv "$source_dir" "$dry_run"

      echo ""
      info "Organization complete!"
      echo "  Successful: $STATS_SUCCESS"
      echo "  Failed:     $STATS_FAILED"
      echo "  Quarantine: $STATS_QUARANTINED"
      echo "  Skipped:    $STATS_SKIPPED"
      ;;
    *)
      error "Unknown command: $command"
      exit 1
      ;;
  esac

  # Cleanup
  rm -f "$CHECKSUM_FILE"
}

# Run main
main "$@"
