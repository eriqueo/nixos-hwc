#!/usr/bin/env bash

# HWC Charter Auto-Fix Script
# Automatically fixes common Charter violations

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
DRY_RUN=false
VERBOSE=false

log() { printf "${BLUE}[AUTOFIX]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }
success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
fixed() { printf "${CYAN}[FIXED]${NC} %s\n" "$1"; ((TOTAL_FIXES++)); }
debug() { [[ "$VERBOSE" == "true" ]] && printf "${BLUE}[DEBUG]${NC} %s\n" "$1" || true; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --help|-h)
      cat << EOF
Usage: $0 [options]
Options:
  --dry-run, -n     Show what would be fixed without making changes
  --verbose, -v     Show detailed output
  --help, -h        Show this help message

Automated fixes:
  1. Namespace kebab-case corrections (protonMail -> proton-mail)
  2. Add missing section headers to index.nix files
  3. Create missing options.nix files with proper structure
  4. Fix legacy comment headers
  5. Move writeScriptBin from home domain to sys.nix
EOF
      exit 0
      ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

# Backup function for dry-run mode
backup_and_edit() {
  local file="$1"
  local description="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would fix: $description in ${file#$REPO_ROOT/}"
    return 0
  fi
  
  # Create backup
  cp "$file" "${file}.backup"
  debug "Created backup: ${file}.backup"
  return 0
}

# Fix 1: Namespace kebab-case corrections
fix_namespace_kebab_case() {
  log "🔧 Fixing namespace kebab-case violations..."
  
  # Find actual violations from specific files mentioned in your lint output
  local -A file_fixes=(
    ["domains/home/apps/proton-authenticator/options.nix"]="s/protonAuthenticator/proton-authenticator/g"
    ["domains/home/apps/proton-pass/options.nix"]="s/protonPass/proton-pass/g"  
    ["domains/home/apps/proton-mail/options.nix"]="s/protonMail/proton-mail/g"
    ["domains/home/apps/gemini-cli/options.nix"]="s/geminiCli/gemini-cli/g"
  )
  
  for rel_file in "${!file_fixes[@]}"; do
    local file="$REPO_ROOT/$rel_file"
    local sed_pattern="${file_fixes[$rel_file]}"
    
    if [[ -f "$file" ]] && grep -qE "(protonAuthenticator|protonPass|protonMail|geminiCli)" "$file"; then
      backup_and_edit "$file" "namespace kebab-case fix"
      
      if [[ "$DRY_RUN" == "false" ]]; then
        sed -i "$sed_pattern" "$file"
        fixed "Fixed kebab-case namespace in $rel_file"
      fi
    fi
  done
}

# Fix 2: Add missing section headers to index.nix files  
fix_missing_section_headers() {
  log "📝 Adding missing section headers to index.nix files..."
  
  # Target specific files that were flagged in your lint output
  local index_files=(
    "domains/home/mail/bridge/index.nix"
    "domains/home/mail/notmuch/index.nix"
    "domains/home/mail/accounts/index.nix"
    "domains/home/mail/mbsync/index.nix"
    "domains/home/mail/msmtp/index.nix"
    "domains/home/apps/betterbird/index.nix"
    "domains/home/apps/dunst/index.nix"
    "domains/home/apps/proton-pass/index.nix"
    "domains/home/apps/kitty/index.nix"
    "domains/home/apps/hyprland/index.nix"
    "domains/home/apps/chromium/index.nix"
    "domains/home/apps/yazi/index.nix"
    "domains/home/apps/proton-mail/index.nix"
    "domains/home/apps/thunar/index.nix"
    "domains/home/apps/librewolf/index.nix"
    "domains/home/apps/neomutt/index.nix"
    "domains/home/apps/aerc/index.nix"
    "domains/home/apps/obsidian/index.nix"
    "domains/home/apps/waybar/index.nix"
  )
  
  for rel_file in "${index_files[@]}"; do
    local file="$REPO_ROOT/$rel_file"
    [[ -f "$file" ]] || continue
    
    local needs_fix=false
    local has_options=false
    local has_implementation=false  
    local has_validation=false
    
    # Check current state
    grep -qE "#\s*OPTIONS" "$file" && has_options=true
    grep -qE "#\s*IMPLEMENTATION" "$file" && has_implementation=true
    grep -qE "#\s*VALIDATION" "$file" && has_validation=true
    
    # Check if any headers are missing
    [[ "$has_options" == "false" ]] && needs_fix=true
    [[ "$has_implementation" == "false" ]] && needs_fix=true  
    [[ "$has_validation" == "false" ]] && needs_fix=true
    
    if [[ "$needs_fix" == "true" ]]; then
      backup_and_edit "$file" "missing section headers"
      
      if [[ "$DRY_RUN" == "false" ]]; then
        local tmp_file
        tmp_file=$(mktemp)
        
        # Read file and add headers
        {
          echo "{"
          [[ "$has_options" == "false" ]] && echo "  #=========================================================================="
          [[ "$has_options" == "false" ]] && echo "  # OPTIONS"
          [[ "$has_options" == "false" ]] && echo "  #=========================================================================="
          
          # Process imports line if exists
          if grep -q "imports.*options\.nix" "$file"; then
            grep "imports.*options\.nix" "$file"
          elif grep -q "imports" "$file"; then
            grep "imports" "$file"
          fi
          
          echo ""
          [[ "$has_implementation" == "false" ]] && echo "  #=========================================================================="
          [[ "$has_implementation" == "false" ]] && echo "  # IMPLEMENTATION"
          [[ "$has_implementation" == "false" ]] && echo "  #=========================================================================="
          
          # Add the rest of the file content (skip first line and imports)
          tail -n +2 "$file" | grep -v "^[[:space:]]*imports"
          
          [[ "$has_validation" == "false" ]] && echo ""
          [[ "$has_validation" == "false" ]] && echo "  #=========================================================================="
          [[ "$has_validation" == "false" ]] && echo "  # VALIDATION"
          [[ "$has_validation" == "false" ]] && echo "  #=========================================================================="
          [[ "$has_validation" == "false" ]] && echo "  # Add validation logic here if needed"
          
        } > "$tmp_file"
        
        cp "$tmp_file" "$file"
        rm -f "$tmp_file"
        fixed "Added section headers to $rel_file"
      fi
    fi
  done
}

# Fix 3: Create missing options.nix files
fix_missing_options_files() {
  log "📄 Creating missing options.nix files..."
  
  # Find directories that should have options.nix but don't
  while IFS= read -r -d '' dir; do
    [[ -d "$dir" ]] || continue
    
    # Check if it's a module directory (has index.nix but no options.nix)
    if [[ -f "$dir/index.nix" && ! -f "$dir/options.nix" ]]; then
      # Extract module path for namespace
      local relative_path="${dir#$REPO_ROOT/}"
      
      # Only process domains
      [[ "$relative_path" =~ ^domains/ ]] || continue
      
      # Build namespace from path
      local -a path_parts
      IFS='/' read -r -a path_parts <<< "$relative_path"
      [[ ${#path_parts[@]} -ge 3 ]] || continue
      
      local namespace="hwc"
      for ((i=1; i<${#path_parts[@]}; i++)); do
        namespace="${namespace}.${path_parts[i]}"
      done
      
      backup_and_edit "$dir/options.nix" "creating missing options.nix"
      
      if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$dir/options.nix" << EOF
{ lib, ... }:

{
  options.$namespace = {
    enable = lib.mkEnableOption "Enable ${path_parts[-1]} functionality";
    
    # Add module-specific options here
  };
}
EOF
        fixed "Created options.nix for ${relative_path}"
        
        # Update index.nix to import options.nix if not already imported
        if ! grep -q "imports.*options\.nix" "$dir/index.nix"; then
          local tmp_file
          tmp_file=$(mktemp)
          {
            echo "{"
            echo "  imports = [ ./options.nix ];"
            echo ""
            tail -n +2 "$dir/index.nix"
          } > "$tmp_file"
          cp "$tmp_file" "$dir/index.nix"
          rm -f "$tmp_file"
          fixed "Added options.nix import to ${relative_path}/index.nix"
        fi
      fi
    fi
  done < <(find "$REPO_ROOT/domains" -type d -print0 2>/dev/null || true)
}

# Fix 4: Update legacy comment headers  
fix_legacy_comment_headers() {
  log "💬 Fixing legacy comment headers..."
  
  while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    
    if grep -q "^# nixos-h\.\." "$file"; then
      backup_and_edit "$file" "legacy comment header"
      
      if [[ "$DRY_RUN" == "false" ]]; then
        sed -i 's/^# nixos-h\.\./# HWC Charter Module/' "$file"
        fixed "Updated legacy comment header in ${file#$REPO_ROOT/}"
      fi
    fi
  done < <(find "$REPO_ROOT/domains" -name "*.nix" -print0 2>/dev/null || true)
}

# Fix 5: Move writeScriptBin from home domain to sys.nix
fix_writeScriptBin_violations() {
  log "🔄 Moving writeScriptBin from home domain to sys.nix..."
  
  # Find writeScriptBin usage in home domain (excluding sys.nix)
  while IFS= read -r file; do
    [[ -f "$file" && ! "$file" =~ sys\.nix$ ]] || continue
    
    # Check if it actually defines writeScriptBin (not just comments)
    if grep -qE "^\s*.*writeScriptBin" "$file" && ! grep -E "^\s*#.*writeScriptBin" "$file" >/dev/null; then
      local dir
      dir=$(dirname "$file")
      local sys_file="$dir/sys.nix"
      local relative_path="${file#$REPO_ROOT/}"
      
      warn "Found writeScriptBin violation in $relative_path"
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would move writeScriptBin from $relative_path to ${sys_file#$REPO_ROOT/}"
        continue
      fi
      
      # Extract writeScriptBin definitions
      local writeScriptBin_lines
      writeScriptBin_lines=$(grep -n "writeScriptBin" "$file" || true)
      
      if [[ -n "$writeScriptBin_lines" ]]; then
        warn "Manual intervention needed for $relative_path"
        warn "  Found writeScriptBin usage that should be moved to ${sys_file#$REPO_ROOT/}"
        warn "  Please review and move manually"
        warn "  Lines: $(echo "$writeScriptBin_lines" | cut -d: -f1 | tr '\n' ' ')"
      fi
    fi
  done < <(find "$REPO_ROOT/domains/home" -name "*.nix" -type f 2>/dev/null || true)
}

# Fix 6: Fix simple namespace realignments (with safety checks)
fix_simple_namespace_realignments() {
  log "🎯 Fixing simple namespace realignments (with safety checks)..."
  
  # Common namespace corrections
  local -A simple_fixes=(
    ["options.hwc.home.shell"]="options.hwc.home.environment.shell"
    ["options.hwc.home.productivity"]="options.hwc.home.environment.productivity"
    ["options.hwc.home.development"]="options.hwc.home.environment.development"
    ["options.hwc.home.fonts"]="options.hwc.home.theme.fonts"
  )
  
  for old_ns in "${!simple_fixes[@]}"; do
    local new_ns="${simple_fixes[$old_ns]}"
    local config_old_ns="${old_ns/options./config.}"
    local config_new_ns="${new_ns/options./config.}"
    
    # Check for any references to this namespace in the entire repo
    local references=0
    local reference_files=()
    
    # Search for both options.* and config.* references
    while IFS= read -r file; do
      # Skip if not a regular file
      [[ -f "$file" ]] || continue
      
      if grep -qE "(${old_ns//./\\.}|${config_old_ns//./\\.})" "$file" 2>/dev/null; then
        ((references++))
        reference_files+=("$file")
        debug "Found reference to ${old_ns##*.} in ${file#$REPO_ROOT/}"
      fi
    done < <(find "$REPO_ROOT" -name "*.nix" -type f 2>/dev/null)
    
    if [[ $references -gt 1 ]]; then
      warn "Namespace ${old_ns##*.} has $references references across multiple files:"
      for ref_file in "${reference_files[@]}"; do
        warn "  - ${ref_file#$REPO_ROOT/}"
      done
      warn "Skipping automatic fix - manual review required"
      warn "  All references must be updated together:"
      warn "  ${old_ns} -> ${new_ns}"
      warn "  ${config_old_ns} -> ${config_new_ns}"
      continue
    fi
    
    # If only one reference (the definition), safe to fix
    for file in "${reference_files[@]}"; do
      if grep -q "$old_ns" "$file"; then
        backup_and_edit "$file" "namespace realignment $old_ns -> $new_ns"
        
        if [[ "$DRY_RUN" == "false" ]]; then
          sed -i "s|$old_ns|$new_ns|g" "$file"
          # Also fix any config references in the same file
          sed -i "s|$config_old_ns|$config_new_ns|g" "$file"
          fixed "Realigned namespace in ${file#$REPO_ROOT/}: $(basename "$old_ns") -> $(basename "$new_ns")"
        fi
      fi
    done
  done
}

# Add diagnostic function
diagnose_fixable_issues() {
  log "🔍 Diagnosing fixable issues..."
  
  local kebab_count=0
  local header_count=0
  local legacy_count=0
  
  # Count kebab-case issues
  for file in "$REPO_ROOT/domains/home/apps/proton-authenticator/options.nix" \
              "$REPO_ROOT/domains/home/apps/proton-pass/options.nix" \
              "$REPO_ROOT/domains/home/apps/proton-mail/options.nix" \
              "$REPO_ROOT/domains/home/apps/gemini-cli/options.nix"; do
    if [[ -f "$file" ]] && grep -qE "(protonAuthenticator|protonPass|protonMail|geminiCli)" "$file"; then
      ((kebab_count++))
      debug "Found kebab-case issue in ${file#$REPO_ROOT/}"
    fi
  done
  
  # Count missing headers
  local index_files=(
    "domains/home/mail/bridge/index.nix"
    "domains/home/mail/notmuch/index.nix"
    "domains/home/mail/accounts/index.nix"
    "domains/home/mail/mbsync/index.nix"
    "domains/home/mail/msmtp/index.nix"
    "domains/home/apps/betterbird/index.nix"
    "domains/home/apps/dunst/index.nix"
    "domains/home/apps/proton-pass/index.nix"
    "domains/home/apps/kitty/index.nix"
    "domains/home/apps/hyprland/index.nix"
    "domains/home/apps/chromium/index.nix"
    "domains/home/apps/yazi/index.nix"
    "domains/home/apps/proton-mail/index.nix"
    "domains/home/apps/thunar/index.nix"
    "domains/home/apps/librewolf/index.nix"
    "domains/home/apps/neomutt/index.nix"
    "domains/home/apps/aerc/index.nix"
    "domains/home/apps/obsidian/index.nix"
    "domains/home/apps/waybar/index.nix"
  )
  
  for rel_file in "${index_files[@]}"; do
    local file="$REPO_ROOT/$rel_file"
    if [[ -f "$file" ]]; then
      local missing_headers=false
      grep -qE "#\s*OPTIONS" "$file" || missing_headers=true
      grep -qE "#\s*IMPLEMENTATION" "$file" || missing_headers=true
      grep -qE "#\s*VALIDATION" "$file" || missing_headers=true
      
      if [[ "$missing_headers" == "true" ]]; then
        ((header_count++))
        debug "Found missing headers in $rel_file"
      fi
    fi
  done
  
  # Count legacy headers
  while IFS= read -r -d '' file; do
    if grep -q "^# nixos-h\.\." "$file"; then
      ((legacy_count++))
      debug "Found legacy header in ${file#$REPO_ROOT/}"
    fi
  done < <(find "$REPO_ROOT/domains" -name "*.nix" -print0 2>/dev/null || true)
  
  echo
  log "📊 Fixable issues found:"
  echo "  🔧 Kebab-case namespace fixes: $kebab_count"
  echo "  📝 Missing section headers: $header_count" 
  echo "  💬 Legacy comment headers: $legacy_count"
  echo "  📄 writeScriptBin violations: Manual review required"
  echo
  
  if [[ $((kebab_count + header_count + legacy_count)) -eq 0 ]]; then
    success "No automatically fixable issues found!"
    log "Most remaining violations require manual intervention"
  fi
}
  if [[ "$DRY_RUN" == "true" ]]; then
    warn "🔍 DRY RUN MODE - No changes will be made"
  fi
  
  log "🚀 Starting HWC Charter auto-fix..."
  log "Repository: $REPO_ROOT"
  echo
  
  cd "$REPO_ROOT"
  
  # Run fixes in order of safety/impact
  fix_legacy_comment_headers
  fix_namespace_kebab_case  
  fix_simple_namespace_realignments
  fix_missing_section_headers
  fix_missing_options_files
  fix_writeScriptBin_violations
  
  echo
  if [[ "$DRY_RUN" == "true" ]]; then
    log "🔍 Dry run completed. Run without --dry-run to apply fixes."
  else
    success "🎉 Auto-fix completed! Applied $TOTAL_FIXES fixes."
    
    if [[ $TOTAL_FIXES -gt 0 ]]; then
      echo
      log "📝 Next steps:"
      echo "  1. Review changes: git diff"
      echo "  2. Test configuration: nixos-rebuild test"  
      echo "  3. Run linter again: ./scripts/lints/charter-lint.sh"
      echo "  4. Commit changes: git add -A && git commit -m 'fix: Charter compliance auto-fixes'"
    fi
  fi
  
  echo
  log "Manual fixes still needed:"
  echo "  - Complex namespace restructuring (system.core.paths, etc.)"
  echo "  - Moving options from single files to proper module structure" 
  echo "  - Lane purity violations requiring architectural changes"
  echo "  - writeScriptBin manual relocation"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
