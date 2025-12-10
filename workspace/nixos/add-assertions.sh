#!/usr/bin/env bash

# Assertion Template Generator
# Intelligently adds dependency assertions to modules with enable options
#
# This script analyzes module dependencies and generates appropriate assertion
# templates to enforce Charter Section 18 (Configuration Validity)

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

log() { printf "${BLUE}[ASSERTIONS]${NC} %s\n" "$1"; }
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
    --help|-h)
      cat << 'EOF'
Usage: $0 [options] [files...]

Add dependency assertions to modules with enable options.

Options:
  --dry-run, -n     Show what would be added without making changes
  --verbose, -v     Show detailed output
  --help, -h        Show this help message

If no files specified, processes all index.nix files that need assertions.

Examples:
  # Dry run on all modules
  ./add-assertions.sh --dry-run

  # Fix specific file
  ./add-assertions.sh domains/home/apps/kitty/index.nix
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

# Check if module has enable option
has_enable_option() {
  local file="$1"
  grep -qE 'mkIf.*(\.enable|enable\s*or\s*false)' "$file"
}

# Check if module already has assertions
has_assertions() {
  local file="$1"
  grep -qE '(assertions\s*=|config\.assertions)' "$file"
}

# Extract module namespace from file path
get_module_namespace() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"

  # Extract from domains/<domain>/<category>/<module>/index.nix
  if [[ "$relative_path" =~ ^domains/([^/]+)/([^/]+)/([^/]+)/index\.nix$ ]]; then
    local domain="${BASH_REMATCH[1]}"
    local category="${BASH_REMATCH[2]}"
    local module="${BASH_REMATCH[3]}"
    echo "hwc.${domain}.${category}.${module}"
  elif [[ "$relative_path" =~ ^domains/([^/]+)/([^/]+)/index\.nix$ ]]; then
    local domain="${BASH_REMATCH[1]}"
    local category="${BASH_REMATCH[2]}"
    echo "hwc.${domain}.${category}"
  else
    echo ""
  fi
}

# Analyze module dependencies by looking at config usage
analyze_dependencies() {
  local file="$1"
  local -n deps=$2

  # Look for config.hwc references that indicate dependencies
  while IFS= read -r line; do
    if [[ "$line" =~ config\.hwc\.([a-zA-Z0-9._-]+) ]]; then
      local ref="${BASH_REMATCH[1]}"
      # Filter out self-references and common non-dependency patterns
      if [[ ! "$ref" =~ ^(enable|home\.theme|paths) ]]; then
        deps+=("$ref")
      fi
    fi
  done < <(grep -E 'config\.hwc\.' "$file" 2>/dev/null || true)

  # Deduplicate
  deps=($(printf '%s\n' "${deps[@]}" | sort -u))
}

# Find where to insert assertions in the file
find_assertion_insertion_point() {
  local file="$1"
  local validation_line=0
  local module_end=0
  local line_num=0
  local brace_depth=0

  while IFS= read -r line; do
    ((line_num++))

    # Track braces
    [[ "$line" =~ \{ ]] && ((brace_depth++)) || true
    [[ "$line" =~ \} ]] && ((brace_depth--)) || true

    # Find VALIDATION section
    if [[ "$line" =~ ^\s*#.*VALIDATION ]]; then
      validation_line=$line_num
    fi

    # Track module end (final closing brace)
    if [[ $brace_depth -eq 0 ]] && [[ $line_num -gt 1 ]]; then
      module_end=$line_num
    fi
  done < "$file"

  # Return line after VALIDATION header, or before module end
  if [[ $validation_line -gt 0 ]]; then
    echo $((validation_line + 1))
  elif [[ $module_end -gt 0 ]]; then
    echo $((module_end - 1))
  else
    echo 0
  fi
}

# Generate assertion template
generate_assertion_template() {
  local namespace="$1"
  shift
  local deps=("$@")

  cat << EOF

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = lib.mkIf (config.${namespace}.enable or false) [
EOF

  if [[ ${#deps[@]} -gt 0 ]]; then
    for dep in "${deps[@]}"; do
      cat << EOF
    {
      assertion = config.hwc.${dep}.enable or true;
      message = "${namespace} requires hwc.${dep} to be enabled";
    }
EOF
    done
  else
    cat << EOF
    # Add dependency assertions here
    # Example:
    # {
    #   assertion = config.hwc.dependency.enable or true;
    #   message = "${namespace} requires hwc.dependency to be enabled";
    # }
EOF
  fi

  cat << EOF
  ];
EOF
}

# Add assertions to a module
add_assertions_to_module() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"

  debug "Analyzing $relative_path"

  # Validate syntax before changes
  if ! validate_nix_syntax "$file"; then
    error "Skipping $relative_path - syntax errors exist before modification"
    return 1
  fi

  # Check if module needs assertions
  if ! has_enable_option "$file"; then
    debug "Skipping $relative_path - no enable option found"
    return 0
  fi

  if has_assertions "$file"; then
    debug "Skipping $relative_path - already has assertions"
    return 0
  fi

  # Get module namespace
  local namespace
  namespace=$(get_module_namespace "$file")
  if [[ -z "$namespace" ]]; then
    warn "Cannot determine namespace for $relative_path"
    return 1
  fi

  debug "Module namespace: $namespace"

  # Analyze dependencies
  local -a dependencies=()
  analyze_dependencies "$file" dependencies

  if [[ ${#dependencies[@]} -gt 0 ]]; then
    debug "Found ${#dependencies[@]} potential dependencies: ${dependencies[*]}"
  else
    debug "No obvious dependencies found - will add template"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would add assertions to $relative_path"
    [[ ${#dependencies[@]} -gt 0 ]] && log "  Dependencies: ${dependencies[*]}"
    return 0
  fi

  # Create backup
  cp "$file" "${file}.backup.$(date +%s)"

  # Find insertion point
  local insert_line
  insert_line=$(find_assertion_insertion_point "$file")

  if [[ $insert_line -eq 0 ]]; then
    error "Cannot find insertion point in $relative_path"
    return 1
  fi

  debug "Inserting at line $insert_line"

  # Generate assertion template
  local assertion_template
  assertion_template=$(generate_assertion_template "$namespace" "${dependencies[@]}")

  # Build new file
  local tmp_file
  tmp_file=$(mktemp)

  local line_num=0
  local inserted=false

  while IFS= read -r line; do
    ((line_num++))

    # Insert assertions at the right point
    if [[ $line_num -eq $insert_line ]] && [[ "$inserted" == "false" ]]; then
      # Check if VALIDATION section already exists
      if ! grep -qE '^\s*#.*VALIDATION' "$file"; then
        echo "$assertion_template" >> "$tmp_file"
      else
        # Insert after VALIDATION header
        echo "$line" >> "$tmp_file"
        echo "$assertion_template" >> "$tmp_file"
        inserted=true
        continue
      fi
      inserted=true
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

  fixed "Added assertions to $relative_path (${#dependencies[@]} dependencies)"
  return 0
}

# Find all modules needing assertions
find_modules_needing_assertions() {
  local files=()

  while IFS= read -r -d '' file; do
    if has_enable_option "$file" && ! has_assertions "$file"; then
      files+=("$file")
    fi
  done < <(find "$REPO_ROOT/domains" -name "index.nix" -type f -print0 2>/dev/null || true)

  printf '%s\n' "${files[@]}"
}

# Main execution
main() {
  log "Assertion Template Generator"
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
    for file in "${TARGET_FILES[@]}"; do
      if [[ -f "$file" ]]; then
        files_to_process+=("$file")
      else
        warn "File not found: $file"
      fi
    done
  else
    log "Scanning for modules needing assertions..."
    mapfile -t files_to_process < <(find_modules_needing_assertions)
  fi

  local total_files=${#files_to_process[@]}
  log "Found $total_files files needing assertions"

  if [[ $total_files -eq 0 ]]; then
    success "All modules with enable options already have assertions!"
    exit 0
  fi

  # Process files
  for file in "${files_to_process[@]}"; do
    add_assertions_to_module "$file" || true
  done

  log ""
  log "=== Summary ==="
  success "Successfully added assertions to: $TOTAL_FIXES files"
  [[ $TOTAL_ERRORS -gt 0 ]] && error "Errors encountered: $TOTAL_ERRORS files"
  log ""

  if [[ $TOTAL_FIXES -gt 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
    log "Next steps:"
    log "  1. Review the generated assertions - they may need manual refinement"
    log "  2. Remove false dependencies and add missing ones"
    log "  3. Test the build: nix flake check"
    log "  4. Run linter: ./workspace/utilities/lints/charter-lint.sh"
    log "  5. If successful: git add -A && git commit -m 'feat: add dependency assertions to modules'"
  fi

  [[ $TOTAL_ERRORS -eq 0 ]] || exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
