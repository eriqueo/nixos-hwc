#!/usr/bin/env bash

# Smart Charter Structure Fixer
# AST-aware script to add charter-compliant structure to modules safely
#
# This script uses nix-instantiate to validate syntax before and after changes
# to prevent the syntax errors that plagued earlier bulk automation attempts.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

TOTAL_FIXES=0
TOTAL_ERRORS=0
DRY_RUN=false
VERBOSE=false
BATCH_SIZE=5

log() { printf "${BLUE}[SMART-FIX]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; ((TOTAL_ERRORS++)); }
success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
fixed() { printf "${CYAN}[FIXED]${NC} %s\n" "$1"; ((TOTAL_FIXES++)); }
debug() { [[ "$VERBOSE" == "true" ]] && printf "${BLUE}[DEBUG]${NC} %s\n" "$1" || true; }

# Parse arguments
TARGET_FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --batch-size|-b) BATCH_SIZE="$2"; shift 2 ;;
    --help|-h)
      cat << 'EOF'
Usage: $0 [options] [files...]

Smart charter structure fixes with AST validation.

Options:
  --dry-run, -n         Show what would be fixed without making changes
  --verbose, -v         Show detailed output
  --batch-size, -b N    Process N files at a time (default: 5)
  --help, -h            Show this help message

If no files specified, processes all non-compliant index.nix files in batches.

Examples:
  # Dry run on all modules
  ./smart-charter-fix.sh --dry-run

  # Fix specific files
  ./smart-charter-fix.sh domains/home/apps/kitty/index.nix domains/home/apps/firefox/index.nix

  # Process in batches of 3 files
  ./smart-charter-fix.sh --batch-size 3
EOF
      exit 0
      ;;
    -*)
      error "Unknown option: $1"
      exit 1
      ;;
    *)
      TARGET_FILES+=("$1")
      shift
      ;;
  esac
done

# Validate Nix file syntax
validate_nix_syntax() {
  local file="$1"

  # Skip if validation not available
  [[ "${SYNTAX_VALIDATION:-false}" == "false" ]] && return 0

  if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Check if file has charter sections
has_charter_structure() {
  local file="$1"
  local has_options has_implementation has_validation

  has_options=$(grep -qE '^\s*#.*OPTIONS' "$file" && echo "true" || echo "false")
  has_implementation=$(grep -qE '^\s*#.*IMPLEMENTATION' "$file" && echo "true" || echo "false")
  has_validation=$(grep -qE '^\s*#.*VALIDATION' "$file" && echo "true" || echo "false")

  [[ "$has_options" == "true" && "$has_implementation" == "true" && "$has_validation" == "true" ]]
}

# Analyze module structure to find insertion points
analyze_module_structure() {
  local file="$1"
  local -n result=$2

  result["has_imports"]=false
  result["imports_line"]=0
  result["has_options_import"]=false
  result["first_config_line"]=0
  result["has_let"]=false
  result["let_line"]=0
  result["in_line"]=0
  result["module_start"]=0
  result["module_end"]=0

  local line_num=0
  local in_module=false
  local brace_depth=0

  while IFS= read -r line; do
    ((line_num++))

    # Find module start (opening brace)
    if [[ "$line" =~ ^[[:space:]]*\{ ]]; then
      if [[ "$in_module" == "false" ]]; then
        result["module_start"]=$line_num
        in_module=true
        brace_depth=1
      else
        ((brace_depth++))
      fi
    fi

    # Track braces for module end
    [[ "$line" =~ \{ ]] && ((brace_depth++)) || true
    [[ "$line" =~ \} ]] && ((brace_depth--)) || true

    if [[ $brace_depth -eq 0 && "$in_module" == "true" ]]; then
      result["module_end"]=$line_num
      in_module=false
    fi

    # Find imports
    if [[ "$line" =~ ^[[:space:]]*imports[[:space:]]*= ]]; then
      result["has_imports"]=true
      result["imports_line"]=$line_num
      [[ "$line" =~ options\.nix ]] && result["has_options_import"]=true
    fi

    # Find let-in block
    if [[ "$line" =~ ^[[:space:]]*let[[:space:]]*$ ]]; then
      result["has_let"]=true
      result["let_line"]=$line_num
    fi

    if [[ "$line" =~ ^[[:space:]]*in[[:space:]]*$ ]]; then
      result["in_line"]=$line_num
    fi

    # Find first config line
    if [[ "$line" =~ ^[[:space:]]*config[[:space:]]*= ]] && [[ ${result["first_config_line"]} -eq 0 ]]; then
      result["first_config_line"]=$line_num
    fi

  done < "$file"
}

# Add charter section headers to a module
add_charter_sections() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"

  debug "Analyzing structure of $relative_path"

  # Validate syntax before changes
  if ! validate_nix_syntax "$file"; then
    error "Skipping $relative_path - syntax errors exist before modification"
    return 1
  fi

  # Check if already compliant
  if has_charter_structure "$file"; then
    debug "Skipping $relative_path - already has charter structure"
    return 0
  fi

  # Analyze structure
  declare -A structure
  analyze_module_structure "$file" structure

  if [[ ${structure["module_start"]} -eq 0 ]]; then
    error "Cannot find module start in $relative_path"
    return 1
  fi

  debug "Module structure: start=${structure[module_start]} imports=${structure[imports_line]} config=${structure[first_config_line]}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would add charter sections to $relative_path"
    return 0
  fi

  # Create backup
  cp "$file" "${file}.backup.$(date +%s)"

  # Build the new file with charter sections
  local tmp_file
  tmp_file=$(mktemp)

  local line_num=0
  local in_module=false
  local added_options=false
  local added_implementation=false
  local added_validation=false

  # Read file line by line and insert sections
  while IFS= read -r line; do
    ((line_num++))

    # Start of module
    if [[ $line_num -eq ${structure["module_start"]} ]]; then
      echo "$line" >> "$tmp_file"
      in_module=true

      # Add OPTIONS section right after module start
      if ! grep -qE '^\s*#.*OPTIONS' "$file"; then
        cat >> "$tmp_file" << 'EOF'
  #==========================================================================
  # OPTIONS
  #==========================================================================
EOF
        added_options=true
      fi
      continue
    fi

    # After imports, add IMPLEMENTATION section
    if [[ ${structure["imports_line"]} -gt 0 ]] && [[ $line_num -eq $((${structure["imports_line"]} + 1)) ]] && [[ "$added_implementation" == "false" ]]; then
      if ! grep -qE '^\s*#.*IMPLEMENTATION' "$file"; then
        cat >> "$tmp_file" << 'EOF'

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
EOF
        added_implementation=true
      fi
    fi

    # Before module end, add VALIDATION section
    if [[ ${structure["module_end"]} -gt 0 ]] && [[ $line_num -eq $((${structure["module_end"]} - 1)) ]] && [[ "$added_validation" == "false" ]]; then
      if ! grep -qE '^\s*#.*VALIDATION' "$file"; then
        cat >> "$tmp_file" << 'EOF'

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add dependency assertions here if module has enable option
EOF
        added_validation=true
      fi
    fi

    echo "$line" >> "$tmp_file"

  done < "$file"

  # Apply changes
  cp "$tmp_file" "$file"
  rm -f "$tmp_file"

  # Validate syntax after changes
  if ! validate_nix_syntax "$file"; then
    error "Syntax error created in $relative_path - restoring backup"
    cp "${file}.backup."* "$file" 2>/dev/null || true
    return 1
  fi

  # Clean up backup on success
  rm -f "${file}.backup."*

  fixed "Added charter sections to $relative_path (options=$added_options, impl=$added_implementation, val=$added_validation)"
  return 0
}

# Find all non-compliant index.nix files
find_non_compliant_files() {
  local files=()

  while IFS= read -r -d '' file; do
    if ! has_charter_structure "$file"; then
      files+=("$file")
    fi
  done < <(find "$REPO_ROOT/domains" -name "index.nix" -type f -print0 2>/dev/null || true)

  printf '%s\n' "${files[@]}"
}

# Main execution
main() {
  log "Smart Charter Structure Fixer"
  log "Repository: $REPO_ROOT"
  [[ "$DRY_RUN" == "true" ]] && log "DRY RUN MODE - No changes will be made"
  log ""

  cd "$REPO_ROOT"

  # Check for nix-instantiate
  if ! command -v nix-instantiate >/dev/null 2>&1; then
    warn "nix-instantiate not found - syntax validation disabled"
    warn "Changes will be made without AST validation - review carefully!"
    SYNTAX_VALIDATION=false
  else
    SYNTAX_VALIDATION=true
  fi

  # Determine files to process
  local files_to_process=()
  if [[ ${#TARGET_FILES[@]} -gt 0 ]]; then
    # Use specified files
    for file in "${TARGET_FILES[@]}"; do
      if [[ -f "$file" ]]; then
        files_to_process+=("$file")
      else
        warn "File not found: $file"
      fi
    done
  else
    # Find all non-compliant files
    log "Scanning for non-compliant index.nix files..."
    mapfile -t files_to_process < <(find_non_compliant_files)
  fi

  local total_files=${#files_to_process[@]}
  log "Found $total_files files needing charter structure"

  if [[ $total_files -eq 0 ]]; then
    success "All files are already charter-compliant!"
    exit 0
  fi

  # Process in batches
  local batch_num=0
  local file_count=0

  for file in "${files_to_process[@]}"; do
    ((file_count++))

    if [[ $((file_count % BATCH_SIZE)) -eq 1 ]]; then
      ((batch_num++))
      log ""
      log "=== Batch $batch_num ==="
    fi

    add_charter_sections "$file" || true

    # Pause between batches for review in non-dry-run mode
    if [[ $((file_count % BATCH_SIZE)) -eq 0 ]] && [[ "$DRY_RUN" == "false" ]] && [[ $file_count -lt $total_files ]]; then
      log ""
      warn "Batch $batch_num complete. Press Enter to continue to next batch, or Ctrl+C to stop..."
      read -r
    fi
  done

  log ""
  log "=== Summary ==="
  success "Successfully fixed: $TOTAL_FIXES files"
  [[ $TOTAL_ERRORS -gt 0 ]] && error "Errors encountered: $TOTAL_ERRORS files"
  log ""

  if [[ $TOTAL_FIXES -gt 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
    log "Next steps:"
    log "  1. Review the changes: git diff"
    log "  2. Test the build: nix flake check"
    log "  3. Run linter: ./workspace/nixos/charter-lint.sh"
    log "  4. If successful: git add -A && git commit -m 'chore: add charter structure to modules'"
  fi

  [[ $TOTAL_ERRORS -eq 0 ]] || exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
