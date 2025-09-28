#!/usr/bin/env bash

# HWC Charter Compliance Linter (robust)
# Validates NixOS configuration against HWC Charter v5.x
# Usage: ./tools/hwc-lint.sh [domain] [--fix] [--verbose]

set -Eeuo pipefail
IFS=$'\n\t'

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script directory and repo root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Global counters
TOTAL_ERRORS=0
TOTAL_WARNINGS=0
TOTAL_FIXED=0
VERBOSE=false
FIX_MODE=false

# ------------------------------------------------------------
# Robustness helpers
# ------------------------------------------------------------
on_err() {
  local exit_code=$?
  printf "${RED}[FATAL]${NC} Linter aborted (exit=%d) at %s:%s\n" "$exit_code" "${BASH_SOURCE[1]:-main}" "${BASH_LINENO[0]:-?}" >&2
  exit "$exit_code"
}
trap on_err ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "${RED}[ERROR]${NC} Required command not found: %s\n" "$1" >&2
    exit 127
  }
}

# Prefer ripgrep; fall back to grep with compatible flags if needed
RG_BIN=""
choose_grep() {
  if command -v rg >/dev/null 2>&1; then
    RG_BIN="rg"
  else
    RG_BIN=""
    printf "${YELLOW}[WARN]${NC} ripgrep (rg) not found; falling back to grep. Results may differ.\n" >&2
  fi
}
choose_grep
require_cmd find
require_cmd sed
require_cmd mktemp

# ------------------------------------------------------------
# Logging
# - Increments use +=1 or pre-increment to avoid set -e pitfalls.
# - print_error prints without increment (for multi-line detail blocks).
# ------------------------------------------------------------
log()      { printf "${BLUE}[LINT]${NC} %s\n" "$1"; }
warn()     { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; ((TOTAL_WARNINGS+=1)); }
error()    { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; ((TOTAL_ERRORS+=1)); }
print_error(){ printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }
success()  { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
fixed()    { printf "${CYAN}[FIXED]${NC} %s\n" "$1"; ((TOTAL_FIXED+=1)); }
debug()    { [[ "$VERBOSE" == "true" ]] && printf "${PURPLE}[DEBUG]${NC} %s\n" "$1" >&2 || true; }

# ------------------------------------------------------------
# Args
# ------------------------------------------------------------
DOMAIN_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX_MODE=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --help|-h)
      printf "Usage: %s [domain] [--fix] [--verbose]\n" "$0"
      printf "  domain: home|system|server|infrastructure|profiles|machines\n"
      printf "  --fix: Attempt to auto-fix violations\n"
      printf "  --verbose: Show detailed output\n"
      exit 0
      ;;
    -*)
      printf "Unknown option: %s\nUse --help for usage.\n" "$1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$DOMAIN_FILTER" ]]; then
        DOMAIN_FILTER="$1"
      else
        printf "Unknown argument: %s\n" "$1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# ------------------------------------------------------------
# Filters
# ------------------------------------------------------------
should_process() {
  local path="$1"
  if [[ -z "$DOMAIN_FILTER" ]]; then
    return 0
  fi
  case "$DOMAIN_FILTER" in
    home|system|server|infrastructure) [[ "$path" == *"/domains/$DOMAIN_FILTER"* ]] ;;
    profiles) [[ "$path" == *"/profiles/"* ]] ;;
    machines) [[ "$path" == *"/machines/"* ]] ;;
    *) return 0 ;;
  esac
}

# ------------------------------------------------------------
# Checks
# ------------------------------------------------------------
check_namespace_alignment() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"
  debug "Checking namespace alignment for: $relative_path"

  [[ "$relative_path" =~ ^domains/ ]] || return 0

  local -a path_parts
  IFS='/' read -r -a path_parts <<< "$relative_path"
  [[ ${#path_parts[@]} -ge 3 ]] || return 0

  if [[ ! "$file" =~ options\.nix$ ]] && ! grep -qE "lib\.mkOption|lib\.mkEnableOption" "$file"; then
    return 0
  fi

  local expected_ns="hwc"
  local filename
  filename="$(basename "$file" .nix)"

  if [[ "$file" =~ options\.nix$ ]]; then
    local dir_path
    dir_path="$(dirname "$relative_path")"
    local -a dir_parts
    IFS='/' read -r -a dir_parts <<< "$dir_path"
    for ((i=1; i<${#dir_parts[@]}; i++)); do
      expected_ns="${expected_ns}.${dir_parts[i]}"
    done
  else
    for ((i=1; i<${#path_parts[@]}-1; i++)); do
      expected_ns="${expected_ns}.${path_parts[i]}"
    done
    if [[ "$filename" != "index" ]]; then
      expected_ns="${expected_ns}.${filename}"
    fi
  fi

  debug "Expected namespace: $expected_ns"

  if ! grep -q "options\.$expected_ns" "$file"; then
    error "FILE: $relative_path"
    print_error "  Namespace mismatch - Expected: options.$expected_ns.*"
    local found
    found="$(grep -oE "options\.hwc[^[:space:]]*" "$file" | head -1 || true)"
    if [[ -n "$found" ]]; then
      print_error "  Found: $found"
      print_error "  Suggestion: Move option definition to match directory structure"
    else
      print_error "  Found: No hwc namespace found"
    fi
    return 1
  fi

  success "Namespace alignment correct: $relative_path"
  return 0
}

check_module_anatomy() {
  local module_dir="$1"
  local relative_path="${module_dir#$REPO_ROOT/}"
  debug "Checking module anatomy for: $relative_path"

  [[ "$relative_path" =~ ^domains/.*/.*/ ]] || return 0

  local errors=0

  if [[ ! -f "$module_dir/options.nix" ]]; then
    error "FILE: $relative_path/"
    print_error "  Missing required file: options.nix"
    ((errors+=1))
  fi

  if [[ ! -f "$module_dir/index.nix" ]]; then
    error "FILE: $relative_path/"
    print_error "  Missing required file: index.nix"
    ((errors+=1))
  fi

  if [[ -f "$module_dir/index.nix" ]]; then
    local index_file="$module_dir/index.nix"
    local index_relative="${index_file#$REPO_ROOT/}"

    grep -qE "#\s*OPTIONS" "$index_file" || { error "FILE: $index_relative"; print_error "  Missing OPTIONS section"; ((errors+=1)); }
    grep -qE "#\s*IMPLEMENTATION" "$index_file" || { error "FILE: $index_relative"; print_error "  Missing IMPLEMENTATION section"; ((errors+=1)); }
    grep -qE "#\s*VALIDATION" "$index_file" || { error "FILE: $index_relative"; print_error "  Missing VALIDATION section"; ((errors+=1)); }
    grep -qE "imports.*options\.nix" "$index_file" || { error "FILE: $index_relative"; print_error "  Missing options.nix import"; ((errors+=1)); }
  fi

  if [[ $errors -eq 0 ]]; then
    success "Module anatomy correct: $relative_path"
  fi
  return $errors
}

check_lane_purity() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"
  debug "Checking lane purity for: $relative_path"

  [[ "$file" =~ sys\.nix$ ]] && return 0

  local errors=0

  if [[ "$relative_path" =~ ^domains/home/ ]]; then
    if grep -q "systemd\.services" "$file"; then
      error "FILE: $relative_path"
      print_error "  Lane purity violation: systemd.services found in home domain"
      print_error "  Solution: Move to co-located sys.nix or system domain"
      ((errors+=1))
    fi
    if grep -q "environment\.systemPackages" "$file"; then
      error "FILE: $relative_path"
      print_error "  Lane purity violation: environment.systemPackages found in home domain"
      print_error "  Solution: Move to co-located sys.nix or use home.packages"
      ((errors+=1))
    fi
    if grep -q "users\.users\." "$file"; then
      error "FILE: $relative_path"
      print_error "  Lane purity violation: users.users found in home domain"
      print_error "  Solution: Move to domains/system/users/"
      ((errors+=1))
    fi
  fi

  if [[ "$relative_path" =~ ^domains/(system|server|infrastructure)/ ]]; then
    if grep -q "programs\." "$file" && grep -q "home\." "$file"; then
      error "FILE: $relative_path"
      print_error "  Lane purity violation: Home Manager configs found in system domain"
      print_error "  Solution: Move to domains/home/ and import via machine home.nix"
      ((errors+=1))
    fi
  fi

  if [[ "$relative_path" =~ ^profiles/ ]] && [[ ! "$relative_path" =~ profiles/home\.nix$ ]]; then
    if grep -q "home-manager\." "$file"; then
      error "FILE: $relative_path"
      print_error "  Lane purity violation: Home Manager activation in profile"
      print_error "  Solution: Move to machine-level home.nix"
      ((errors+=1))
    fi
  fi

  [[ $errors -eq 0 ]] && debug "Lane purity correct: $relative_path"
  return $errors
}

check_anti_patterns() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"
  debug "Checking anti-patterns for: $relative_path"

  local errors=0

  if grep -q "/mnt/" "$file"; then
    warn "FILE: $relative_path"
    warn "  Hardcoded /mnt/ path found - consider using variable paths"
  fi

  if [[ ! "$file" =~ options\.nix$ ]] && [[ ! "$file" =~ index\.nix$ ]] && grep -qE "lib\.mkOption|lib\.mkEnableOption" "$file"; then
    error "FILE: $relative_path"
    print_error "  Anti-pattern: Options defined outside options.nix or index.nix"
    print_error "  Solution: Move option definitions to options.nix"
    ((errors+=1))
  fi

  if [[ "$relative_path" =~ ^domains/home/ ]] && grep -q "users\.users\." "$file"; then
    error "FILE: $relative_path"
    print_error "  Anti-pattern: Mixed-domain module (user creation in home domain)"
    print_error "  Solution: User creation belongs in domains/system/users/"
    ((errors+=1))
  fi

  if grep -q "\.paths\." "$file" && [[ "$relative_path" =~ domains/system/ ]]; then
    if grep -q "hot.*cold.*media" "$file" && ! grep -qE "paths\.nix|filesystem" <<< "$relative_path"; then
      warn "FILE: $relative_path"
      warn "  Potential duplicate path definition - consider consolidating with existing path module"
    fi
  fi

  if grep -q "^# nixos-h\.\." "$file"; then
    warn "FILE: $relative_path"
    warn "  Legacy comment header format - consider updating to current Charter format"
  fi

  if grep -q "TODO:" "$file" && [[ ! "$relative_path" =~ test/ ]]; then
    warn "FILE: $relative_path"
    warn "  TODO comment found"
    debug "    $(grep -n "TODO:" "$file" | head -1 || true)"
  fi

  return $errors
}

check_file_naming() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"
  local filename
  filename="$(basename "$file")"

  debug "Checking file naming for: $relative_path"

  case "$filename" in
    flake.nix|flake.lock|configuration.nix|hardware-configuration.nix) return 0 ;;
  esac

  if [[ "$relative_path" =~ ^(domains|profiles|machines)/ ]] && [[ "$filename" =~ \.nix$ ]]; then
    if [[ ! "$filename" =~ ^[a-z0-9-]+\.nix$ ]]; then
      error "FILE: $relative_path"
      print_error "  File naming violation: not kebab-case (expected: kebab-case.nix)"
      return 1
    fi
  fi

  debug "File naming correct: $relative_path"
  return 0
}

check_profile_structure() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"

  [[ "$relative_path" =~ ^profiles/.*\.nix$ ]] || return 0
  debug "Checking profile structure for: $relative_path"

  if ! grep -qE "BASE|CRITICAL|ESSENTIAL" "$file"; then
    warn "FILE: $relative_path"
    warn "  Missing BASE section marker - consider adding # BASE SYSTEM or similar section"
  fi
  if ! grep -qE "OPTIONAL|FEATURES|DEFAULTS" "$file"; then
    warn "FILE: $relative_path"
    warn "  Missing OPTIONAL FEATURES section marker - consider adding # OPTIONAL FEATURES section"
  fi
  return 0
}

# ------------------------------------------------------------
# Fixes
# ------------------------------------------------------------
fix_issues() {
  local file="$1"
  local relative_path="${file#$REPO_ROOT/}"

  [[ "$FIX_MODE" == "true" ]] || return 0
  debug "Attempting fixes for: $relative_path"

  if [[ "$file" =~ index\.nix$ ]] && [[ -f "$file" ]]; then
    local tmp
    tmp="$(mktemp)"
    local has_options=false has_implementation=false has_validation=false

    grep -qE "#\s*OPTIONS" "$file" && has_options=true || true
    grep -qE "#\s*IMPLEMENTATION" "$file" && has_implementation=true || true
    grep -qE "#\s*VALIDATION" "$file" && has_validation=true || true

    if [[ "$has_options" == "false" ]] && grep -qE "imports.*options\.nix" "$file"; then
      sed 's|imports = \[ ./options.nix \];|#==========================================================================\
  # OPTIONS \
  #==========================================================================\
  imports = [ ./options.nix ];|' "$file" > "$tmp"

      if [[ "$has_implementation" == "false" ]] && grep -q "config.*mkIf" "$tmp"; then
        sed 's|config = lib.mkIf|#==========================================================================\
  # IMPLEMENTATION\
  #==========================================================================\
  config = lib.mkIf|' "$tmp" > "${tmp}.2"
        mv "${tmp}.2" "$tmp"
      fi

      if [[ "$has_validation" == "false" ]]; then
        printf "\n  #==========================================================================\n  # VALIDATION\n  #==========================================================================" >> "$tmp"
      fi

      if ! cmp -s "$file" "$tmp"; then
        cp "$tmp" "$file"
        fixed "Added missing section headers to $relative_path"
      fi
    fi
    rm -f "$tmp" "${tmp}.2" 2>/dev/null || true
  fi

  return 0
}

# ------------------------------------------------------------
# Processing
# ------------------------------------------------------------
process_file() {
  local file="$1"
  [[ -f "$file" && "$file" =~ \.nix$ ]] || return 0
  should_process "$file" || return 0
  debug "Processing file: ${file#$REPO_ROOT/}"

  check_namespace_alignment "$file" || true
  check_lane_purity "$file" || true
  check_anti_patterns "$file" || true
  check_file_naming "$file" || true
  check_profile_structure "$file" || true
  fix_issues "$file" || true
}

process_directory() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  should_process "$dir" || return 0

  if [[ "$dir" =~ domains/.*/.*$ ]] && ([[ -f "$dir/index.nix" ]] || [[ -f "$dir/options.nix" ]]); then
    check_module_anatomy "$dir" || true
  fi
}

# ------------------------------------------------------------
# Validation searches (Charter Section 13)
#   Robust fix:
#   - Use print_error for detail lines to avoid inflating counters.
#   - Count one error per violation class via search_errors.
#   - Arithmetic uses +=1 to remain safe under set -e.
# ------------------------------------------------------------
run_validation_searches() {
  log "Running Charter validation searches…"
  local search_errors=0

  # Helper to list files via ripgrep or grep
  _list_files() {
    local pattern="$1" base="$2"
    if [[ -n "$RG_BIN" ]]; then
      "$RG_BIN" --color=never -l "$pattern" "$base" 2>/dev/null || true
    else
      grep -RIl --exclude-dir='.git' -e "$pattern" "$base" 2>/dev/null || true
    fi
  }
  _grep_lines() {
    local pattern="$1" file="$2"
    if [[ -n "$RG_BIN" ]]; then
      "$RG_BIN" --color=never -n "$pattern" "$file" 2>/dev/null || true
    else
      grep -nH -- "$pattern" "$file" 2>/dev/null || true
    fi
  }

  printf "Checking for writeScriptBin violations...\n"
  if [[ -d "$REPO_ROOT/domains/home/" ]]; then
    mapfile -t writeScriptFiles < <(_list_files "writeScriptBin" "$REPO_ROOT/domains/home/")
    if [[ ${#writeScriptFiles[@]} -gt 0 ]]; then
      error "Charter violation: writeScriptBin found in domains/home/"
      for filepath in "${writeScriptFiles[@]}"; do
        local rel="${filepath#$REPO_ROOT/}"
        print_error "  FILE: $rel"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local linenum="${line%%:*}"
          local content="${line#*:}"
          print_error "    Line ${linenum}:${content}"
        done < <(_grep_lines "writeScriptBin" "$filepath")
      done
      print_error "  Solution: Move script creation to co-located sys.nix or system domain"
      printf "\n"
      ((search_errors+=1))
    fi
  fi

  printf "Checking for systemd.services violations...\n"
  if [[ -d "$REPO_ROOT/domains/home/" ]]; then
    mapfile -t systemdFiles < <(_list_files "systemd\.services" "$REPO_ROOT/domains/home/")
    if [[ ${#systemdFiles[@]} -gt 0 ]]; then
      error "Charter violation: systemd.services found in domains/home/"
      for filepath in "${systemdFiles[@]}"; do
        local rel="${filepath#$REPO_ROOT/}"
        print_error "  FILE: $rel"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local linenum="${line%%:*}"
          local content="${line#*:}"
          print_error "    Line ${linenum}:${content}"
        done < <(_grep_lines "systemd\.services" "$filepath")
      done
      print_error "  Solution: Move to co-located sys.nix or system domain"
      printf "\n"
      ((search_errors+=1))
    fi
  fi

  printf "Checking for environment.systemPackages violations...\n"
  if [[ -d "$REPO_ROOT/domains/home/" ]]; then
    mapfile -t envPkgFiles < <(_list_files "environment\.systemPackages" "$REPO_ROOT/domains/home/")
    if [[ ${#envPkgFiles[@]} -gt 0 ]]; then
      error "Charter violation: environment.systemPackages found in domains/home/"
      for filepath in "${envPkgFiles[@]}"; do
        local rel="${filepath#$REPO_ROOT/}"
        print_error "  FILE: $rel"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local linenum="${line%%:*}"
          local content="${line#*:}"
          print_error "    Line ${linenum}:${content}"
        done < <(_grep_lines "environment\.systemPackages" "$filepath")
      done
      print_error "  Solution: Use home.packages or move to co-located sys.nix"
      printf "\n"
      ((search_errors+=1))
    fi
  fi

  printf "Checking for home-manager in profiles violations...\n"
  if [[ -d "$REPO_ROOT/profiles/" ]]; then
    # find ... -exec ... pattern retained for compatibility
    if [[ -n "$RG_BIN" ]]; then
      mapfile -t hmFiles < <(find "$REPO_ROOT/profiles/" -name "*.nix" ! -name "home.nix" -exec "$RG_BIN" --color=never -l "home-manager" {} \; 2>/dev/null)
    else
      mapfile -t hmFiles < <(grep -RIl --exclude-dir='.git' --include='*.nix' -e "home-manager" "$REPO_ROOT/profiles/" | grep -v '/home\.nix$' || true)
    fi
    if [[ ${#hmFiles[@]} -gt 0 ]]; then
      error "Charter violation: home-manager found in profiles/ (except home.nix)"
      for filepath in "${hmFiles[@]}"; do
        local rel="${filepath#$REPO_ROOT/}"
        print_error "  FILE: $rel"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local linenum="${line%%:*}"
          local content="${line#*:}"
          print_error "    Line ${linenum}:${content}"
        done < <(_grep_lines "home-manager" "$filepath")
      done
      print_error "  Solution: Move HM activation to machine-level home.nix"
      printf "\n"
      ((search_errors+=1))
    fi
  fi

  printf "Checking for hardcoded /mnt/ paths...\n"
  if [[ -d "$REPO_ROOT/domains/" ]]; then
    mapfile -t mntFiles < <(_list_files "/mnt/" "$REPO_ROOT/domains/")
    if [[ ${#mntFiles[@]} -gt 0 ]]; then
      warn "Charter concern: hardcoded /mnt/ paths found in domains/"
      for filepath in "${mntFiles[@]}"; do
        local rel="${filepath#$REPO_ROOT/}"
        warn "  FILE: $rel"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local linenum="${line%%:*}"
          local content="${line#*:}"
          warn "    Line ${linenum}:${content}"
        done < <(_grep_lines "/mnt/" "$filepath")
      done
      warn "  Suggestion: Consider using variable paths from hwc.paths"
      printf "\n"
    fi
  fi

  if [[ $search_errors -eq 0 ]]; then
    success "All validation searches passed"
  fi

  ((TOTAL_ERRORS+=search_errors))
  return $search_errors
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
main() {
  log "HWC Charter Compliance Linter (robust)"
  log "Repository: $REPO_ROOT"
  [[ -n "$DOMAIN_FILTER" ]] && log "Domain filter: $DOMAIN_FILTER"
  [[ "$FIX_MODE" == "true" ]] && log "Fix mode: enabled"
  printf "\n"

  cd "$REPO_ROOT"

  if [[ ! -d "domains" ]] || [[ ! -d "profiles" ]] || [[ ! -f "flake.nix" ]]; then
    error "Not in HWC repository root (missing domains/, profiles/, or flake.nix)"
    exit 1
  fi

  run_validation_searches || true
  printf "\n"

  log "Checking individual files..."
  while IFS= read -r -d '' file; do
    process_file "$file"
  done < <(find "$REPO_ROOT" -type f -name "*.nix" -print0)
  printf "\n"

  log "Checking module anatomy..."
  while IFS= read -r -d '' dir; do
    process_directory "$dir"
  done < <(find "$REPO_ROOT/domains" -type d -print0 2>/dev/null || true)
  printf "\n"

  log "Linting complete!"
  printf "\n"

  if [[ $TOTAL_ERRORS -eq 0 && $TOTAL_WARNINGS -eq 0 ]]; then
    success "✅ All checks passed! Your configuration is Charter compliant."
  else
    if [[ $TOTAL_ERRORS -gt 0 ]]; then
      error "❌ Found $TOTAL_ERRORS error(s)"
    fi
    if [[ $TOTAL_WARNINGS -gt 0 ]]; then
      warn "⚠️  Found $TOTAL_WARNINGS warning(s)"
    fi
    if [[ $TOTAL_FIXED -gt 0 ]]; then
      fixed "🔧 Auto-fixed $TOTAL_FIXED issue(s)"
    fi
  fi

  printf "\n"
  [[ $TOTAL_ERRORS -eq 0 ]] || exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
