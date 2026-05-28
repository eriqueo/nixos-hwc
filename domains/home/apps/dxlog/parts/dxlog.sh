#!/usr/bin/env bash
# =============================================================================
# dxlog — DataX OpenSearch Log Diagnostic Tool  v0.2.0
#
# Query chat-req-trace logs and general platform logs from OpenSearch.
# Outputs structured markdown or raw JSON.
#
# Usage:
#   dxlog trace --agent <id> [--from <date>] [--to <date>] [--limit <n>]
#   dxlog trace --user <id>  [--from <date>] [--to <date>] [--limit <n>]
#   dxlog trace --chat <id>  [--from <date>] [--to <date>] [--limit <n>]
#   dxlog search <term>      [--from <date>] [--to <date>] [--limit <n>]
#   dxlog errors             [--from <date>] [--to <date>] [--limit <n>]
#   dxlog loops              [--from <date>] [--to <date>] [--limit <n>]
#   dxlog tail [minutes]     Last N minutes of traces (default: 30)
#   dxlog live               [--user <id>] [--agent <id>]
#   dxlog indices
#
# Environment (set in ~/.config/dxlog/env or export directly):
#   DXLOG_OPENSEARCH_HOST     OpenSearch hostname (no protocol)
#   DXLOG_OPENSEARCH_PORT     OpenSearch port (default: 25060)
#   DXLOG_OPENSEARCH_USER     OpenSearch username
#   DXLOG_OPENSEARCH_PASS     OpenSearch password
#   DXLOG_DO_APP_ID           DigitalOcean app ID for live tailing
#
# =============================================================================

set -euo pipefail

VERSION="0.2.0"
CONFIG_DIR="${HOME}/.config/dxlog"
CONFIG_FILE="${CONFIG_DIR}/env"

# -----------------------------------------------------------------------------
# Colors & formatting
# -----------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
DIM='\033[2m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
err()  { echo -e "${RED}error:${NC} $*" >&2; }
warn() { echo -e "${YELLOW}warn:${NC} $*" >&2; }
info() { echo -e "${DIM}$*${NC}" >&2; }
ok()   { echo -e "${GREEN}✓${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# Load config — split into OS vs doctl to avoid false dependency
# -----------------------------------------------------------------------------
load_env_file() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
}

load_os_config() {
  load_env_file
  local missing=()
  [[ -z "${DXLOG_OPENSEARCH_HOST:-}" ]] && missing+=("DXLOG_OPENSEARCH_HOST")
  [[ -z "${DXLOG_OPENSEARCH_USER:-}" ]] && missing+=("DXLOG_OPENSEARCH_USER")
  [[ -z "${DXLOG_OPENSEARCH_PASS:-}" ]] && missing+=("DXLOG_OPENSEARCH_PASS")

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required environment variables: ${missing[*]}"
    echo "" >&2
    echo "Set them in ${CONFIG_FILE} or export them directly." >&2
    echo "Run 'dxlog init' to create a config template." >&2
    exit 1
  fi

  DXLOG_OPENSEARCH_PORT="${DXLOG_OPENSEARCH_PORT:-25060}"
  OS_BASE="https://${DXLOG_OPENSEARCH_HOST}:${DXLOG_OPENSEARCH_PORT}"
}

load_doctl_config() {
  load_env_file
  DXLOG_DO_APP_ID="${DXLOG_DO_APP_ID:-3a369b9a-4352-41f2-b85a-9f79f8cf2ae2}"
}

# -----------------------------------------------------------------------------
# Init config — idempotent against an existing file AND populated env vars
# (so the Nix wrapper's exports don't get clobbered by a stub config)
# -----------------------------------------------------------------------------
cmd_init() {
  if [[ -n "${DXLOG_OPENSEARCH_HOST:-}" \
     && -n "${DXLOG_OPENSEARCH_USER:-}" \
     && -n "${DXLOG_OPENSEARCH_PASS:-}" ]]; then
    ok "dxlog is already configured via environment variables. Nothing to do."
    info "  HOST/USER/PASS are present in the environment (likely from a Nix wrapper"
    info "  or shell rc). A stub config file would only get in the way."
    return
  fi

  mkdir -p "$CONFIG_DIR"
  if [[ -f "$CONFIG_FILE" ]]; then
    warn "Config already exists at ${CONFIG_FILE}"
    echo "  Edit it directly or delete and re-run init." >&2
    return
  fi
  cat > "$CONFIG_FILE" <<'ENVEOF'
# dxlog configuration
# Fill in your OpenSearch credentials from the DataX .env

DXLOG_OPENSEARCH_HOST=""
DXLOG_OPENSEARCH_PORT="25060"
DXLOG_OPENSEARCH_USER=""
DXLOG_OPENSEARCH_PASS=""

# DigitalOcean app ID for 'dxlog live'
DXLOG_DO_APP_ID="3a369b9a-4352-41f2-b85a-9f79f8cf2ae2"
ENVEOF

  chmod 600 "$CONFIG_FILE"
  ok "Created config at ${CONFIG_FILE}"
  echo "  Edit it and fill in your credentials." >&2
}

# -----------------------------------------------------------------------------
# OpenSearch query runner — with timeouts (#4)
# -----------------------------------------------------------------------------
os_query() {
  local index_pattern="$1"
  local query_body="$2"

  if [[ "${VERBOSE:-0}" == "1" ]]; then
    info "Query: GET ${index_pattern}/_search"
    echo "$query_body" | jq '.' >&2 2>/dev/null || echo "$query_body" >&2
    info "---"
  fi

  local response http_code
  response=$(mktemp)
  http_code=$(curl -s -w "%{http_code}" -o "$response" \
    --connect-timeout 10 --max-time 30 \
    -u "${DXLOG_OPENSEARCH_USER}:${DXLOG_OPENSEARCH_PASS}" \
    -H "Content-Type: application/json" \
    -X POST "${OS_BASE}/${index_pattern}/_search" \
    -d "$query_body" 2>/dev/null) || {
      err "curl failed. Check your network and OpenSearch credentials."
      err "Host: ${OS_BASE}"
      rm -f "$response"
      exit 1
    }

  if [[ "$http_code" -ge 400 ]]; then
    err "OpenSearch returned HTTP ${http_code}"
    local error_reason
    error_reason=$(jq -r '.error.reason // .error.root_cause[0].reason // "unknown"' "$response" 2>/dev/null)
    if [[ "$error_reason" != "null" && "$error_reason" != "unknown" ]]; then
      err "Reason: ${error_reason}"
    fi
    if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
      err "Authentication failed. Check DXLOG_OPENSEARCH_USER and DXLOG_OPENSEARCH_PASS."
    elif [[ "$http_code" == "404" ]]; then
      err "Index pattern '${index_pattern}' not found. Run 'dxlog indices' to see available indices."
    fi
    cat "$response" >&2
    rm -f "$response"
    exit 1
  fi

  cat "$response"
  rm -f "$response"
}

# -----------------------------------------------------------------------------
# Date helpers — GNU coreutils only (#9: drop dead BSD branch)
# -----------------------------------------------------------------------------
default_from() {
  date -u -d "24 hours ago" "+%Y-%m-%dT%H:%M:%SZ"
}

default_to() {
  date -u "+%Y-%m-%dT%H:%M:%SZ"
}

minutes_ago() {
  local mins="$1"
  date -u -d "${mins} minutes ago" "+%Y-%m-%dT%H:%M:%SZ"
}

normalize_date() {
  local d="$1"
  if [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "${d}T00:00:00Z"
  else
    echo "$d"
  fi
}

# Detect if from/to span multiple days (#14)
spans_multiple_days() {
  local from_date to_date
  from_date="${1:0:10}"  # YYYY-MM-DD
  to_date="${2:0:10}"
  [[ "$from_date" != "$to_date" ]]
}

# -----------------------------------------------------------------------------
# Build query JSON — using jq for safe escaping (#6)
# -----------------------------------------------------------------------------
build_trace_query() {
  local filter_field="$1"
  local filter_value="$2"
  local date_from="$3"
  local date_to="$4"
  local limit="$5"

  jq -nc \
    --arg phrase1 "chat-req-trace" \
    --arg phrase2 "${filter_field}=${filter_value}" \
    --arg gte "$date_from" \
    --arg lte "$date_to" \
    --argjson size "$limit" \
    '{
      query: {
        bool: {
          must: [
            { match_phrase: { log: $phrase1 } },
            { match_phrase: { log: $phrase2 } }
          ],
          filter: {
            range: { "@timestamp": { gte: $gte, lte: $lte } }
          }
        }
      },
      size: $size,
      sort: [{ "@timestamp": "asc" }]
    }'
}

build_search_query() {
  local term="$1"
  local date_from="$2"
  local date_to="$3"
  local limit="$4"

  jq -nc \
    --arg phrase "$term" \
    --arg gte "$date_from" \
    --arg lte "$date_to" \
    --argjson size "$limit" \
    '{
      query: {
        bool: {
          must: [ { match_phrase: { log: $phrase } } ],
          filter: {
            range: { "@timestamp": { gte: $gte, lte: $lte } }
          }
        }
      },
      size: $size,
      sort: [{ "@timestamp": "asc" }]
    }'
}

build_errors_query() {
  local date_from="$1"
  local date_to="$2"
  local limit="$3"

  jq -nc \
    --arg gte "$date_from" \
    --arg lte "$date_to" \
    --argjson size "$limit" \
    '{
      query: {
        bool: {
          must: [ { match_phrase: { log: "chat-req-trace" } } ],
          should: [
            { match_phrase: { log: "Error in" } },
            { match_phrase: { log: "LOOP WARNING" } },
            { match_phrase: { log: "ERROR LOOP WARNING" } },
            { match_phrase: { log: "isError" } }
          ],
          minimum_should_match: 1,
          filter: {
            range: { "@timestamp": { gte: $gte, lte: $lte } }
          }
        }
      },
      size: $size,
      sort: [{ "@timestamp": "asc" }]
    }'
}

build_loops_query() {
  local date_from="$1"
  local date_to="$2"
  local limit="$3"

  jq -nc \
    --arg gte "$date_from" \
    --arg lte "$date_to" \
    --argjson size "$limit" \
    '{
      query: {
        bool: {
          must: [
            { match_phrase: { log: "chat-req-trace" } },
            { match_phrase: { log: "LOOP WARNING" } }
          ],
          filter: {
            range: { "@timestamp": { gte: $gte, lte: $lte } }
          }
        }
      },
      size: $size,
      sort: [{ "@timestamp": "asc" }]
    }'
}

# -----------------------------------------------------------------------------
# Parse trace log entry — extract via jq, not greedy regex (#7)
# Drops dead has_tool_calls field (#5)
# Fixes error/loop counting (#2)
# -----------------------------------------------------------------------------
parse_trace_entry() {
  local log_str="$1"
  local timestamp="$2"

  # Extract header IDs
  local user_id chat_id agent_id
  user_id=$(echo "$log_str" | grep -oP 'userId=\K[^ \]]+' || echo "?")
  chat_id=$(echo "$log_str" | grep -oP 'chatId=\K[^ \]]+' || echo "?")
  agent_id=$(echo "$log_str" | grep -oP 'agentId=\K[^ \]]+' || echo "?")

  # Extract the JSON payload — the message field contains [chat-req-trace ...] {json}
  # Parse by finding the first { that starts "iteration"
  local json_payload
  json_payload=$(echo "$log_str" | sed 's/.*\({"iteration\)/\1/' 2>/dev/null || echo "{}")

  # `head -n1` guards against jq returning multiple values (e.g. when .iteration
  # also appears inside nested messages[]); without it the entry becomes
  # multi-line and breaks downstream arithmetic.
  local iteration msg_count tool_count total_chars
  iteration=$(echo  "$json_payload" | jq -r '.iteration // "?"'    2>/dev/null | head -n1 || echo "?")
  msg_count=$(echo  "$json_payload" | jq -r '.messageCount // "?"' 2>/dev/null | head -n1 || echo "?")
  tool_count=$(echo "$json_payload" | jq -r '.toolCount // "?"'    2>/dev/null | head -n1 || echo "?")
  total_chars=$(echo "$json_payload" | jq -r '.totalChars // "?"'  2>/dev/null | head -n1 || echo "?")

  local error_count loop_count
  error_count=$(echo "$json_payload" | grep -oE "Error in|isError"             2>/dev/null | wc -l | tr -d ' \n')
  loop_count=$(echo  "$json_payload" | grep -oE "LOOP WARNING|ERROR LOOP WARNING" 2>/dev/null | wc -l | tr -d ' \n')
  : "${error_count:=0}"
  : "${loop_count:=0}"

  echo "${timestamp}|${user_id}|${chat_id}|${agent_id}|${iteration}|${msg_count}|${tool_count}|${total_chars}|${error_count}|${loop_count}"
}

# -----------------------------------------------------------------------------
# Format output — Markdown
# Uses associative array for dedup (#8)
# Keeps date in timestamp for multi-day queries (#14)
# -----------------------------------------------------------------------------
format_trace_md() {
  local raw_json="$1"
  local title="$2"
  local date_from="${3:-}"
  local date_to="${4:-}"

  local total_hits returned_hits
  total_hits=$(echo "$raw_json" | jq '.hits.total.value')
  returned_hits=$(echo "$raw_json" | jq '.hits.hits | length')

  local multi_day=false
  if [[ -n "$date_from" && -n "$date_to" ]]; then
    spans_multiple_days "$date_from" "$date_to" && multi_day=true
  fi

  {
    echo "# ${title}"
    echo ""
    echo "_Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC') | Hits: ${total_hits} (showing ${returned_hits})_"
    echo ""

    if [[ "$returned_hits" -eq 0 ]]; then
      echo "**No results found.**"
      echo ""
      echo "Possible reasons:"
      echo "- The 'Log per-request shape' checkbox wasn't enabled for this user when the agent ran"
      echo "- The ID doesn't match any agentId/userId/chatId in trace logs"
      echo "- The date range doesn't cover the agent's execution window"
      echo "- Try \`dxlog search <id>\` to search all log types, not just traces"
      return
    fi

    echo "## Summary"
    echo ""

    local entries=()
    local max_iteration=0
    local total_errors=0
    local total_loops=0
    declare -A seen_chats  # (#8: associative array)

    while IFS= read -r hit; do
      local ts msg_field
      ts=$(echo "$hit" | jq -r '._source["@timestamp"]')
      # The log field is a JSON string; extract the message field from it
      msg_field=$(echo "$hit" | jq -r '._source.log' | jq -r '.message // empty' 2>/dev/null)
      if [[ -z "$msg_field" ]]; then
        msg_field=$(echo "$hit" | jq -r '._source.log')
      fi

      local parsed
      parsed=$(parse_trace_entry "$msg_field" "$ts")
      entries+=("$parsed")

      local iter errs loops cid
      iter=$(echo "$parsed" | cut -d'|' -f5)
      errs=$(echo "$parsed" | cut -d'|' -f9)
      loops=$(echo "$parsed" | cut -d'|' -f10)
      cid=$(echo "$parsed" | cut -d'|' -f3)

      [[ "$iter" != "?" && "$iter" -gt "$max_iteration" ]] && max_iteration=$iter
      total_errors=$((total_errors + errs))
      total_loops=$((total_loops + loops))
      [[ -n "$cid" && "$cid" != "?" ]] && seen_chats["$cid"]=1
    done < <(echo "$raw_json" | jq -c '.hits.hits[]')

    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Total trace entries | ${returned_hits} |"
    echo "| Unique chat sessions | ${#seen_chats[@]} |"
    echo "| Max iteration reached | ${max_iteration} |"
    echo "| Entries with errors | ${total_errors} |"
    echo "| Entries with loop warnings | ${total_loops} |"
    echo ""

    if [[ "$max_iteration" -gt 10 ]]; then
      echo "> ⚠️ **High iteration count** (${max_iteration}): Agent made ${max_iteration}+ DX1 calls in a single turn. Likely retry loops or complex multi-step workflow."
      echo ""
    fi
    if [[ "$total_loops" -gt 0 ]]; then
      echo "> 🔴 **Loop warnings detected** (${total_loops}): DX1 called the same tool with identical arguments. Known failure mode."
      echo ""
    fi

    echo "## Timeline"
    echo ""
    echo "| Time (UTC) | Chat | Agent | Iter | Msgs | Chars | Errors | Loops |"
    echo "|------------|------|-------|------|------|-------|--------|-------|"

    for entry in "${entries[@]}"; do
      local ts cid aid iter msgs chars errs loops
      ts=$(echo "$entry" | cut -d'|' -f1)
      cid=$(echo "$entry" | cut -d'|' -f3)
      aid=$(echo "$entry" | cut -d'|' -f4)
      iter=$(echo "$entry" | cut -d'|' -f5)
      msgs=$(echo "$entry" | cut -d'|' -f6)
      chars=$(echo "$entry" | cut -d'|' -f8)
      errs=$(echo "$entry" | cut -d'|' -f9)
      loops=$(echo "$entry" | cut -d'|' -f10)

      # (#14) Keep MM-DD for multi-day, time-only for single day
      local short_ts
      if [[ "$multi_day" == true ]]; then
        short_ts=$(echo "$ts" | sed 's/^[0-9]*-//' | sed 's/\..*//' | sed 's/T/ /')
      else
        short_ts=$(echo "$ts" | sed 's/.*T//' | sed 's/\..*//')
      fi

      local short_cid="${cid:0:8}…"
      local short_aid="${aid:0:8}…"
      local err_flag="" loop_flag=""
      [[ "$errs" -gt 0 ]] && err_flag=" ⚠️"
      [[ "$loops" -gt 0 ]] && loop_flag=" 🔴"

      echo "| ${short_ts} | ${short_cid} | ${short_aid} | ${iter} | ${msgs} | ${chars} | ${errs}${err_flag} | ${loops}${loop_flag} |"
    done

    echo ""
    echo "## Raw IDs"
    echo ""
    echo "For Firestore lookups or deeper investigation:"
    echo ""

    declare -A printed_chats
    for entry in "${entries[@]}"; do
      local uid cid aid
      uid=$(echo "$entry" | cut -d'|' -f2)
      cid=$(echo "$entry" | cut -d'|' -f3)
      aid=$(echo "$entry" | cut -d'|' -f4)

      if [[ -n "$cid" && "$cid" != "?" && -z "${printed_chats[$cid]:-}" ]]; then
        printed_chats["$cid"]=1
        echo "- **chatId**: \`${cid}\` → userId: \`${uid}\` | agentId: \`${aid}\`"
      fi
    done
  }
}

format_search_md() {
  local raw_json="$1"
  local title="$2"

  local total_hits returned_hits
  total_hits=$(echo "$raw_json" | jq '.hits.total.value')
  returned_hits=$(echo "$raw_json" | jq '.hits.hits | length')

  {
    echo "# ${title}"
    echo ""
    echo "_Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC') | Hits: ${total_hits} (showing ${returned_hits})_"
    echo ""

    if [[ "$returned_hits" -eq 0 ]]; then
      echo "**No results found.**"
      return
    fi

    while IFS= read -r hit; do
      local ts log_raw
      ts=$(echo "$hit" | jq -r '._source["@timestamp"]')
      log_raw=$(echo "$hit" | jq -r '._source.log')

      echo "### ${ts}"
      echo ""
      echo '```json'
      echo "$log_raw" | jq '.' 2>/dev/null || echo "$log_raw"
      echo '```'
      echo ""
    done < <(echo "$raw_json" | jq -c '.hits.hits[]')
  }
}

# -----------------------------------------------------------------------------
# Output helper — shared by all commands
# -----------------------------------------------------------------------------
emit_output() {
  local content="$1"
  local output_file="${2:-}"

  if [[ -n "$output_file" ]]; then
    echo "$content" > "$output_file"
    ok "Written to ${output_file}"
  else
    echo "$content"
  fi
}

# -----------------------------------------------------------------------------
# Common flag parser for OpenSearch commands
# -----------------------------------------------------------------------------
parse_os_flags() {
  # Sets globals: DATE_FROM DATE_TO LIMIT OUTPUT_JSON OUTPUT_FILE VERBOSE
  DATE_FROM="" DATE_TO="" LIMIT=50 OUTPUT_JSON=0 OUTPUT_FILE="" VERBOSE=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from|-f) DATE_FROM="$2"; shift 2 ;;
      --to|-t)   DATE_TO="$2"; shift 2 ;;
      --limit|-n) LIMIT="$2"; shift 2 ;;
      --json)    OUTPUT_JSON=1; shift ;;
      --out|-o)  OUTPUT_FILE="$2"; shift 2 ;;
      --verbose) VERBOSE=1; shift ;;
      --help|-h) return 1 ;;  # signal caller to show help
      *) return 2 ;;  # unknown flag, caller decides
    esac
  done

  DATE_FROM=$(normalize_date "${DATE_FROM:-$(default_from)}")
  DATE_TO=$(normalize_date "${DATE_TO:-$(default_to)}")
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------
cmd_trace() {
  local filter_field="" filter_value=""
  local args=()

  # Pull trace-specific flags first, collect rest for parse_os_flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)  filter_field="agentId"; filter_value="$2"; shift 2 ;;
      --user)   filter_field="userId";  filter_value="$2"; shift 2 ;;
      --chat)   filter_field="chatId";  filter_value="$2"; shift 2 ;;
      --help|-h) show_trace_help; return ;;
      *)        args+=("$1"); shift ;;
    esac
  done

  if [[ -z "$filter_field" || -z "$filter_value" ]]; then
    err "Must specify --agent <id>, --user <id>, or --chat <id>"
    echo "Run 'dxlog trace --help' for usage." >&2
    exit 1
  fi

  parse_os_flags "${args[@]}" || true

  info "Querying traces: ${filter_field}=${filter_value} | ${DATE_FROM} → ${DATE_TO} | limit=${LIMIT}"

  local query result hit_count
  query=$(build_trace_query "$filter_field" "$filter_value" "$DATE_FROM" "$DATE_TO" "$LIMIT")
  result=$(os_query "logs-*" "$query")
  hit_count=$(echo "$result" | jq '.hits.total.value')
  ok "Found ${hit_count} trace entries"

  if [[ "$OUTPUT_JSON" -eq 1 ]]; then
    emit_output "$(echo "$result" | jq '.')" "$OUTPUT_FILE"
  else
    local title="Trace: ${filter_field}=${filter_value} (${DATE_FROM} → ${DATE_TO})"
    emit_output "$(format_trace_md "$result" "$title" "$DATE_FROM" "$DATE_TO")" "$OUTPUT_FILE"
  fi
}

cmd_search() {
  local term="${1:-}"; shift || { err "Must specify a search term"; exit 1; }

  parse_os_flags "$@" || true

  info "Searching: \"${term}\" | ${DATE_FROM} → ${DATE_TO} | limit=${LIMIT}"

  local query result hit_count
  query=$(build_search_query "$term" "$DATE_FROM" "$DATE_TO" "$LIMIT")
  result=$(os_query "logs-*" "$query")
  hit_count=$(echo "$result" | jq '.hits.total.value')
  ok "Found ${hit_count} entries"

  if [[ "$OUTPUT_JSON" -eq 1 ]]; then
    emit_output "$(echo "$result" | jq '.')" "$OUTPUT_FILE"
  else
    local title="Search: \"${term}\" (${DATE_FROM} → ${DATE_TO})"
    emit_output "$(format_search_md "$result" "$title")" "$OUTPUT_FILE"
  fi
}

cmd_errors() {
  parse_os_flags "$@" || true

  info "Finding trace errors: ${DATE_FROM} → ${DATE_TO} | limit=${LIMIT}"

  local query result hit_count
  query=$(build_errors_query "$DATE_FROM" "$DATE_TO" "$LIMIT")
  result=$(os_query "logs-*" "$query")
  hit_count=$(echo "$result" | jq '.hits.total.value')
  ok "Found ${hit_count} error trace entries"

  if [[ "$OUTPUT_JSON" -eq 1 ]]; then
    emit_output "$(echo "$result" | jq '.')" "$OUTPUT_FILE"
  else
    local title="Error Traces (${DATE_FROM} → ${DATE_TO})"
    emit_output "$(format_trace_md "$result" "$title" "$DATE_FROM" "$DATE_TO")" "$OUTPUT_FILE"
  fi
}

cmd_loops() {
  parse_os_flags "$@" || true

  info "Finding loop warnings: ${DATE_FROM} → ${DATE_TO} | limit=${LIMIT}"

  local query result hit_count
  query=$(build_loops_query "$DATE_FROM" "$DATE_TO" "$LIMIT")
  result=$(os_query "logs-*" "$query")
  hit_count=$(echo "$result" | jq '.hits.total.value')
  ok "Found ${hit_count} loop warning entries"

  if [[ "$OUTPUT_JSON" -eq 1 ]]; then
    emit_output "$(echo "$result" | jq '.')" "$OUTPUT_FILE"
  else
    local title="Loop Warnings (${DATE_FROM} → ${DATE_TO})"
    emit_output "$(format_trace_md "$result" "$title" "$DATE_FROM" "$DATE_TO")" "$OUTPUT_FILE"
  fi
}

# (#11) New: quick "last N minutes" command
cmd_tail() {
  local minutes="${1:-30}"
  shift || true

  # Remaining args go to parse_os_flags (for --json, --out, --verbose, --limit)
  parse_os_flags "$@" || true

  local tail_from
  tail_from=$(minutes_ago "$minutes")
  local tail_to
  tail_to=$(default_to)

  info "Tailing traces: last ${minutes} minutes (${tail_from} → ${tail_to}) | limit=${LIMIT}"

  local query result hit_count
  query=$(jq -nc \
    --arg gte "$tail_from" \
    --arg lte "$tail_to" \
    --argjson size "$LIMIT" \
    '{
      query: {
        bool: {
          must: [ { match_phrase: { log: "chat-req-trace" } } ],
          filter: { range: { "@timestamp": { gte: $gte, lte: $lte } } }
        }
      },
      size: $size,
      sort: [{ "@timestamp": "asc" }]
    }')

  result=$(os_query "logs-*" "$query")
  hit_count=$(echo "$result" | jq '.hits.total.value')
  ok "Found ${hit_count} trace entries in last ${minutes} minutes"

  if [[ "$OUTPUT_JSON" -eq 1 ]]; then
    emit_output "$(echo "$result" | jq '.')" "$OUTPUT_FILE"
  else
    local title="Traces: last ${minutes} minutes"
    emit_output "$(format_trace_md "$result" "$title" "$tail_from" "$tail_to")" "$OUTPUT_FILE"
  fi
}

# (#1, #3, #12) Fixed: no OpenSearch creds needed, no eval, connected indicator
cmd_live() {
  local user_filter="" agent_filter=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)  user_filter="$2"; shift 2 ;;
      --agent) agent_filter="$2"; shift 2 ;;
      --help|-h) show_live_help; return ;;
      *) err "Unknown flag: $1"; exit 1 ;;
    esac
  done

  if ! command -v doctl &>/dev/null; then
    err "doctl not installed. Install with: brew install doctl"
    exit 1
  fi

  # (#12) Show what we're doing
  local filter_desc="all traces"
  [[ -n "$user_filter" ]]  && filter_desc="userId=${user_filter}"
  [[ -n "$agent_filter" ]] && filter_desc="${filter_desc:+${filter_desc}, }agentId=${agent_filter}"
  info "Tailing live logs: ${filter_desc} (Ctrl+C to stop)..."
  info "Connected. Waiting for matching log entries..."

  # (#3) No eval — build a proper pipeline
  doctl apps logs "${DXLOG_DO_APP_ID}" --type run --follow --no-prefix \
    | grep --line-buffered "chat-req-trace" \
    | if [[ -n "$user_filter" ]]; then grep -F --line-buffered "userId=${user_filter}"; else cat; fi \
    | if [[ -n "$agent_filter" ]]; then grep -F --line-buffered "agentId=${agent_filter}"; else cat; fi
}

cmd_indices() {
  info "Fetching index list..."

  local response
  response=$(curl -s --connect-timeout 10 --max-time 15 \
    -u "${DXLOG_OPENSEARCH_USER}:${DXLOG_OPENSEARCH_PASS}" \
    "${OS_BASE}/_cat/indices/logs*?v&s=index" 2>/dev/null) || {
      err "Failed to fetch indices"
      exit 1
    }

  echo "$response"
}

# -----------------------------------------------------------------------------
# Interactive wizard — runs on `dxlog` (no args) or `dxlog wizard`
# Walks: action → identifier (if needed) → time period → limit → format → output
# Re-execs the script with the constructed args; env vars are inherited.
# -----------------------------------------------------------------------------
prompt_choice() {
  local prompt="$1"; shift
  local default="$1"; shift
  local choices=("$@")
  local i=1 reply

  echo "" >&2
  echo "${prompt}" >&2
  for c in "${choices[@]}"; do
    echo "  ${i}) ${c}" >&2
    ((i++))
  done
  read -rp "> [${default}] " reply
  reply="${reply:-$default}"
  if [[ ! "$reply" =~ ^[0-9]+$ ]] || (( reply < 1 || reply > ${#choices[@]} )); then
    err "Invalid choice: ${reply}"
    exit 1
  fi
  echo "$reply"
}

prompt_text() {
  local prompt="$1"
  local default="${2:-}"
  local reply
  if [[ -n "$default" ]]; then
    read -rp "${prompt} [${default}]: " reply
    echo "${reply:-$default}"
  else
    read -rp "${prompt}: " reply
    while [[ -z "$reply" ]]; do
      err "Value required."
      read -rp "${prompt}: " reply
    done
    echo "$reply"
  fi
}

# Convert a free-form string into a filename-safe slug
slugify() {
  echo "$1" | tr -c 'A-Za-z0-9_.-' '_' | sed 's/__*/_/g; s/^_//; s/_$//'
}

cmd_wizard() {
  echo "" >&2
  echo "─── dxlog wizard ───" >&2

  local action
  action=$(prompt_choice "What do you want to look up?" "1" \
    "Trace by agentId" \
    "Trace by userId" \
    "Trace by chatId" \
    "Search all logs for a term" \
    "Find error traces" \
    "Find loop warnings" \
    "Tail recent traces (last N minutes)" \
    "Live tail via doctl" \
    "List available indices")

  local cmd args=() slug id_val term mins
  case "$action" in
    9)
      info "Running: dxlog indices"
      exec "$0" indices
      ;;
    8)
      local filter
      filter=$(prompt_choice "Filter live tail?" "1" \
        "No filter (all traces)" \
        "By userId" \
        "By agentId")
      case "$filter" in
        2) id_val=$(prompt_text "userId");  args=(--user  "$id_val") ;;
        3) id_val=$(prompt_text "agentId"); args=(--agent "$id_val") ;;
      esac
      info "Running: dxlog live ${args[*]}"
      exec "$0" live "${args[@]}"
      ;;
    1) cmd="trace"; id_val=$(prompt_text "agentId"); args=(--agent "$id_val"); slug="trace-agent-$(slugify "$id_val")" ;;
    2) cmd="trace"; id_val=$(prompt_text "userId");  args=(--user  "$id_val"); slug="trace-user-$(slugify "$id_val")"  ;;
    3) cmd="trace"; id_val=$(prompt_text "chatId");  args=(--chat  "$id_val"); slug="trace-chat-$(slugify "$id_val")"  ;;
    4) cmd="search"; term=$(prompt_text "Search term"); args=("$term"); slug="search-$(slugify "$term")" ;;
    5) cmd="errors"; slug="errors" ;;
    6) cmd="loops";  slug="loops"  ;;
    7)
      cmd="tail"
      mins=$(prompt_text "Minutes" "30")
      args=("$mins")
      slug="tail-${mins}min"
      ;;
  esac

  # Time window — skipped for `tail` (which uses the minutes arg instead)
  if [[ "$cmd" != "tail" ]]; then
    local tchoice
    tchoice=$(prompt_choice "Time period:" "2" \
      "Last 1 hour" \
      "Last 24 hours" \
      "Last 7 days" \
      "Last 30 days" \
      "Custom (specify from/to)")
    case "$tchoice" in
      1) args+=(--from "$(date -u -d '1 hour ago'  '+%Y-%m-%dT%H:%M:%SZ')") ;;
      2) ;;  # 24h is the script default
      3) args+=(--from "$(date -u -d '7 days ago'  '+%Y-%m-%dT%H:%M:%SZ')") ;;
      4) args+=(--from "$(date -u -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ')") ;;
      5)
        local fd td
        fd=$(prompt_text "From (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ)")
        td=$(prompt_text "To   (blank = now)" "$(default_to)")
        args+=(--from "$fd" --to "$td")
        ;;
    esac
  fi

  # Result limit
  local limit
  limit=$(prompt_text "Max results" "50")
  args+=(--limit "$limit")

  # Output format
  local fmt
  fmt=$(prompt_choice "Output format:" "1" \
    "Markdown report" \
    "Raw JSON")
  local ext="md"
  if [[ "$fmt" == "2" ]]; then
    args+=(--json)
    ext="json"
  fi

  # Destination
  local dest out_path
  dest=$(prompt_choice "Output destination:" "2" \
    "Print to terminal" \
    "Save to ~/dxlog-reports/ (auto-named)" \
    "Custom path")
  case "$dest" in
    1) ;;
    2)
      mkdir -p "${HOME}/dxlog-reports"
      out_path="${HOME}/dxlog-reports/${slug}-$(date -u '+%Y%m%d-%H%M%SZ').${ext}"
      args+=(-o "$out_path")
      ;;
    3)
      out_path=$(prompt_text "Output path")
      args+=(-o "$out_path")
      ;;
  esac

  echo "" >&2
  info "Running: dxlog ${cmd} ${args[*]}"
  echo "" >&2

  # Re-exec via this script directly. The wrapper-exported env vars are
  # inherited; load_os_config / load_doctl_config still runs in the new
  # process to validate.
  exec "$0" "$cmd" "${args[@]}"
}

# -----------------------------------------------------------------------------
# Help — per-command (#10)
# -----------------------------------------------------------------------------
show_trace_help() {
  cat <<'HELP'
dxlog trace — Query chat-req-trace logs

USAGE:
  dxlog trace --agent <id> [options]
  dxlog trace --user <id>  [options]
  dxlog trace --chat <id>  [options]

FILTERS (pick one):
  --agent <id>       Filter by agentId
  --user <id>        Filter by userId
  --chat <id>        Filter by chatId

OPTIONS:
  --from, -f <date>  Start date (default: 24h ago)
  --to, -t <date>    End date (default: now)
  --limit, -n <num>  Max results (default: 50)
  --json             Raw JSON output
  --out, -o <file>   Write to file
  --verbose          Show OpenSearch query
HELP
}

show_live_help() {
  cat <<'HELP'
dxlog live — Tail live logs via doctl

USAGE:
  dxlog live [--user <id>] [--agent <id>]

OPTIONS:
  --user <id>    Filter to specific userId
  --agent <id>   Filter to specific agentId

Requires doctl installed and authenticated.
Does NOT require OpenSearch credentials.
HELP
}

show_help() {
  cat <<'HELP'
dxlog — DataX OpenSearch Log Diagnostic Tool

Running `dxlog` with no arguments launches an interactive wizard.

COMMANDS:
  wizard                    Interactive prompt (same as running `dxlog` with no args)
  init                      Create config template at ~/.config/dxlog/env (no-op if env vars are set)
  trace                     Query chat-req-trace logs (requires --agent, --user, or --chat)
  search <term>             Search all logs for a term
  errors                    Find trace entries with errors or loop warnings
  loops                     Find trace entries with loop warnings specifically
  tail [minutes]            Last N minutes of all traces (default: 30)
  live                      Tail live logs via doctl (optional --user, --agent filters)
  indices                   List available log indices

OPTIONS (apply to trace, search, errors, loops, tail):
  --from, -f <date>         Start date: YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS (default: 24h ago)
  --to, -t <date>           End date (default: now)
  --limit, -n <num>         Max results (default: 50)
  --json                    Output raw JSON instead of markdown
  --out, -o <file>          Write output to file
  --verbose                 Show the OpenSearch query being sent
  --help, -h                Help (global or per-command)

EXAMPLES:
  dxlog init
  dxlog trace --agent CVoS8hRoodbr0GloorC5 --from 2026-05-20 --to 2026-05-21
  dxlog trace --user L9zUKy8TV1WrukTpmrr0HaWpwB73 -f 2026-05-20 -o report.md
  dxlog tail 60                                # last hour of all traces
  dxlog errors --from 2026-05-27 --limit 20
  dxlog loops --from 2026-05-20 --to 2026-05-28
  dxlog search "4QXix7bscaBVnLRKwLVs" -f 2026-05-20
  dxlog live --agent CVoS8hRoodbr0GloorC5
  dxlog indices

SETUP:
  1. Run: dxlog init
  2. Edit ~/.config/dxlog/env with your OpenSearch credentials
  3. Run: dxlog indices   (to verify connection)
HELP
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  # No args → wizard
  if [[ $# -eq 0 ]]; then
    cmd_wizard
    return
  fi

  local cmd="$1"; shift

  # Check for --help before loading config (avoids cred errors on help)
  for arg in "$@"; do
    [[ "$arg" == "--help" || "$arg" == "-h" ]] && {
      case "$cmd" in
        trace) show_trace_help; return ;;
        live)  show_live_help; return ;;
        *)     show_help; return ;;
      esac
    }
  done

  case "$cmd" in
    wizard)   cmd_wizard ;;
    init)     cmd_init ;;
    trace)    load_os_config; cmd_trace "$@" ;;
    search)   load_os_config; cmd_search "$@" ;;
    errors)   load_os_config; cmd_errors "$@" ;;
    loops)    load_os_config; cmd_loops "$@" ;;
    tail)     load_os_config; cmd_tail "$@" ;;
    live)     load_doctl_config; cmd_live "$@" ;;
    indices)  load_os_config; cmd_indices ;;
    --help|-h|help) show_help ;;
    --version|-v) echo "dxlog ${VERSION}" ;;
    *)
      err "Unknown command: ${cmd}"
      echo "Run 'dxlog --help' for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
