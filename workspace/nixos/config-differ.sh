#!/bin/bash
# Configuration Comparison Tool
# Compares two system distillations to identify differences

set -euo pipefail

usage() {
    cat << EOF
Usage: $0 <old-config.json> <new-config.json>

Compare two system distillations and highlight differences.
Focuses on functional differences while ignoring cosmetic changes.

Examples:
    # Basic comparison
    $0 old-system.json new-system.json

    # Just containers
    $0 old-system.json new-system.json --section=containers

    # Detailed diff with line numbers
    $0 old-system.json new-system.json --detailed
EOF
}

SECTION=""
DETAILED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --section=*)
            SECTION="${1#*=}"
            shift
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "${OLD_CONFIG:-}" ]]; then
                OLD_CONFIG="$1"
            elif [[ -z "${NEW_CONFIG:-}" ]]; then
                NEW_CONFIG="$1"
            else
                echo "Error: Too many arguments" >&2
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "${OLD_CONFIG:-}" ]] || [[ -z "${NEW_CONFIG:-}" ]]; then
    echo "Error: Need both old and new config files" >&2
    usage
    exit 1
fi

if [[ ! -f "$OLD_CONFIG" ]] || [[ ! -f "$NEW_CONFIG" ]]; then
    echo "Error: Config files must exist" >&2
    exit 1
fi

# Helper functions
extract_section() {
    local file="$1"
    local section="$2"
    
    if [[ -n "$section" ]]; then
        jq -r ".$section" "$file" 2>/dev/null || echo "{}"
    else
        cat "$file"
    fi
}

normalize_json() {
    local file="$1"
    # Sort keys, remove metadata timestamps, normalize paths
    jq -S 'del(.metadata.timestamp) | del(.systemd.services[].timestamp)' "$file" 2>/dev/null || echo "{}"
}

compare_containers() {
    echo "=== CONTAINER DIFFERENCES ==="
    
    # Extract container names
    OLD_CONTAINERS=$(jq -r '.containers | keys[]' "$OLD_CONFIG" 2>/dev/null | sort)
    NEW_CONTAINERS=$(jq -r '.containers | keys[]' "$NEW_CONFIG" 2>/dev/null | sort)
    
    # Show added/removed containers
    comm -23 <(echo "$NEW_CONTAINERS") <(echo "$OLD_CONTAINERS") | while read -r container; do
        echo "ADDED: Container $container"
    done
    
    comm -13 <(echo "$NEW_CONTAINERS") <(echo "$OLD_CONTAINERS") | while read -r container; do
        echo "REMOVED: Container $container"
    done
    
    # Compare existing containers
    comm -12 <(echo "$NEW_CONTAINERS") <(echo "$OLD_CONTAINERS") | while read -r container; do
        echo "--- Comparing container: $container ---"
        
        OLD_CONTAINER=$(jq ".containers[\"$container\"]" "$OLD_CONFIG")
        NEW_CONTAINER=$(jq ".containers[\"$container\"]" "$NEW_CONFIG")
        
        # Key comparisons
        for field in "image" "volumes" "ports" "environment" "devices"; do
            OLD_VAL=$(echo "$OLD_CONTAINER" | jq -r ".$field // empty")
            NEW_VAL=$(echo "$NEW_CONTAINER" | jq -r ".$field // empty")
            
            if [[ "$OLD_VAL" != "$NEW_VAL" ]]; then
                echo "  DIFF $field:"
                echo "    OLD: $OLD_VAL"
                echo "    NEW: $NEW_VAL"
            fi
        done
    done
}

compare_services() {
    echo "=== SYSTEMD SERVICE DIFFERENCES ==="
    
    OLD_SERVICES=$(jq -r '.systemd.services | keys[]' "$OLD_CONFIG" 2>/dev/null | sort)
    NEW_SERVICES=$(jq -r '.systemd.services | keys[]' "$NEW_CONFIG" 2>/dev/null | sort)
    
    # Show added/removed services
    comm -23 <(echo "$NEW_SERVICES") <(echo "$OLD_SERVICES") | while read -r service; do
        echo "ADDED: Service $service"
    done
    
    comm -13 <(echo "$NEW_SERVICES") <(echo "$OLD_SERVICES") | while read -r service; do
        echo "REMOVED: Service $service"
    done
    
    # Check for critical service changes (enabled/disabled)
    comm -12 <(echo "$NEW_SERVICES") <(echo "$OLD_SERVICES") | while read -r service; do
        OLD_STATE=$(jq -r ".systemd.services[\"$service\"].active_state // \"unknown\"" "$OLD_CONFIG")
        NEW_STATE=$(jq -r ".systemd.services[\"$service\"].active_state // \"unknown\"" "$NEW_CONFIG")
        
        if [[ "$OLD_STATE" != "$NEW_STATE" ]]; then
            echo "STATE CHANGE: $service ($OLD_STATE → $NEW_STATE)"
        fi
    done
}

compare_networking() {
    echo "=== NETWORKING DIFFERENCES ==="
    
    # Compare listening ports
    OLD_PORTS=$(jq -r '.networking.services[]? | "\(.protocol):\(.local_address)"' "$OLD_CONFIG" 2>/dev/null | sort)
    NEW_PORTS=$(jq -r '.networking.services[]? | "\(.protocol):\(.local_address)"' "$NEW_CONFIG" 2>/dev/null | sort)
    
    comm -23 <(echo "$NEW_PORTS") <(echo "$OLD_PORTS") | while read -r port; do
        echo "ADDED PORT: $port"
    done
    
    comm -13 <(echo "$NEW_PORTS") <(echo "$OLD_PORTS") | while read -r port; do
        echo "REMOVED PORT: $port"
    done
}

# Main comparison logic
main() {
    echo "Comparing system configurations..."
    echo "OLD: $OLD_CONFIG"
    echo "NEW: $NEW_CONFIG"
    echo

    if [[ "$SECTION" == "containers" ]]; then
        compare_containers
    elif [[ "$SECTION" == "services" ]]; then
        compare_services
    elif [[ "$SECTION" == "networking" ]]; then
        compare_networking
    else
        # Full comparison
        compare_containers
        echo
        compare_services
        echo
        compare_networking
        
        if [[ "$DETAILED" == "true" ]]; then
            echo
            echo "=== DETAILED JSON DIFF ==="
            diff -u <(normalize_json "$OLD_CONFIG") <(normalize_json "$NEW_CONFIG") || true
        fi
    fi
}

main "$@"