#!/usr/bin/env bash
# journal-errors - Advanced system error analysis and summarization
#
# Usage: journal-errors [OPTIONS] [TIME-WINDOW] [SERVICE]
#
# Options:
#   --show-all          Bypass all exclusion filters
#   --warnings          Include warning-level messages
#   --severity          Show severity classification
#   --patterns          Show detected error patterns
#   --context           Show extended context for critical errors
#   --trends            Show time-based error trends
#   --health            Show service health correlation
#   --containers        Analyze podman container logs directly
#   --verbose           Enable all analysis features (including containers)
#
# Examples:
#   journal-errors                                  # Last 10 minutes, errors only
#   journal-errors --warnings                       # Include warnings
#   journal-errors --verbose "1 hour ago"           # Full analysis, last hour
#   journal-errors "1 hour ago" tdarr               # Last hour, tdarr service only
#   journal-errors --patterns --severity            # Pattern detection + severity
#   journal-errors "10 minutes ago" "" --show-all   # Bypass all filters
#   journal-errors --containers "1 hour ago"        # Analyze container logs
#
# Configuration:
#   Edit EXCLUDE_SERVICES and EXCLUDE_PATTERNS arrays below to customize filtering
#
# Dependencies: journalctl, awk, sed, grep, wc, sort, uniq, tail, date, jq (standard on NixOS)
# Optional: podman (for --containers flag)
# Location: workspace/monitoring/journal-errors.sh
# Invoked by: Shell wrapper in domains/home/environment/shell/parts/journal-errors.nix

set -euo pipefail

#==============================================================================
# DEPENDENCY VERIFICATION
#==============================================================================
# Standard tools - should always exist on NixOS, but verify for robustness

REQUIRED_COMMANDS=(journalctl awk sed grep wc sort uniq tail date jq)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' not found" >&2
    echo "This should not happen on a standard NixOS system." >&2
    exit 127
  fi
done

# Optional: Check for podman (used with --containers flag)
PODMAN_AVAILABLE=false
if command -v podman &>/dev/null; then
  PODMAN_AVAILABLE=true
fi

#==============================================================================
# CONFIGURATION
#==============================================================================

# Parse arguments
TIME_WINDOW=""
SERVICE=""
SHOW_ALL=false
INCLUDE_WARNINGS=false
SHOW_SEVERITY=false
SHOW_PATTERNS=false
SHOW_CONTEXT=false
SHOW_TRENDS=false
SHOW_HEALTH=false
SHOW_CONTAINERS=false

for arg in "$@"; do
  case "$arg" in
    --show-all)
      SHOW_ALL=true
      ;;
    --warnings)
      INCLUDE_WARNINGS=true
      ;;
    --severity)
      SHOW_SEVERITY=true
      ;;
    --patterns)
      SHOW_PATTERNS=true
      ;;
    --context)
      SHOW_CONTEXT=true
      ;;
    --trends)
      SHOW_TRENDS=true
      ;;
    --health)
      SHOW_HEALTH=true
      ;;
    --containers)
      SHOW_CONTAINERS=true
      ;;
    --verbose)
      SHOW_SEVERITY=true
      SHOW_PATTERNS=true
      SHOW_CONTEXT=true
      SHOW_TRENDS=true
      SHOW_HEALTH=true
      SHOW_CONTAINERS=true
      ;;
    --*)
      echo "Unknown option: $arg" >&2
      echo "Run with no arguments to see basic usage" >&2
      exit 1
      ;;
    *)
      if [ -z "$TIME_WINDOW" ]; then
        TIME_WINDOW="$arg"
      elif [ -z "$SERVICE" ]; then
        SERVICE="$arg"
      fi
      ;;
  esac
done

# Set defaults
TIME_WINDOW="${TIME_WINDOW:-10 minutes ago}"

# Exclusion patterns (grep -E compatible regex)
# Add services or patterns to exclude from error reports
EXCLUDE_SERVICES=(
  "soularr"
)

EXCLUDE_PATTERNS=(
  "INFO\|"
  "DEBUG\|"
  "\[INFO"
  "\[DEBUG"
  "No releases wanted"
  "Server stats"
  "No expired messages"
  "No expired attachments"
  "Removed 0 empty topic"
  "Deleted 0 stale visitor"
  "Manager finished"
  "Pruned messages"
)

# Critical patterns that should never be filtered (even with exclusions)
CRITICAL_PATTERNS=(
  "segmentation fault"
  "segfault"
  "kernel panic"
  "out of memory"
  "oom-kill"
  "failed to start"
  "core dumped"
  "cannot allocate memory"
)

# Container-specific error patterns
CONTAINER_ERROR_PATTERNS=(
  "ECONNREFUSED"
  "ETIMEDOUT"
  "ENOTFOUND"
  "database.*connection.*failed"
  "database.*timeout"
  "connection.*refused"
  "Error:"
  "ERROR:"
  "Exception"
  "EXCEPTION"
  "Fatal:"
  "FATAL:"
  "Traceback"
  "exit code [1-9]"
  "exited with error"
  "health check failed"
  "failed to connect"
  "connection timeout"
  "stack trace"
  "StackTrace"
  "at [a-zA-Z0-9_]+\.[a-zA-Z0-9_]+\([^)]*:[0-9]+:[0-9]+\)"
  "HTTP [45][0-9]{2}"
  "status code [45][0-9]{2}"
  "Cannot connect to"
  "Unable to connect"
  "Address already in use"
  "EADDRINUSE"
  "NullPointerException"
  "RuntimeException"
  "SQLException"
)

# Colors
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

# Check if a line contains any critical pattern
is_critical() {
  local line="$1"
  local line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')

  for pattern in "${CRITICAL_PATTERNS[@]}"; do
    if echo "$line_lower" | grep -qi "$pattern"; then
      return 0
    fi
  done
  return 1
}

# Classify error severity based on patterns
classify_severity() {
  local line="$1"
  local line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')

  # CRITICAL: System-threatening errors
  if echo "$line_lower" | grep -Eq "kernel panic|oom-kill|segfault|segmentation fault|core dumped"; then
    echo "CRITICAL"
    return
  fi

  # HIGH: Service failures, security issues
  if echo "$line_lower" | grep -Eq "failed to start|cannot start|fatal|panic|out of memory|permission denied|connection refused|authentication failed"; then
    echo "HIGH"
    return
  fi

  # MEDIUM: Recoverable errors, warnings
  if echo "$line_lower" | grep -Eq "warning|timeout|retry|failed to connect|temporary failure|not found"; then
    echo "MEDIUM"
    return
  fi

  # LOW: Minor issues
  echo "LOW"
}

# Detect error patterns
detect_pattern() {
  local line="$1"
  local line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')

  # Service start/restart failures
  if echo "$line_lower" | grep -Eq "failed to start|start request repeated|unit .* failed"; then
    echo "SERVICE_START_FAILURE"
    return
  fi

  # OOM events
  if echo "$line_lower" | grep -Eq "out of memory|oom-kill|memory allocation failed|cannot allocate memory"; then
    echo "OUT_OF_MEMORY"
    return
  fi

  # Permission errors
  if echo "$line_lower" | grep -Eq "permission denied|access denied|not permitted|cannot access"; then
    echo "PERMISSION_DENIED"
    return
  fi

  # Network/connection failures
  if echo "$line_lower" | grep -Eq "connection refused|connection timeout|network unreachable|failed to connect|no route to host"; then
    echo "NETWORK_FAILURE"
    return
  fi

  # Segmentation faults
  if echo "$line_lower" | grep -Eq "segfault|segmentation fault|core dumped"; then
    echo "SEGFAULT"
    return
  fi

  # Container/Podman errors
  if echo "$line_lower" | grep -Eq "podman|container .* died|container .* failed|image pull failed"; then
    echo "CONTAINER_ERROR"
    return
  fi

  # Disk/filesystem errors
  if echo "$line_lower" | grep -Eq "no space left|disk full|filesystem.*full|i/o error|read-only file system"; then
    echo "DISK_ERROR"
    return
  fi

  # Authentication/security
  if echo "$line_lower" | grep -Eq "authentication failed|invalid.*key|certificate.*invalid|ssl.*error|tls.*error"; then
    echo "AUTH_SECURITY_ERROR"
    return
  fi

  echo "GENERAL_ERROR"
}

# Get pattern description
pattern_description() {
  case "$1" in
    SERVICE_START_FAILURE) echo "Service Start/Restart Failure" ;;
    OUT_OF_MEMORY) echo "Out of Memory (OOM)" ;;
    PERMISSION_DENIED) echo "Permission Denied" ;;
    NETWORK_FAILURE) echo "Network/Connection Failure" ;;
    SEGFAULT) echo "Segmentation Fault" ;;
    CONTAINER_ERROR) echo "Container/Podman Error" ;;
    DISK_ERROR) echo "Disk/Filesystem Error" ;;
    AUTH_SECURITY_ERROR) echo "Authentication/Security Error" ;;
    GENERAL_ERROR) echo "General Error" ;;
    *) echo "Unknown Pattern" ;;
  esac
}

# Extract service name from journal line
extract_service() {
  echo "$1" | awk '{print $3}' | sed 's/\[.*\]//' | sed 's/:$//'
}

# Detect container-specific error patterns
detect_container_error() {
  local line="$1"
  local line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')

  for pattern in "${CONTAINER_ERROR_PATTERNS[@]}"; do
    if echo "$line" | grep -Eq "$pattern"; then
      return 0
    fi
  done
  return 1
}

# Convert time window to podman --since format
convert_time_window_to_since() {
  local time_window="$1"

  # Parse time window like "10 minutes ago", "1 hour ago", etc.
  if [[ "$time_window" =~ ([0-9]+)[[:space:]]*(minute|hour|day|week) ]]; then
    local number="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"

    case "$unit" in
      minute*) echo "${number}m" ;;
      hour*) echo "${number}h" ;;
      day*) echo "${number}d" ;;
      week*) echo "$((number * 7))d" ;;
      *) echo "10m" ;;
    esac
  else
    # Default to 10 minutes
    echo "10m"
  fi
}

# Classify container log severity
classify_container_log_severity() {
  local line="$1"
  local line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')

  # CRITICAL: Fatal errors, crashes, exits
  if echo "$line_lower" | grep -Eq "fatal|panic|segfault|core dumped|exit code [1-9]|exited with error"; then
    echo "CRITICAL"
    return
  fi

  # HIGH: Errors, exceptions, connection failures
  if echo "$line_lower" | grep -Eq "error:|exception|econnrefused|etimedout|database.*connection.*failed|status code [45][0-9]{2}|nullpointerexception|runtimeexception|sqlexception"; then
    echo "HIGH"
    return
  fi

  # MEDIUM: Warnings, timeouts
  if echo "$line_lower" | grep -Eq "warn|warning|timeout|retry|deprecated"; then
    echo "MEDIUM"
    return
  fi

  # LOW: Info that looks problematic
  echo "LOW"
}

#==============================================================================
# MAIN LOGIC
#==============================================================================

echo -e "${BOLD}${BLUE}=== System Error Analysis ===${NC}"
echo -e "${CYAN}Time window: ${TIME_WINDOW}${NC}"

# Determine priority levels to check
if [ "$INCLUDE_WARNINGS" = true ]; then
  PRIORITY_LEVELS="warning"
  echo -e "${CYAN}Priority levels: error, warning${NC}"
else
  PRIORITY_LEVELS="err"
  echo -e "${CYAN}Priority levels: error only${NC}"
fi

# Build journalctl command
JOURNAL_CMD="journalctl --since \"${TIME_WINDOW}\" -p ${PRIORITY_LEVELS} --no-pager -o short-iso"
if [ -n "$SERVICE" ]; then
    JOURNAL_CMD="$JOURNAL_CMD -u ${SERVICE}"
    echo -e "${CYAN}Service filter: ${SERVICE}${NC}"
fi

# Show filter status
if [ "$SHOW_ALL" = true ]; then
    echo -e "${YELLOW}Exclusion filters: DISABLED (--show-all)${NC}"
else
    echo -e "${CYAN}Exclusion filters: ${#EXCLUDE_SERVICES[@]} services, ${#EXCLUDE_PATTERNS[@]} patterns${NC}"
    echo -e "${DIM}(Critical errors are never filtered)${NC}"
fi

# Show active analysis features
ACTIVE_FEATURES=()
[ "$SHOW_SEVERITY" = true ] && ACTIVE_FEATURES+=("severity")
[ "$SHOW_PATTERNS" = true ] && ACTIVE_FEATURES+=("patterns")
[ "$SHOW_CONTEXT" = true ] && ACTIVE_FEATURES+=("context")
[ "$SHOW_TRENDS" = true ] && ACTIVE_FEATURES+=("trends")
[ "$SHOW_HEALTH" = true ] && ACTIVE_FEATURES+=("health")
[ "$SHOW_CONTAINERS" = true ] && ACTIVE_FEATURES+=("containers")

if [ ${#ACTIVE_FEATURES[@]} -gt 0 ]; then
  echo -e "${CYAN}Active features: ${ACTIVE_FEATURES[*]}${NC}"
fi

echo ""

# Get raw errors
RAW_ERRORS=$(eval "$JOURNAL_CMD" 2>/dev/null || echo "")

# Apply exclusion filters (unless --show-all is specified)
# BUT preserve critical errors even if they match exclusion patterns
if [ "$SHOW_ALL" = false ] && [ -n "$RAW_ERRORS" ]; then
  FILTERED_ERRORS=""
  CRITICAL_ERRORS=""

  while IFS= read -r line; do
    if is_critical "$line"; then
      # Preserve critical errors
      CRITICAL_ERRORS="${CRITICAL_ERRORS}${line}"$'\n'
    else
      # Apply normal filtering
      SHOULD_EXCLUDE=false

      # Check service exclusions
      for service in "${EXCLUDE_SERVICES[@]}"; do
        if echo "$line" | grep -q "$service"; then
          SHOULD_EXCLUDE=true
          break
        fi
      done

      # Check pattern exclusions
      if [ "$SHOULD_EXCLUDE" = false ]; then
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
          if echo "$line" | grep -q "$pattern"; then
            SHOULD_EXCLUDE=true
            break
          fi
        done
      fi

      if [ "$SHOULD_EXCLUDE" = false ]; then
        FILTERED_ERRORS="${FILTERED_ERRORS}${line}"$'\n'
      fi
    fi
  done <<< "$RAW_ERRORS"

  # Combine critical errors (unfiltered) with filtered errors
  RAW_ERRORS="${CRITICAL_ERRORS}${FILTERED_ERRORS}"
  RAW_ERRORS=$(echo "$RAW_ERRORS" | sed '/^$/d') # Remove empty lines
fi

if [ -z "$RAW_ERRORS" ]; then
    echo -e "${GREEN}✓ No journal errors found!${NC}"

    # Still run container analysis if requested
    if [ "$SHOW_CONTAINERS" = false ]; then
        exit 0
    else
        # Skip to container analysis
        echo ""
    fi
else
    # Count total errors
    TOTAL_ERRORS=$(echo "$RAW_ERRORS" | wc -l)
    echo -e "${YELLOW}Total entries: ${TOTAL_ERRORS}${NC}"
    echo ""
fi

#==============================================================================
# SEVERITY CLASSIFICATION
#==============================================================================

if [ "$SHOW_SEVERITY" = true ] && [ -n "$RAW_ERRORS" ]; then
  echo -e "${BOLD}${BLUE}=== Severity Classification ===${NC}"

  declare -A SEVERITY_COUNTS
  SEVERITY_COUNTS[CRITICAL]=0
  SEVERITY_COUNTS[HIGH]=0
  SEVERITY_COUNTS[MEDIUM]=0
  SEVERITY_COUNTS[LOW]=0

  while IFS= read -r line; do
    severity=$(classify_severity "$line")
    SEVERITY_COUNTS[$severity]=$((SEVERITY_COUNTS[$severity] + 1))
  done <<< "$RAW_ERRORS"

  [ ${SEVERITY_COUNTS[CRITICAL]} -gt 0 ] && echo -e "${RED}${BOLD}CRITICAL:${NC} ${SEVERITY_COUNTS[CRITICAL]}"
  [ ${SEVERITY_COUNTS[HIGH]} -gt 0 ] && echo -e "${RED}HIGH:${NC}     ${SEVERITY_COUNTS[HIGH]}"
  [ ${SEVERITY_COUNTS[MEDIUM]} -gt 0 ] && echo -e "${YELLOW}MEDIUM:${NC}   ${SEVERITY_COUNTS[MEDIUM]}"
  [ ${SEVERITY_COUNTS[LOW]} -gt 0 ] && echo -e "${CYAN}LOW:${NC}      ${SEVERITY_COUNTS[LOW]}"

  echo ""
fi

#==============================================================================
# PATTERN DETECTION
#==============================================================================

if [ "$SHOW_PATTERNS" = true ] && [ -n "$RAW_ERRORS" ]; then
  echo -e "${BOLD}${BLUE}=== Detected Error Patterns ===${NC}"

  declare -A PATTERN_COUNTS

  while IFS= read -r line; do
    pattern=$(detect_pattern "$line")
    PATTERN_COUNTS[$pattern]=$((${PATTERN_COUNTS[$pattern]:-0} + 1))
  done <<< "$RAW_ERRORS"

  # Sort patterns by count (descending)
  for pattern in "${!PATTERN_COUNTS[@]}"; do
    echo "${PATTERN_COUNTS[$pattern]} $pattern"
  done | sort -rn | while read -r count pattern; do
    desc=$(pattern_description "$pattern")

    # Color-code by pattern type
    case "$pattern" in
      OUT_OF_MEMORY|SEGFAULT)
        echo -e "${RED}${BOLD}[$count]${NC} ${desc}"
        ;;
      SERVICE_START_FAILURE|DISK_ERROR|AUTH_SECURITY_ERROR)
        echo -e "${RED}[$count]${NC} ${desc}"
        ;;
      PERMISSION_DENIED|NETWORK_FAILURE|CONTAINER_ERROR)
        echo -e "${YELLOW}[$count]${NC} ${desc}"
        ;;
      *)
        echo -e "${CYAN}[$count]${NC} ${desc}"
        ;;
    esac
  done

  echo ""
fi

#==============================================================================
# SERVICE HEALTH CORRELATION
#==============================================================================

if [ "$SHOW_HEALTH" = true ] && [ -n "$RAW_ERRORS" ]; then
  echo -e "${BOLD}${BLUE}=== Service Health Correlation ===${NC}"

  declare -A SERVICE_ERROR_COUNTS
  declare -A SERVICE_PATTERN_COUNTS

  while IFS= read -r line; do
    service=$(extract_service "$line")
    pattern=$(detect_pattern "$line")

    # Count errors per service
    SERVICE_ERROR_COUNTS[$service]=$((${SERVICE_ERROR_COUNTS[$service]:-0} + 1))

    # Track unique patterns per service
    key="${service}:${pattern}"
    SERVICE_PATTERN_COUNTS[$key]=1
  done <<< "$RAW_ERRORS"

  # Calculate pattern diversity per service
  declare -A SERVICE_PATTERN_DIVERSITY
  for key in "${!SERVICE_PATTERN_COUNTS[@]}"; do
    service="${key%%:*}"
    SERVICE_PATTERN_DIVERSITY[$service]=$((${SERVICE_PATTERN_DIVERSITY[$service]:-0} + 1))
  done

  # Sort services by error count
  for service in "${!SERVICE_ERROR_COUNTS[@]}"; do
    echo "${SERVICE_ERROR_COUNTS[$service]} ${SERVICE_PATTERN_DIVERSITY[$service]:-0} $service"
  done | sort -rn | head -10 | while read -r count diversity service; do
    if [ "$count" -gt 10 ] || [ "$diversity" -gt 3 ]; then
      echo -e "${RED}${BOLD}$service:${NC} $count errors, $diversity pattern types ${RED}[UNHEALTHY]${NC}"
    elif [ "$count" -gt 5 ] || [ "$diversity" -gt 2 ]; then
      echo -e "${YELLOW}$service:${NC} $count errors, $diversity pattern types ${YELLOW}[WARNING]${NC}"
    else
      echo -e "${CYAN}$service:${NC} $count errors, $diversity pattern types"
    fi
  done

  echo ""
fi

#==============================================================================
# TIME-BASED TRENDS
#==============================================================================

if [ "$SHOW_TRENDS" = true ] && [ -n "$RAW_ERRORS" ]; then
  echo -e "${BOLD}${BLUE}=== Error Trends ===${NC}"

  # Split time window into 4 quarters and count errors in each
  # This requires calculating the time range

  # Get current timestamp
  NOW=$(date +%s)

  # Parse time window to get seconds ago
  SECONDS_AGO=0
  if [[ "$TIME_WINDOW" =~ ([0-9]+)[[:space:]]*(minute|hour|day|week) ]]; then
    NUMBER="${BASH_REMATCH[1]}"
    UNIT="${BASH_REMATCH[2]}"

    case "$UNIT" in
      minute*) SECONDS_AGO=$((NUMBER * 60)) ;;
      hour*) SECONDS_AGO=$((NUMBER * 3600)) ;;
      day*) SECONDS_AGO=$((NUMBER * 86400)) ;;
      week*) SECONDS_AGO=$((NUMBER * 604800)) ;;
    esac
  else
    # Default to 10 minutes if we can't parse
    SECONDS_AGO=600
  fi

  START_TIME=$((NOW - SECONDS_AGO))
  QUARTER_DURATION=$((SECONDS_AGO / 4))

  declare -A QUARTER_COUNTS
  QUARTER_COUNTS[1]=0
  QUARTER_COUNTS[2]=0
  QUARTER_COUNTS[3]=0
  QUARTER_COUNTS[4]=0

  while IFS= read -r line; do
    # Extract ISO timestamp from journalctl output
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
      timestamp="${BASH_REMATCH[1]}"
      # Convert to epoch (works on most systems)
      epoch=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$timestamp" +%s 2>/dev/null || echo "$NOW")

      # Determine which quarter this falls into
      elapsed=$((epoch - START_TIME))
      if [ "$elapsed" -lt "$QUARTER_DURATION" ]; then
        QUARTER_COUNTS[1]=$((QUARTER_COUNTS[1] + 1))
      elif [ "$elapsed" -lt $((QUARTER_DURATION * 2)) ]; then
        QUARTER_COUNTS[2]=$((QUARTER_COUNTS[2] + 1))
      elif [ "$elapsed" -lt $((QUARTER_DURATION * 3)) ]; then
        QUARTER_COUNTS[3]=$((QUARTER_COUNTS[3] + 1))
      else
        QUARTER_COUNTS[4]=$((QUARTER_COUNTS[4] + 1))
      fi
    fi
  done <<< "$RAW_ERRORS"

  # Display trend
  echo -e "${DIM}Time periods (oldest to newest):${NC}"

  # Calculate max for scaling
  MAX_COUNT=0
  for i in 1 2 3 4; do
    [ ${QUARTER_COUNTS[$i]} -gt $MAX_COUNT ] && MAX_COUNT=${QUARTER_COUNTS[$i]}
  done

  for i in 1 2 3 4; do
    count=${QUARTER_COUNTS[$i]}

    # Create simple bar chart
    if [ $MAX_COUNT -gt 0 ]; then
      bar_length=$((count * 40 / MAX_COUNT))
    else
      bar_length=0
    fi
    bar=$(printf '█%.0s' $(seq 1 $bar_length))

    # Color based on quarter (newer = more important)
    if [ $i -eq 4 ]; then
      echo -e "${BOLD}Q$i:${NC} ${RED}$bar${NC} ($count)"
    elif [ $i -eq 3 ]; then
      echo -e "${BOLD}Q$i:${NC} ${YELLOW}$bar${NC} ($count)"
    else
      echo -e "${BOLD}Q$i:${NC} ${CYAN}$bar${NC} ($count)"
    fi
  done

  # Trend analysis
  if [ ${QUARTER_COUNTS[4]} -gt ${QUARTER_COUNTS[1]} ]; then
    echo -e "${RED}${BOLD}⚠ Errors are INCREASING${NC}"
  elif [ ${QUARTER_COUNTS[4]} -lt ${QUARTER_COUNTS[1]} ]; then
    echo -e "${GREEN}✓ Errors are decreasing${NC}"
  else
    echo -e "${CYAN}Errors are stable${NC}"
  fi

  echo ""
fi

#==============================================================================
# CRITICAL ERROR CONTEXT
#==============================================================================

if [ "$SHOW_CONTEXT" = true ] && [ -n "$RAW_ERRORS" ]; then
  # Find critical errors and show context
  CRITICAL_LINES=$(echo "$RAW_ERRORS" | grep -n "" | while IFS=: read -r linenum line; do
    if is_critical "$line"; then
      echo "$linenum"
    fi
  done)

  if [ -n "$CRITICAL_LINES" ]; then
    echo -e "${BOLD}${RED}=== Critical Error Context ===${NC}"

    while read -r linenum; do
      # Show 2 lines before and 2 lines after
      start=$((linenum - 2))
      [ $start -lt 1 ] && start=1
      end=$((linenum + 2))

      echo -e "${RED}${BOLD}Critical error at line $linenum:${NC}"
      echo "$RAW_ERRORS" | sed -n "${start},${end}p" | while IFS= read -r context_line; do
        if is_critical "$context_line"; then
          echo -e "${RED}${BOLD}► $context_line${NC}"
        else
          echo -e "${DIM}  $context_line${NC}"
        fi
      done
      echo ""
    done <<< "$CRITICAL_LINES"
  fi
fi

#==============================================================================
# DEDUPLICATION SUMMARY
#==============================================================================

if [ -n "$RAW_ERRORS" ]; then
  echo -e "${BOLD}${BLUE}=== Error Summary (deduplicated) ===${NC}"

  # Enhanced deduplication with severity marking
  echo "$RAW_ERRORS" | \
      # Remove timestamps and hostnames for grouping
      sed -E 's/^[^ ]+ [^ ]+ //' | \
      # Group and count duplicates
      sort | uniq -c | sort -rn | \
      # Format output with colors and severity
      while read -r count message; do
          severity=$(classify_severity "$message")

          # Determine color based on count and severity
          if [ "$severity" = "CRITICAL" ] || [ "$count" -gt 10 ]; then
              echo -e "${RED}${BOLD}[${count}x]${NC} ${RED}$message${NC}"
          elif [ "$severity" = "HIGH" ] || [ "$count" -gt 5 ]; then
              echo -e "${YELLOW}[${count}x]${NC} ${message}"
          elif [ "$severity" = "MEDIUM" ]; then
              echo -e "${CYAN}[${count}x]${NC} ${DIM}$message${NC}"
          else
              echo -e "${CYAN}[${count}x]${NC} $message"
          fi
      done

  #==============================================================================
  # RECENT ERRORS
  #==============================================================================

  echo ""
  echo -e "${BOLD}${BLUE}=== Top 5 Most Recent Errors ===${NC}"
  echo "$RAW_ERRORS" | tail -5 | while IFS= read -r line; do
    if is_critical "$line"; then
      echo -e "${RED}${BOLD}$line${NC}"
    else
      echo "$line"
    fi
  done
fi

#==============================================================================
# CONTAINER LOG ANALYSIS
#==============================================================================

if [ "$SHOW_CONTAINERS" = true ]; then
  echo ""
  echo -e "${BOLD}${BLUE}=== Container Log Analysis ===${NC}"

  if [ "$PODMAN_AVAILABLE" = false ]; then
    echo -e "${YELLOW}⚠ Podman not available, skipping container analysis${NC}"
  else
    # Convert time window to podman format
    PODMAN_SINCE=$(convert_time_window_to_since "$TIME_WINDOW")
    echo -e "${CYAN}Analyzing container logs (last ${PODMAN_SINCE})${NC}"
    echo ""

    # Get list of all containers (running and stopped)
    CONTAINERS_JSON=$(podman ps -a --format json 2>/dev/null || echo "[]")

    if [ "$CONTAINERS_JSON" = "[]" ] || [ -z "$CONTAINERS_JSON" ]; then
      echo -e "${GREEN}✓ No containers found${NC}"
    else
      # Count containers
      CONTAINER_COUNT=$(echo "$CONTAINERS_JSON" | jq 'length')
      echo -e "${CYAN}Found ${CONTAINER_COUNT} container(s)${NC}"
      echo ""

      # Analyze each container
      CONTAINERS_WITH_ERRORS=0
      TOTAL_CONTAINER_ERRORS=0

      echo "$CONTAINERS_JSON" | jq -c '.[]' | while IFS= read -r container; do
        CONTAINER_NAME=$(echo "$container" | jq -r '.Names[0]')
        CONTAINER_ID=$(echo "$container" | jq -r '.Id' | cut -c1-12)
        CONTAINER_STATUS=$(echo "$container" | jq -r '.State')
        CONTAINER_IMAGE=$(echo "$container" | jq -r '.Image')

        # Get container logs
        CONTAINER_LOGS=$(podman logs --since "$PODMAN_SINCE" --tail 1000 "$CONTAINER_ID" 2>&1 || echo "")

        # Skip if no logs
        if [ -z "$CONTAINER_LOGS" ]; then
          continue
        fi

        # Filter logs for errors
        CONTAINER_ERRORS=$(echo "$CONTAINER_LOGS" | while IFS= read -r line; do
          if detect_container_error "$line"; then
            echo "$line"
          fi
        done)

        # Skip if no errors
        if [ -z "$CONTAINER_ERRORS" ]; then
          continue
        fi

        # Count errors
        ERROR_COUNT=$(echo "$CONTAINER_ERRORS" | wc -l)
        CONTAINERS_WITH_ERRORS=$((CONTAINERS_WITH_ERRORS + 1))
        TOTAL_CONTAINER_ERRORS=$((TOTAL_CONTAINER_ERRORS + ERROR_COUNT))

        # Determine container health color
        STATUS_COLOR="$GREEN"
        if [ "$CONTAINER_STATUS" != "running" ]; then
          STATUS_COLOR="$RED"
        elif [ "$ERROR_COUNT" -gt 10 ]; then
          STATUS_COLOR="$RED"
        elif [ "$ERROR_COUNT" -gt 5 ]; then
          STATUS_COLOR="$YELLOW"
        fi

        # Print container header
        echo -e "${BOLD}${BLUE}Container: ${CONTAINER_NAME}${NC}"
        echo -e "${DIM}  ID:     ${CONTAINER_ID}${NC}"
        echo -e "${DIM}  Image:  ${CONTAINER_IMAGE}${NC}"
        echo -e "${DIM}  Status: ${STATUS_COLOR}${CONTAINER_STATUS}${NC}"
        echo -e "${YELLOW}  Errors: ${ERROR_COUNT}${NC}"

        # Analyze error patterns
        declare -A CONTAINER_PATTERN_COUNTS

        while IFS= read -r error_line; do
          # Classify severity
          severity=$(classify_container_log_severity "$error_line")

          # Detect general pattern (reuse existing function)
          pattern=$(detect_pattern "$error_line")
          CONTAINER_PATTERN_COUNTS[$pattern]=$((${CONTAINER_PATTERN_COUNTS[$pattern]:-0} + 1))
        done <<< "$CONTAINER_ERRORS"

        # Show pattern summary
        if [ ${#CONTAINER_PATTERN_COUNTS[@]} -gt 0 ]; then
          echo -e "${DIM}  Patterns:${NC}"
          for pattern in "${!CONTAINER_PATTERN_COUNTS[@]}"; do
            count=${CONTAINER_PATTERN_COUNTS[$pattern]}
            desc=$(pattern_description "$pattern")
            echo -e "${DIM}    - ${desc}: ${count}${NC}"
          done
        fi

        # Show recent critical errors (max 3)
        CRITICAL_CONTAINER_ERRORS=$(echo "$CONTAINER_ERRORS" | while IFS= read -r line; do
          severity=$(classify_container_log_severity "$line")
          if [ "$severity" = "CRITICAL" ] || [ "$severity" = "HIGH" ]; then
            echo "$line"
          fi
        done)

        if [ -n "$CRITICAL_CONTAINER_ERRORS" ]; then
          echo -e "${RED}  Recent Critical Errors:${NC}"
          echo "$CRITICAL_CONTAINER_ERRORS" | head -3 | while IFS= read -r line; do
            # Truncate long lines
            if [ ${#line} -gt 120 ]; then
              line="${line:0:117}..."
            fi
            echo -e "${RED}    $line${NC}"
          done
        fi

        echo ""
      done

      # Summary
      echo -e "${BOLD}${BLUE}=== Container Analysis Summary ===${NC}"
      echo -e "${CYAN}Containers analyzed: ${CONTAINER_COUNT}${NC}"

      # Note: Due to subshell limitations, we can't get the exact count here
      # The analysis is still shown above, but summary counts would need refactoring
      echo -e "${DIM}(See individual container details above)${NC}"
      echo ""
    fi
  fi
fi

#==============================================================================
# USAGE TIPS
#==============================================================================

echo ""
echo -e "${BOLD}${BLUE}=== Tips ===${NC}"
echo -e "${CYAN}Full journal: journalctl --since \"${TIME_WINDOW}\" -p ${PRIORITY_LEVELS}${NC}"

if [ -z "$SERVICE" ]; then
    echo -e "${CYAN}Filter service: journal-errors \"${TIME_WINDOW}\" SERVICE_NAME${NC}"
fi

if [ "$SHOW_ALL" = false ]; then
    echo -e "${CYAN}Show all: journal-errors --show-all \"${TIME_WINDOW}\"${NC}"
fi

if [ "$INCLUDE_WARNINGS" = false ]; then
    echo -e "${CYAN}Include warnings: journal-errors --warnings \"${TIME_WINDOW}\"${NC}"
fi

if [ "$SHOW_SEVERITY" = false ] || [ "$SHOW_PATTERNS" = false ] || [ "$SHOW_CONTEXT" = false ]; then
    echo -e "${CYAN}Full analysis: journal-errors --verbose \"${TIME_WINDOW}\"${NC}"
fi

if [ "$SHOW_CONTAINERS" = false ] && [ "$PODMAN_AVAILABLE" = true ]; then
    echo -e "${CYAN}Analyze containers: journal-errors --containers \"${TIME_WINDOW}\"${NC}"
fi

echo -e "${DIM}Available options: --warnings --severity --patterns --context --trends --health --containers --verbose${NC}"
