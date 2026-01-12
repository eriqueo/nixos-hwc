#!/usr/bin/env bash
# domains/ai/framework/parts/ollama-wrapper.sh
#
# Thermal-aware Ollama wrapper with Charter integration
# Replaces separate dispatcher service with simple shell logic

set -euo pipefail

# Configuration (overridable by environment)
OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://localhost:11434}"
CHARTER_PATH="${CHARTER_PATH:-/home/eric/.nixos/CHARTER.md}"
LOG_DIR="${LOG_DIR:-/var/log/hwc-ai}"
THERMAL_WARNING="${THERMAL_WARNING:-75}"
THERMAL_CRITICAL="${THERMAL_CRITICAL:-85}"
PROFILE="${PROFILE:-auto}"
VERBOSE="${VERBOSE:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Logging
log_info() { echo -e "${GREEN}✅${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $*"; }
log_error() { echo -e "${RED}❌${NC} $*" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $*" >&2 || true; }
log_header() { echo -e "\n${BOLD}${BLUE}$*${NC}"; }

# Ensure log directory exists
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Get CPU temperature
get_temp() {
  # Try multiple methods to get CPU temperature
  local temp=0

  # Method 1: sensors (most reliable)
  if command -v sensors >/dev/null 2>&1; then
    temp=$(sensors 2>/dev/null | grep -E 'Package id 0|CPU:' | grep -oP '\+\K[0-9]+' | head -n1 || echo 0)
  fi

  # Method 2: /sys/class/thermal (fallback)
  if [[ $temp -eq 0 ]] && [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
  fi

  # Method 3: /proc/acpi (old systems)
  if [[ $temp -eq 0 ]] && [[ -f /proc/acpi/thermal_zone/THM0/temperature ]]; then
    temp=$(cat /proc/acpi/thermal_zone/THM0/temperature | grep -oP '[0-9]+' | head -n1 || echo 0)
  fi

  echo "$temp"
}

# Check thermal safety
check_thermal() {
  local temp=$(get_temp)

  log_debug "Current CPU temperature: ${temp}°C"

  if [[ $temp -eq 0 ]]; then
    log_warn "Could not read CPU temperature, proceeding with caution"
    echo "unknown"
    return 0
  fi

  if [[ $temp -gt $THERMAL_CRITICAL ]]; then
    log_error "🚨 ABORT: CPU at ${temp}°C (critical: ${THERMAL_CRITICAL}°C)"
    notify-send "AI Task Aborted" "CPU too hot: ${temp}°C" -u critical 2>/dev/null || true
    return 1
  fi

  if [[ $temp -gt $THERMAL_WARNING ]]; then
    log_warn "⚠️  High temperature: ${temp}°C (warning: ${THERMAL_WARNING}°C)"
    log_warn "Forcing smallest model for safety"
    echo "hot"
    return 0
  fi

  log_debug "Temperature OK: ${temp}°C"
  echo "ok"
  return 0
}

# Select model based on task complexity and thermal state
select_model() {
  local task_complexity="${1:-medium}"  # small/medium/large
  local thermal_state="${2:-ok}"        # ok/hot/unknown
  local profile="${3:-auto}"            # auto/laptop/server/cpu-only

  log_debug "Selecting model: complexity=$task_complexity, thermal=$thermal_state, profile=$profile"

  # Thermal override: always use smallest model if hot
  if [[ "$thermal_state" == "hot" ]]; then
    echo "llama3.2:1b"
    return
  fi

  # Profile-based selection
  case "$profile:$task_complexity" in
    # Laptop profiles
    laptop:small|auto:small)       echo "llama3.2:1b" ;;
    laptop:medium|auto:medium)     echo "llama3.2:3b" ;;
    laptop:large|auto:large)       echo "phi3.5:3.8b" ;;

    # Server profiles
    server:small)                  echo "llama3.2:3b" ;;
    server:medium)                 echo "qwen2.5-coder:7b" ;;
    server:large)                  echo "qwen2.5-coder:14b" ;;

    # CPU-only profiles
    cpu-only:small)                echo "llama3.2:1b" ;;
    cpu-only:medium)               echo "llama3.2:1b" ;;
    cpu-only:large)                echo "llama3.2:3b" ;;

    # Default fallback
    *)                             echo "llama3.2:3b" ;;
  esac
}

# Get Charter context using charter-search.sh
get_charter_context() {
  local file_path="${1:-.}"
  local task_type="${2:-doc}"

  log_debug "Getting Charter context for: file=$file_path, task=$task_type"

  # Check if charter-search is available
  if ! command -v charter-search >/dev/null 2>&1; then
    log_warn "charter-search not found, using fallback"
    # Simple fallback: just grep for Laws
    if [[ -f "$CHARTER_PATH" ]]; then
      grep -A 3 "^### Law [0-9]:" "$CHARTER_PATH" | head -n 30 || echo "Charter context not available"
    else
      echo "Charter not found at $CHARTER_PATH"
    fi
    return
  fi

  # Use charter-search tool
  CHARTER_PATH="$CHARTER_PATH" charter-search search "$file_path" "$task_type" 2>/dev/null || {
    log_warn "Charter search failed, using minimal context"
    echo "Charter context unavailable"
  }
}

# Check if Ollama is available
check_ollama() {
  if ! curl -s --connect-timeout 2 "$OLLAMA_ENDPOINT/api/tags" >/dev/null 2>&1; then
    log_error "Ollama not available at $OLLAMA_ENDPOINT"
    log_error "Start Ollama with: systemctl start podman-ollama.service"
    return 1
  fi
  return 0
}

# Execute Ollama request with thermal monitoring
execute_ollama() {
  local model="$1"
  local prompt="$2"
  local timeout="${3:-60}"
  local log_file="${4:-}"

  log_header "🤖 Executing AI Task"
  log_info "Model: $model"
  log_info "Timeout: ${timeout}s"
  log_info "Temperature: $(get_temp)°C"

  # Start thermal monitoring in background
  local monitor_running=true
  (
    while $monitor_running; do
      local temp=$(get_temp)
      if [[ $temp -gt $THERMAL_CRITICAL ]]; then
        log_error "🚨 Emergency stop at ${temp}°C!"
        notify-send "AI Emergency Stop" "CPU critical: ${temp}°C" -u critical 2>/dev/null || true
        # Kill the curl process
        pkill -f "curl.*$OLLAMA_ENDPOINT" || true
        exit 1
      fi
      sleep 5
    done
  ) &
  local monitor_pid=$!

  # Prepare request JSON
  local request_json=$(jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    '{
      model: $model,
      prompt: $prompt,
      stream: false,
      options: {
        temperature: 0.2,
        num_predict: 2000
      }
    }')

  # Execute request with timeout
  log_debug "Sending request to Ollama..."
  local response
  local exit_code=0

  response=$(timeout "$timeout" curl -s -X POST \
    "$OLLAMA_ENDPOINT/api/generate" \
    -H "Content-Type: application/json" \
    -d "$request_json" 2>&1) || exit_code=$?

  # Stop thermal monitor
  monitor_running=false
  kill $monitor_pid 2>/dev/null || true
  wait $monitor_pid 2>/dev/null || true

  # Check execution result
  if [[ $exit_code -ne 0 ]]; then
    if [[ $exit_code -eq 124 ]]; then
      log_error "Request timed out after ${timeout}s"
    else
      log_error "Request failed with exit code $exit_code"
    fi
    return 1
  fi

  # Extract response
  local ai_response=$(echo "$response" | jq -r '.response' 2>/dev/null || echo "")

  if [[ -z "$ai_response" ]] || [[ "$ai_response" == "null" ]]; then
    log_error "Empty or invalid response from Ollama"
    log_debug "Raw response: $response"
    return 1
  fi

  # Log to file if specified
  if [[ -n "$log_file" ]]; then
    {
      echo "# AI Task Execution Log"
      echo "Timestamp: $(date)"
      echo "Model: $model"
      echo "Temperature: $(get_temp)°C"
      echo "---"
      echo "$ai_response"
    } >> "$log_file" 2>/dev/null || log_warn "Failed to write log file"
  fi

  # Output response
  echo "$ai_response"

  log_info "Task completed successfully"
  log_info "Final temperature: $(get_temp)°C"
}

# Main workflow
main() {
  local task_type="${1:-doc}"        # doc/commit/readme/lint
  local complexity="${2:-medium}"     # small/medium/large
  local file_path="${3:-.}"          # File being documented/analyzed
  local output_file="${4:-}"         # Optional output file

  log_header "🚀 AI Framework - Thermal-Aware Execution"

  # Check Ollama availability
  check_ollama || exit 1

  # Thermal check
  local thermal_state
  thermal_state=$(check_thermal) || exit 1

  # Select model
  local model
  model=$(select_model "$complexity" "$thermal_state" "$PROFILE")
  log_info "Selected model: $model (profile: $PROFILE)"

  # Get Charter context
  log_info "Retrieving Charter context..."
  local charter_context
  charter_context=$(get_charter_context "$file_path" "$task_type")

  # Build prompt based on task type
  local prompt
  case "$task_type" in
    commit)
      prompt="You are a NixOS expert generating commit documentation.

Charter Context (follow these rules):
$charter_context

Task: Generate commit message documentation for changes in: $file_path

Include:
1. Summary of changes
2. Relevant Charter Law citations
3. Impact analysis
4. Validation checks

Keep it concise and cite specific Laws."
      ;;

    readme)
      prompt="You are a NixOS expert generating README documentation.

Charter Context (follow these rules):
$charter_context

Task: Generate README for: $file_path

Include:
1. Module purpose and overview
2. Configuration options
3. Charter compliance notes (cite specific Laws)
4. Example usage
5. Dependencies

Follow Charter v9.1 standards."
      ;;

    doc|documentation)
      prompt="You are a NixOS expert documenting system changes.

Charter Context (follow these rules):
$charter_context

Task: Generate documentation for: $file_path

Include:
1. What changed and why
2. Charter compliance verification (cite specific Laws)
3. Impact on other modules
4. Configuration examples
5. Troubleshooting tips

Be specific and actionable."
      ;;

    lint|validate)
      prompt="You are a NixOS expert validating Charter compliance.

Charter Context (all rules):
$charter_context

Task: Check $file_path for Charter violations

Analyze:
1. Namespace alignment (Law 2)
2. Path abstraction usage (Law 3)
3. Module anatomy (OPTIONS/IMPLEMENTATION/VALIDATION)
4. Permission model (Law 4)

Report any violations with Law citations."
      ;;

    *)
      log_error "Unknown task type: $task_type"
      log_error "Valid types: commit, readme, doc, lint"
      exit 1
      ;;
  esac

  # Execute with appropriate timeout
  local timeout
  case "$task_type" in
    commit|lint) timeout=30 ;;
    readme)      timeout=60 ;;
    doc)         timeout=90 ;;
    *)           timeout=60 ;;
  esac

  # Log file
  local log_file="$LOG_DIR/task-$(date +%Y%m%d-%H%M%S).log"

  # Execute
  local result
  result=$(execute_ollama "$model" "$prompt" "$timeout" "$log_file") || exit 1

  # Output result
  if [[ -n "$output_file" ]]; then
    echo "$result" > "$output_file"
    log_info "Output saved to: $output_file"
  else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "$result"
    echo "═══════════════════════════════════════════════════════════════"
  fi

  log_info "Log saved to: $log_file"
}

# Show usage
show_usage() {
  cat <<EOF
${BOLD}Ollama Wrapper - Thermal-Aware AI Execution${NC}

USAGE:
    ollama-wrapper <task> <complexity> <file> [output]

ARGUMENTS:
    task         Task type: commit|readme|doc|lint
    complexity   Model size: small|medium|large
    file         File path for context
    output       Optional output file

EXAMPLES:
    ollama-wrapper doc medium domains/ai/ollama/index.nix
    ollama-wrapper commit small domains/ai/framework/options.nix
    ollama-wrapper readme large domains/ai/ README.md

ENVIRONMENT:
    OLLAMA_ENDPOINT      Ollama API URL (default: http://localhost:11434)
    CHARTER_PATH         Charter document path
    THERMAL_WARNING      Warning temperature (default: 75°C)
    THERMAL_CRITICAL     Critical temperature (default: 85°C)
    PROFILE              Hardware profile: auto|laptop|server|cpu-only
    VERBOSE              Enable debug output (default: false)
    LOG_DIR              Log directory (default: /var/log/hwc-ai)

THERMAL SAFETY:
    - Monitors CPU temperature every 5 seconds
    - Downgrades to smallest model if temp > warning
    - Aborts immediately if temp > critical
    - Logs all temperature readings

CHARTER INTEGRATION:
    - Automatically retrieves relevant Charter sections
    - Injects context into AI prompts
    - Validates compliance (lint mode)
    - Cites specific Laws in outputs
EOF
}

# Entry point
if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  show_usage
  exit 0
fi

main "$@"
