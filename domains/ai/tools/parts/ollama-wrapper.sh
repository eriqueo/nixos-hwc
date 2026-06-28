#!/usr/bin/env bash
# domains/ai/framework/parts/ollama-wrapper.sh
#
# Thermal-aware llama.cpp wrapper with Charter integration
# Talks to llama.cpp's OpenAI-compatible server (/v1/chat/completions).
# Replaces separate dispatcher service with simple shell logic

set -euo pipefail

# Configuration (overridable by environment)
LLM_ENDPOINT="${LLM_ENDPOINT:-http://127.0.0.1:11500}"   # llama.cpp OpenAI server (llama-gpu)
LLM_MODEL="${LLM_MODEL:-lfm2-2.6b}"                       # --alias served by llama-gpu
CHARTER_PATH="${CHARTER_PATH:-/home/eric/.nixos/CHARTER.md}"
LOG_DIR="${LOG_DIR:-/var/log/hwc-ai}"
THERMAL_WARNING="${THERMAL_WARNING:-75}"
THERMAL_CRITICAL="${THERMAL_CRITICAL:-85}"
# The dGPU now does the inference, so watch its temperature too (80/90 °C).
GPU_WARN="${GPU_WARN:-80}"
GPU_CRIT="${GPU_CRIT:-90}"
PROFILE="${PROFILE:-auto}"
VERBOSE="${VERBOSE:-false}"
NPU_ENABLED="${NPU_ENABLED:-false}"
AI_FORCE_NPU="${AI_FORCE_NPU:-false}"
AI_NPU_BIN="${AI_NPU_BIN:-ai-npu}"
HWC_NPU_MODEL_DIR="${HWC_NPU_MODEL_DIR:-}"

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

# Get NVIDIA dGPU temperature in °C. Best-effort: empty string if nvidia-smi
# is absent or fails, in which case GPU thermal checks are skipped.
gpu_temp() {
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1
}

# Check thermal safety (CPU + dGPU). Pre-flight gate before dispatching a task.
check_thermal() {
  local temp=$(get_temp)
  local gtemp=$(gpu_temp)

  log_debug "Current CPU temperature: ${temp}°C; GPU: ${gtemp:-n/a}°C"

  # GPU critical → abort. The dGPU runs the inference now, so it is the primary
  # heat source; CPU stays secondary.
  if [[ -n "$gtemp" ]] && [[ "$gtemp" -gt $GPU_CRIT ]]; then
    log_error "🚨 ABORT: GPU at ${gtemp}°C (critical: ${GPU_CRIT}°C)"
    notify-send "AI Task Aborted" "GPU too hot: ${gtemp}°C" -u critical 2>/dev/null || true
    return 1
  fi

  if [[ $temp -gt $THERMAL_CRITICAL ]]; then
    log_error "🚨 ABORT: CPU at ${temp}°C (critical: ${THERMAL_CRITICAL}°C)"
    notify-send "AI Task Aborted" "CPU too hot: ${temp}°C" -u critical 2>/dev/null || true
    return 1
  fi

  if [[ $temp -eq 0 ]] && [[ -z "$gtemp" ]]; then
    log_warn "Could not read CPU or GPU temperature, proceeding with caution"
    echo "unknown"
    return 0
  fi

  # Warnings: log and proceed. Only one chat model (lfm2-2.6b) is served, so
  # there is NO smaller model to downgrade to — we warn but do not throttle.
  if [[ -n "$gtemp" ]] && [[ "$gtemp" -gt $GPU_WARN ]]; then
    log_warn "⚠️  High GPU temperature: ${gtemp}°C (warning: ${GPU_WARN}°C) — no downgrade target, proceeding"
  fi
  if [[ $temp -gt $THERMAL_WARNING ]]; then
    log_warn "⚠️  High CPU temperature: ${temp}°C (warning: ${THERMAL_WARNING}°C) — no downgrade target, proceeding"
  fi

  log_debug "Temperature OK: CPU ${temp}°C / GPU ${gtemp:-n/a}°C"
  echo "ok"
  return 0
}

# Select model. The laptop's llama-gpu serves exactly one chat alias
# (lfm2-2.6b), so every task maps to it — there is no complexity/thermal-based
# model swap any more. Args kept for call-site compatibility and a possible
# future multi-model setup.
select_model() {
  local task_complexity="${1:-medium}"  # accepted, unused
  local thermal_state="${2:-ok}"        # accepted, unused
  local profile="${3:-auto}"            # accepted, unused

  log_debug "Selecting model: complexity=$task_complexity, thermal=$thermal_state, profile=$profile -> $LLM_MODEL"
  echo "$LLM_MODEL"
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

# Check if the llama.cpp server is reachable
check_llm() {
  if ! curl -s --connect-timeout 2 "$LLM_ENDPOINT/v1/models" >/dev/null 2>&1; then
    log_error "llama.cpp server not reachable at $LLM_ENDPOINT"
    log_error "Check: systemctl status llama-gpu.service"
    return 1
  fi
  return 0
}

should_use_npu() {
  local prompt="$1"
  local complexity="$2"

  if [[ "$NPU_ENABLED" != "true" ]]; then
    return 1
  fi

  if [[ "$AI_FORCE_NPU" == "true" ]]; then
    return 0
  fi

  if [[ "$complexity" == "large" ]]; then
    return 1
  fi

  # Skip NPU for long or explicitly complex prompts
  local len=${#prompt}
  if (( len >= 8000 )); then
    return 1
  fi

  if echo "$prompt" | grep -qiE "(^|[^A-Za-z0-9])(large|complex|deep)([^A-Za-z0-9]|$)"; then
    return 1
  fi

  return 0
}

execute_npu() {
  local prompt="$1"
  local log_file="$2"

  if ! command -v "$AI_NPU_BIN" >/dev/null 2>&1; then
    log_error "NPU requested but ai-npu binary not found"
    return 1
  fi

  log_header "⚡ Executing AI Task on NPU"
  log_info "Model dir: ${HWC_NPU_MODEL_DIR:-"(default)"}"

  local response
  if ! response=$(printf "%s" "$prompt" | "$AI_NPU_BIN"); then
    log_error "NPU execution failed"
    return 1
  fi

  if [[ -n "$log_file" ]]; then
    {
      echo "# AI NPU Task Execution Log"
      echo "Timestamp: $(date)"
      echo "Model dir: ${HWC_NPU_MODEL_DIR:-"(default)"}"
      echo "---"
      echo "$response"
    } >> "$log_file" 2>/dev/null || log_warn "Failed to write NPU log file"
  fi

  echo "$response"
  return 0
}

# Execute a chat completion against llama.cpp with thermal monitoring
execute_llm() {
  local model="$1"
  local prompt="$2"
  local timeout="${3:-60}"
  local log_file="${4:-}"

  log_header "🤖 Executing AI Task"
  log_info "Model: $model"
  log_info "Timeout: ${timeout}s"
  log_info "Temperature: CPU $(get_temp)°C / GPU $(gpu_temp)°C"

  # Start thermal monitoring in background (dGPU primary, CPU secondary)
  local monitor_running=true
  (
    while $monitor_running; do
      local temp=$(get_temp)
      local gtemp=$(gpu_temp)
      if [[ -n "$gtemp" ]] && [[ "$gtemp" -gt $GPU_CRIT ]]; then
        log_error "🚨 Emergency stop at GPU ${gtemp}°C!"
        notify-send "AI Emergency Stop" "GPU critical: ${gtemp}°C" -u critical 2>/dev/null || true
        pkill -f "curl.*$LLM_ENDPOINT" || true
        exit 1
      fi
      if [[ $temp -gt $THERMAL_CRITICAL ]]; then
        log_error "🚨 Emergency stop at CPU ${temp}°C!"
        notify-send "AI Emergency Stop" "CPU critical: ${temp}°C" -u critical 2>/dev/null || true
        pkill -f "curl.*$LLM_ENDPOINT" || true
        exit 1
      fi
      sleep 5
    done
  ) &
  local monitor_pid=$!

  # Prepare request JSON (OpenAI /v1/chat/completions shape)
  local request_json=$(jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    '{
      model: $model,
      messages: [ { role: "user", content: $prompt } ],
      temperature: 0.2,
      max_tokens: 2000,
      stream: false
    }')

  # Execute request with timeout
  log_debug "Sending request to llama.cpp..."
  local response
  local exit_code=0

  response=$(timeout "$timeout" curl -sS -X POST \
    "$LLM_ENDPOINT/v1/chat/completions" \
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

  # Extract response (OpenAI shape)
  local ai_response=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo "")

  if [[ -z "$ai_response" ]]; then
    log_error "Empty or invalid response from llama.cpp"
    log_debug "Raw response: $response"
    return 1
  fi

  # Log to file if specified
  if [[ -n "$log_file" ]]; then
    {
      echo "# AI Task Execution Log"
      echo "Timestamp: $(date)"
      echo "Model: $model"
      echo "Temperature: CPU $(get_temp)°C / GPU $(gpu_temp)°C"
      echo "---"
      echo "$ai_response"
    } >> "$log_file" 2>/dev/null || log_warn "Failed to write log file"
  fi

  # Output response
  echo "$ai_response"

  log_info "Task completed successfully"
  log_info "Final temperature: CPU $(get_temp)°C / GPU $(gpu_temp)°C"
}

# Main workflow
main() {
  if [[ "${1:-}" == "--npu" ]]; then
    AI_FORCE_NPU="true"
    shift
  fi

  local task_type="${1:-doc}"        # doc/commit/readme/lint
  local complexity="${2:-medium}"     # small/medium/large
  local file_path="${3:-.}"          # File being documented/analyzed
  local output_file="${4:-}"         # Optional output file

  log_header "🚀 AI Framework - Thermal-Aware Execution"

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

  local use_npu="false"
  if should_use_npu "$prompt" "$complexity"; then
    use_npu="true"
  fi

  # Execute
  local result
  if [[ "$use_npu" == "true" ]]; then
    result=$(execute_npu "$prompt" "$log_file") || exit 1
  else
    check_llm || exit 1
    result=$(execute_llm "$model" "$prompt" "$timeout" "$log_file") || exit 1
  fi

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
${BOLD}llama.cpp Wrapper - Thermal-Aware AI Execution${NC}

USAGE:
    ollama-wrapper [--npu] <task> <complexity> <file> [output]

ARGUMENTS:
    --npu        Force Tier 0 NPU path (bypass Ollama)
    task         Task type: commit|readme|doc|lint
    complexity   Model size: small|medium|large
    file         File path for context
    output       Optional output file

EXAMPLES:
    ollama-wrapper doc medium domains/ai/ollama/index.nix
    ollama-wrapper commit small domains/ai/framework/options.nix
    ollama-wrapper readme large domains/ai/ README.md

ENVIRONMENT:
    LLM_ENDPOINT         llama.cpp OpenAI server URL (default: http://127.0.0.1:11500)
    LLM_MODEL            Chat model alias (default: lfm2-2.6b)
    CHARTER_PATH         Charter document path
    THERMAL_WARNING      CPU warning temperature (default: 75°C)
    THERMAL_CRITICAL     CPU critical temperature (default: 85°C)
    GPU_WARN             GPU warning temperature (default: 80°C)
    GPU_CRIT             GPU critical temperature (default: 90°C)
    PROFILE              Hardware profile: auto|laptop|server|cpu-only
    VERBOSE              Enable debug output (default: false)
    LOG_DIR              Log directory (default: /var/log/hwc-ai)
    NPU_ENABLED          Enable Tier 0 NPU path when true
    AI_FORCE_NPU         Force NPU path (auto-routing otherwise)
    AI_NPU_BIN           Override ai-npu binary (default: ai-npu)
    HWC_NPU_MODEL_DIR    Override NPU model directory

THERMAL SAFETY:
    - Monitors GPU (primary) and CPU temperature every 5 seconds
    - Only one chat model is served, so a warning logs but does NOT throttle
      (no smaller model to downgrade to)
    - Aborts immediately if GPU > GPU_CRIT or CPU > THERMAL_CRITICAL,
      killing any in-flight request
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
