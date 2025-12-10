#!/usr/bin/env bash
# Comprehensive Health Check Script with Auto-Discovery (NixOS Path-Fixed)
set -euo pipefail

# --- HARDCODED PATHS FOR NIXOS ---
PODMAN_BIN="/run/current-system/sw/bin/podman"
SYSTEMCTL_BIN="/run/current-system/sw/bin/systemctl"
AWK_BIN="/run/current-system/sw/bin/awk"
CURL_BIN="${CURL_BIN:-/run/current-system/sw/bin/curl}"
# ----------------------------------

# Configuration
TIMEOUT="${TIMEOUT:-5}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"  # json or human
INCLUDE_HEALTHY="${INCLUDE_HEALTHY:-1}" # 0 = only report failures

# Utility
have() { [ -x "$1" ]; }
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# JSON helpers
json_escape() {
    local s="${1:-}"
    # escape backslashes, double quotes, newlines, tabs
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# json_value VALUE [numeric_allowed]
# prints a JSON literal: number|null|"string"
json_value() {
    local v="${1-}"
    local numeric_allowed="${2:-0}"
    if [[ -z "${v}" ]]; then
        printf 'null'
        return
    fi
    if [[ "$numeric_allowed" -eq 1 && "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        printf '%s' "$v"
        return
    fi
    # else treat as string (escape)
    printf '"%s"' "$(json_escape "$v")"
}

# Global results array (each element is a JSON object string)
RESULTS=()

add_result() {
    local service="$1"
    local type="$2"
    local healthy="$3"   # should be "true" or "false"
    local status_code="${4:-}"
    local error_msg="${5:-}"
    local response_time="${6:-}"
    local extra="${7:-}"

    # normalize healthy to boolean
    local healthy_json="false"
    if [[ "$healthy" == "true" || "$healthy" == "1" ]]; then
        healthy_json="true"
    fi

    # statusCode: number if purely digits, else string or null
    local status_json
    if [[ -z "$status_code" ]]; then
        status_json="null"
    elif [[ "$status_code" =~ ^-?[0-9]+$ ]]; then
        status_json="$status_code"
    else
        status_json="$(json_value "$status_code" 0)"
    fi

    # responseTime: numeric allowed (float), else null or string
    local response_json
    if [[ -z "$response_time" ]]; then
        response_json="null"
    elif [[ "$response_time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        response_json="$response_time"
    else
        response_json="$(json_value "$response_time" 0)"
    fi

    # error message and extra always strings or null
    local error_json
    if [[ -z "$error_msg" ]]; then
        error_json="null"
    else
        error_json="$(json_value "$error_msg" 0)"
    fi

    local extra_json
    if [[ -z "$extra" ]]; then
        extra_json="null"
    else
        extra_json="$(json_value "$extra" 0)"
    fi

    # Build the JSON object
    local j
    j=$(cat <<EOF
{
  "service": "$(json_escape "$service")",
  "type": "$(json_escape "$type")",
  "healthy": $healthy_json,
  "timestamp": "$(timestamp)",
  "statusCode": $status_json,
  "errorMessage": $error_json,
  "responseTime": $response_json,
  "extra": $extra_json
}
EOF
)
    RESULTS+=("$j")
}

# Podman container checks
check_podman_containers() {
    if ! have "$PODMAN_BIN"; then
        return 0
    fi

    local containers
    containers=$("$PODMAN_BIN" ps -a --format "{{.Names}}|{{.Status}}|{{.ID}}" 2>/dev/null || echo "")
    if [[ -z "$containers" ]]; then
        return 0
    fi

    while IFS='|' read -r name status id; do
        [[ -z "$name" ]] && continue

        if [[ "$status" =~ ^Up ]]; then
            local health_status
            health_status=$("$PODMAN_BIN" inspect "$id" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
            if [[ "$health_status" == "healthy" || "$health_status" == "none" ]]; then
                add_result "$name" "podman" "true" "" "" "" "status: $status"
            else
                add_result "$name" "podman" "false" "" "Health check failed: $health_status" "" "status: $status"
            fi
        else
            add_result "$name" "podman" "false" "" "Container not running" "" "status: $status"
        fi
    done <<< "$containers"
}

# Systemd services checks
check_systemd_services() {
    if ! have "$SYSTEMCTL_BIN"; then
        return 0
    fi

    local services=( "caddy" "tailscaled" "sshd" )

    # attempt to discover podman services; fallback without awk if not present
    local podman_services_raw
    podman_services_raw=$("$SYSTEMCTL_BIN" list-units --type=service --all --no-legend 'podman-*.service' 2>/dev/null || true)

    if [[ -n "$podman_services_raw" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # extract first whitespace-delimited token (unit name)
            svc="${line%% *}"
            services+=("$svc")
        done <<< "$podman_services_raw"
    fi

    for service in "${services[@]}"; do
        [[ -z "$service" ]] && continue
        local clean_name="${service%.service}"
        local is_active
        is_active=$("$SYSTEMCTL_BIN" is-active "$service" 2>/dev/null || echo "inactive")

        if [[ "$is_active" == "active" ]]; then
            add_result "$clean_name" "systemd" "true" "" "" "" "active"
        else
            local failed_info
            failed_info=$("$SYSTEMCTL_BIN" status "$service" 2>/dev/null | grep -i "failed\|error" | head -1 | xargs || echo "$is_active")
            add_result "$clean_name" "systemd" "false" "" "$failed_info" "" ""
        fi
    done
}

# HTTP endpoint checks
check_http_endpoints() {
    if ! have "$CURL_BIN"; then
        return 0
    fi

    local endpoints=(
        "jellyfin|http://127.0.0.1:8096/health|2.."
        "immich|http://127.0.0.1:2283/api/server/ping|2.."
        "frigate|http://127.0.0.1:5001/api/config|2.."
        "ntfy|http://127.0.0.1:2586/v1/health|2.."
        "n8n|http://127.0.0.1:5678/healthz|2.."
        "prometheus|http://127.0.0.1:9090/-/healthy|2.."
        "alertmanager|http://127.0.0.1:9093/-/healthy|2.."
    )

    for endpoint in "${endpoints[@]}"; do
        IFS='|' read -r name url expected_pattern <<< "$endpoint"
        local response
        local http_code
        local response_time

        response=$("$CURL_BIN" -sS --max-time "$HTTP_TIMEOUT" -o /dev/null -w "%{http_code}|%{time_total}" "$url" 2>&1 || echo "000|0")
        IFS='|' read -r http_code response_time <<< "$response"

        if [[ "$http_code" =~ ^$expected_pattern$ ]]; then
            add_result "$name" "http" "true" "$http_code" "" "$response_time" "$url"
        else
            local error="HTTP $http_code"
            [[ "$http_code" == "000" ]] && error="Connection failed or timeout"
            add_result "$name" "http" "false" "$http_code" "$error" "$response_time" "$url"
        fi
    done
}

# Output results
output_results() {
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local json_array=""
        local first=1
        for result in "${RESULTS[@]}"; do
            if [[ "$INCLUDE_HEALTHY" == "0" ]]; then
                if echo "$result" | grep -q '"healthy": true'; then
                    continue
                fi
            fi
            if [[ $first -eq 1 ]]; then
                json_array="$result"
                first=0
            else
                json_array="$json_array,$result"
            fi
        done
        echo "{\"timestamp\":\"$(timestamp)\",\"checks\":[$json_array]}"
    else
        echo "=== Health Check Report ==="
        echo "Timestamp: $(timestamp)"
        echo ""
        local total=0 healthy=0 unhealthy=0
        for result in "${RESULTS[@]}"; do
            ((total++))
            local service=$(echo "$result" | sed -n 's/.*"service":[[:space:]]*"\([^"]*\)".*/\1/p')
            local type=$(echo "$result" | sed -n 's/.*"type":[[:space:]]*"\([^"]*\)".*/\1/p')
            local is_healthy=$(echo "$result" | sed -n 's/.*"healthy":[[:space:]]*\(true\|false\).*/\1/p')
            local error=$(echo "$result" | sed -n 's/.*"errorMessage":[[:space:]]*"\([^"]*\)".*/\1/p' || true)
            if [[ "$is_healthy" == "true" ]]; then
                ((healthy++))
                if [[ "$INCLUDE_HEALTHY" == "1" ]]; then
                    echo -e "✓ $service ($type)"
                fi
            else
                ((unhealthy++))
                echo -e "✗ $service ($type): $error"
            fi
        done
        echo ""
        echo "=== Summary ==="
        echo "Total checks: $total"
        echo "Healthy: $healthy"
        echo "Unhealthy: $unhealthy"
        [[ $unhealthy -gt 0 ]] && exit 1
    fi
}

# Main
main() {
    check_podman_containers
    check_systemd_services
    check_http_endpoints
    output_results
}

main "$@"
