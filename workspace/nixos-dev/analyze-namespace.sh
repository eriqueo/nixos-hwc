#!/usr/bin/env bash

# Namespace Impact Analysis Tool
# Analyzes the impact of namespace changes before applying them

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

log() { printf "${BLUE}[ANALYZE]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }
success() { printf "${GREEN}[SAFE]${NC} %s\n" "$1"; }

analyze_namespace_usage() {
  local namespace="$1"
  local context="$2"
  
  log "Analyzing usage of namespace: $namespace"
  
  # Convert namespace patterns
  local config_ns="${namespace/options./config.}"
  local enable_ns="${config_ns}.enable"
  
  echo "  Searching for patterns:"
  echo "    - $namespace"
  echo "    - $config_ns"
  echo "    - $enable_ns"
  echo
  
  local total_refs=0
  local definition_files=()
  local usage_files=()
  
  # First, get count of .nix files for progress
  local total_files
  total_files=$(find "$REPO_ROOT" -name "*.nix" -type f | wc -l)
  echo "  Scanning $total_files .nix files..."
  
  local current_file=0
  
  # Search for all references with progress
  while IFS= read -r file; do
    ((current_file++))
    
    # Show progress every 50 files
    if (( current_file % 50 == 0 )); then
      printf "\r  Progress: %d/%d files scanned" "$current_file" "$total_files"
    fi
    
    # Skip if file doesn't exist or is a directory
    [[ -f "$file" ]] || continue
    
    local has_definition=false
    local has_usage=false
    
    # Check for option definition (more specific pattern)
    if grep -qE "^\s*${namespace//./\\.}\s*=" "$file" 2>/dev/null; then
      has_definition=true
      definition_files+=("$file")
    fi
    
    # Check for config usage
    if grep -qE "\b${config_ns//./\\.}\b|\b${enable_ns//./\\.}\b" "$file" 2>/dev/null; then
      has_usage=true
      usage_files+=("$file")
    fi
    
    if [[ "$has_definition" == "true" || "$has_usage" == "true" ]]; then
      ((total_refs++))
    fi
    
  done < <(find "$REPO_ROOT" -name "*.nix" -type f 2>/dev/null)
  
  printf "\r  Completed: %d/%d files scanned\n" "$current_file" "$total_files"
  echo
  
  # Show detailed results only for files with matches
  if [[ $total_refs -gt 0 ]]; then
    echo "  Files with references:"
    for file in "${definition_files[@]}" "${usage_files[@]}"; do
      echo "  📄 ${file#$REPO_ROOT/}"
      
      # Check what type of reference this file has
      local is_definition=false
      local is_usage=false
      
      for def_file in "${definition_files[@]}"; do
        [[ "$file" == "$def_file" ]] && is_definition=true
      done
      
      for usage_file in "${usage_files[@]}"; do
        [[ "$file" == "$usage_file" ]] && is_usage=true
      done
      
      if [[ "$is_definition" == "true" ]]; then
        echo "    🔧 Defines options:"
        grep -n "$namespace" "$file" 2>/dev/null | head -3 | sed 's/^/      /' || true
      fi
      
      if [[ "$is_usage" == "true" ]]; then
        echo "    🎯 Uses config:"
        grep -nE "\b${config_ns//./\\.}\b|\b${enable_ns//./\\.}\b" "$file" 2>/dev/null | head -3 | sed 's/^/      /' || true
      fi
      echo
    done
  else
    echo "  ℹ️  No references found for this namespace"
    echo
  fi
  
  echo "📊 Summary for $namespace:"
  echo "  Total files with references: $total_refs"
  echo "  Definition files: ${#definition_files[@]}"
  echo "  Usage files: ${#usage_files[@]}"
  echo
  
  # Safety assessment
  if [[ ${#definition_files[@]} -eq 0 ]]; then
    if [[ ${#usage_files[@]} -eq 0 ]]; then
      warn "No references found - namespace may not exist or pattern needs adjustment"
      return 0  # Safe to change since it doesn't exist
    else
      error "Usage found but no definition - investigate manually"
      return 1
    fi
  elif [[ ${#definition_files[@]} -gt 1 ]]; then
    error "Multiple definitions found - manual resolution required"
    return 1
  elif [[ ${#usage_files[@]} -eq 0 ]]; then
    success "Only definition found - safe to rename"
    return 0
  else
    warn "Has ${#usage_files[@]} usage file(s) - all must be updated together"
    echo "Files that need coordinated updates:"
    printf '%s\n' "${definition_files[@]}" "${usage_files[@]}" | sort -u | while read -r file; do
      echo "  - ${file#$REPO_ROOT/}"
    done
    return 2
  fi
}

generate_fix_plan() {
  local old_ns="$1"
  local new_ns="$2"
  local safety_status="$3"
  
  case $safety_status in
    0)
      echo "✅ SAFE: Can be automated"
      echo "   Only definition exists, no usage references"
      ;;
    1)
      echo "❌ UNSAFE: Manual investigation required"
      echo "   Multiple definitions or no definitions found"
      ;;
    2)
      echo "⚠️  CAUTION: Coordinated update required"
      echo "   Multiple files must be updated together"
      echo "   Suggested approach:"
      echo "   1. Update all files in a single commit"
      echo "   2. Test configuration immediately"
      echo "   3. Consider creating a migration script"
      ;;
  esac
}

main() {
  log "Namespace Impact Analysis"
  log "Repository: $REPO_ROOT"
  echo
  
  # Analyze each proposed namespace change
  local -A namespace_changes=(
    ["options.hwc.home.shell"]="options.hwc.home.environment.shell"
    ["options.hwc.home.productivity"]="options.hwc.home.environment.productivity"
    ["options.hwc.home.development"]="options.hwc.home.environment.development"
    ["options.hwc.home.fonts"]="options.hwc.home.theme.fonts"
    ["options.hwc.home.apps.protonAuthenticator"]="options.hwc.home.apps.proton-authenticator"
    ["options.hwc.home.apps.protonMail"]="options.hwc.home.apps.proton-mail"
    ["options.hwc.home.apps.protonPass"]="options.hwc.home.apps.proton-pass"
    ["options.hwc.home.apps.geminiCli"]="options.hwc.home.apps.gemini-cli"
  )
  
  local safe_count=0
  local unsafe_count=0
  local caution_count=0
  
  for old_ns in "${!namespace_changes[@]}"; do
    local new_ns="${namespace_changes[$old_ns]}"
    
    echo "═══════════════════════════════════════════════════════════════"
    echo "ANALYZING: $old_ns"
    echo "      TO: $new_ns"
    echo "═══════════════════════════════════════════════════════════════"
    
    analyze_namespace_usage "$old_ns" "proposed change"
    local result=$?
    
    case $result in
      0) ((safe_count++)) ;;
      1) ((unsafe_count++)) ;;
      2) ((caution_count++)) ;;
    esac
    
    generate_fix_plan "$old_ns" "$new_ns" "$result"
    echo
  done
  
  echo "═══════════════════════════════════════════════════════════════"
  echo "FINAL ANALYSIS"
  echo "═══════════════════════════════════════════════════════════════"
  echo "✅ Safe for automation: $safe_count"
  echo "⚠️  Require coordination: $caution_count"
  echo "❌ Need manual review: $unsafe_count"
  echo
  
  if [[ $safe_count -gt 0 ]]; then
    success "Some namespace changes can be safely automated"
  fi
  
  if [[ $caution_count -gt 0 ]]; then
    warn "Some changes require updating multiple files together"
    warn "Consider running autofix with --dry-run first"
  fi
  
  if [[ $unsafe_count -gt 0 ]]; then
    error "Some changes need manual investigation"
    error "Do not run automated fixes until these are resolved"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
