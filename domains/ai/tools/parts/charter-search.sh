#!/usr/bin/env bash
# domains/ai/framework/parts/charter-search.sh
#
# Charter context retrieval using ripgrep
# Extracts relevant Charter sections based on changed files and task type

set -euo pipefail

# Configuration
CHARTER_PATH="${CHARTER_PATH:-/home/eric/.nixos/CHARTER.md}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_debug() {
  [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Extract domain from file path
get_domain() {
  local file_path="$1"

  # Extract domain from path like domains/ai/ollama/index.nix -> ai
  if [[ "$file_path" =~ domains/([^/]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "unknown"
  fi
}

# Extract module type from path
get_module_type() {
  local file_path="$1"

  # Check for specific file types
  case "$file_path" in
    */options.nix)       echo "options" ;;
    */index.nix)         echo "implementation" ;;
    */sys.nix)           echo "system-lane" ;;
    */parts/*)           echo "helper" ;;
    machines/*)          echo "machine-config" ;;
    profiles/*)          echo "profile" ;;
    *)                   echo "generic" ;;
  esac
}

# Search Charter for relevant sections
search_charter() {
  local file_path="${1:-.}"
  local task_type="${2:-doc}"  # commit/readme/doc/lint

  log_debug "Searching Charter for: file=$file_path, task=$task_type"

  if [[ ! -f "$CHARTER_PATH" ]]; then
    log_error "Charter not found at: $CHARTER_PATH"
    return 1
  fi

  local domain=$(get_domain "$file_path")
  local module_type=$(get_module_type "$file_path")

  log_debug "Detected: domain=$domain, module_type=$module_type"

  # Build search patterns based on task and file type
  local search_patterns=()

  case "$task_type" in
    commit)
      # Commit messages: namespace, structure, conventions
      search_patterns+=(
        "Law 2.*Namespace Fidelity"
        "Law.*Module Anatomy"
        "Preserve-First Doctrine"
      )
      ;;

    readme)
      # README generation: architecture, domain boundaries
      search_patterns+=(
        "Law.*Namespace"
        "Domain.*${domain}"
        "Module Anatomy"
      )
      ;;

    doc|documentation)
      # Full documentation: comprehensive context
      search_patterns+=(
        "Law [0-9]:"
        "Domain.*${domain}"
        "${module_type}"
      )
      ;;

    lint|validate)
      # Validation: all laws and boundaries
      search_patterns+=(
        "Law [0-9]:"
        "Violation:"
        "Domain Boundaries"
      )
      ;;

    *)
      # Generic: core laws
      search_patterns+=(
        "Law [0-9]:"
        "Preserve-First"
      )
      ;;
  esac

  # Add file-type-specific patterns
  case "$module_type" in
    options)
      search_patterns+=("options\.nix" "API definition")
      ;;
    implementation)
      search_patterns+=("IMPLEMENTATION" "VALIDATION")
      ;;
    system-lane)
      search_patterns+=("sys\.nix" "System-lane")
      ;;
  esac

  # Execute searches and collect unique results
  local results=""
  for pattern in "${search_patterns[@]}"; do
    log_debug "Searching pattern: $pattern"

    # Search with context (3 lines after each match)
    local matches=$(rg -i "$pattern" "$CHARTER_PATH" -A 3 2>/dev/null || true)

    if [[ -n "$matches" ]]; then
      results+="$matches"$'\n\n'
    fi
  done

  # Deduplicate and format
  if [[ -z "$results" ]]; then
    # Fallback: return core laws
    log_debug "No specific matches, returning core laws"
    rg -i "^## [0-9]\..*Doctrine|^### Law [0-9]:" "$CHARTER_PATH" -A 2 2>/dev/null || echo "Charter context not available"
  else
    echo "$results" | head -n 50  # Limit to 50 lines to avoid token overflow
  fi
}

# Extract specific law by number
get_law() {
  local law_number="$1"

  if [[ ! -f "$CHARTER_PATH" ]]; then
    log_error "Charter not found at: $CHARTER_PATH"
    return 1
  fi

  # Search for "### Law N:" and get next 10 lines
  rg "^### Law ${law_number}:" "$CHARTER_PATH" -A 10 2>/dev/null || {
    log_error "Law $law_number not found"
    return 1
  }
}

# List all laws
list_laws() {
  if [[ ! -f "$CHARTER_PATH" ]]; then
    log_error "Charter not found at: $CHARTER_PATH"
    return 1
  fi

  # Extract law headers
  rg "^### Law [0-9]+:" "$CHARTER_PATH" 2>/dev/null || {
    log_error "No laws found in Charter"
    return 1
  }
}

# Validate file against Charter rules
validate_file() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    log_error "File not found: $file_path"
    return 1
  fi

  local domain=$(get_domain "$file_path")
  local violations=()

  # Check Law 2: Namespace Fidelity
  if [[ "$file_path" =~ domains/([^/]+)/([^/]+) ]]; then
    local path_namespace="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"

    # Search for option definitions
    local option_namespaces=$(rg "options\.hwc\.([a-zA-Z0-9\.]+)" "$file_path" -o -r '$1' 2>/dev/null || true)

    if [[ -n "$option_namespaces" ]]; then
      while IFS= read -r ns; do
        if [[ ! "$ns" =~ ^${path_namespace} ]]; then
          violations+=("Namespace mismatch: options.hwc.$ns doesn't match path $path_namespace")
        fi
      done <<< "$option_namespaces"
    fi
  fi

  # Check Law 3: Path Abstraction (no hardcoded paths)
  local hardcoded_paths=$(rg '"/mnt/|/home/eric/|/opt/' "$file_path" 2>/dev/null || true)
  if [[ -n "$hardcoded_paths" ]]; then
    violations+=("Hardcoded path detected (violates Law 3)")
  fi

  # Report violations
  if [[ ${#violations[@]} -gt 0 ]]; then
    echo "Charter violations found in $file_path:"
    printf '%s\n' "${violations[@]}"
    return 1
  else
    echo "✅ No Charter violations detected"
    return 0
  fi
}

# Main entry point
main() {
  local command="${1:-search}"
  shift || true

  case "$command" in
    search)
      search_charter "$@"
      ;;
    law)
      get_law "$@"
      ;;
    list)
      list_laws
      ;;
    validate)
      validate_file "$@"
      ;;
    help|--help|-h)
      cat <<EOF
Charter Search Tool - Extract relevant Charter sections for AI context

USAGE:
    charter-search <command> [options]

COMMANDS:
    search <file> <task>   Search for relevant Charter sections
                           task: commit|readme|doc|lint

    law <number>           Get specific law by number

    list                   List all Charter laws

    validate <file>        Check file for Charter violations

    help                   Show this help message

EXAMPLES:
    charter-search search domains/ai/ollama/index.nix doc
    charter-search law 2
    charter-search list
    charter-search validate domains/ai/ollama/options.nix

ENVIRONMENT:
    CHARTER_PATH           Path to Charter document (default: /home/eric/.nixos/CHARTER.md)
    VERBOSE                Enable debug output (default: false)
EOF
      ;;
    *)
      log_error "Unknown command: $command"
      log_error "Run 'charter-search help' for usage"
      return 1
      ;;
  esac
}

main "$@"
