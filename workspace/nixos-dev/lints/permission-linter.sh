#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
FIXED=0
FIX_MODE=false

SEARCH_PATH="${1:-.}"
if [[ "${2:-}" == "--fix" || "${1:-}" == "--fix" ]]; then
    FIX_MODE=true
    echo -e "${BLUE}Running in FIX mode${NC}"
fi

lint_error() {
    echo -e "${RED}ERROR${NC}: $1"
    echo "  Issue: $2"
    echo "  Fix: $3"
    echo ""
    ((ERRORS++))
}

lint_warning() {
    echo -e "${YELLOW}WARNING${NC}: $1"
    echo "  Issue: $2"
    echo "  Suggestion: $3"
    echo ""
    ((WARNINGS++))
}

echo "Permission Pattern Linter - nixos-hwc"
echo "======================================"
echo ""
echo "Checking: $SEARCH_PATH"
echo ""

MODULE_FILES=$(find "$SEARCH_PATH" -type f -name "*.nix" 2>/dev/null || true)

if [[ -z "$MODULE_FILES" ]]; then
    echo "No Nix files found in $SEARCH_PATH"
    exit 0
fi

check_container_pgid() {
    local file=$1
    local matches
    matches=$(rg -n '\bPGID\s*=\s*"1000"' "$file" || true)
    [[ -z "$matches" ]] && return

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local num="${line%%:*}"
        lint_error "$file:$num" "Container uses PGID=\"1000\"" "Change to PGID=\"100\""
    done <<< "$matches"

    if [[ "$FIX_MODE" == true ]]; then
        sed -i 's/\bPGID\s*=\s*"1000"/PGID = "100"/g' "$file"
        ((FIXED++))
    fi
}

check_statedirectory_user() {
    local file=$1
    local states
    states=$(rg -n '\bStateDirectory\s*=' "$file" || true)
    [[ -z "$states" ]] && return

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local num="${line%%:*}"
        if ! rg -q '\bUser\s*=\s*lib\.mkForce\s*"eric"' "$file"; then
            lint_warning "$file:$num" "StateDirectory defined without forced User" "Add User = lib.mkForce \"eric\" in the same serviceConfig block"
        fi
        if ! rg -q '\bGroup\s*=\s*lib\.mkForce\s*"users"' "$file"; then
            lint_warning "$file:$num" "StateDirectory defined without forced Group" "Add Group = lib.mkForce \"users\" in the same serviceConfig block"
        fi
    done <<< "$states"
}

check_secret_permissions() {
    local file=$1
    local secrets
    secrets=$(rg -o 'age\.secrets\.[a-zA-Z0-9_-]+' "$file" | sort -u || true)
    [[ -z "$secrets" ]] && return

    while IFS= read -r secret; do
        [[ -z "$secret" ]] && continue
        local name="${secret##*.}"
        local decl
        decl=$(rg -n "age\.secrets\.$name" -A20 "$file" || true)
        [[ -z "$decl" ]] && continue
        local num
        num=$(grep -m1 -o '^[0-9]*' <<< "$decl")

        if ! grep -q 'mode\s*=\s*"0440"' <<< "$decl"; then
            lint_warning "$file:$num" "Secret '$name' missing mode = \"0440\"" "Add mode = \"0440\" in its declaration block"
        fi

        if ! grep -q 'group\s*=\s*"secrets"' <<< "$decl"; then
            lint_warning "$file:$num" "Secret '$name' missing group = \"secrets\"" "Add group = \"secrets\" in its declaration block"
        fi
    done <<< "$secrets"
}

check_hardcoded_secret_paths() {
    local file=$1
    local matches
    matches=$(rg -n '/run/agenix/' "$file" || true)
    [[ -z "$matches" ]] && return

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local num="${line%%:*}"
        lint_error "$file:$num" "Hardcoded /run/agenix path" "Use config.age.secrets.<name>.path instead"
    done <<< "$matches"
}

check_mkforce_usage() {
    local file=$1
    if ! rg -q 'systemd\.services\.' "$file" 2>/dev/null; then
        return
    fi

    local users
    users=$(rg -n '\bUser\s*=\s*"eric"' "$file" || true)
    if [[ -n "$users" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local num="${line%%:*}"
            if ! rg -q '\bUser\s*=\s*lib\.mkForce\s*"eric"' "$file"; then
                lint_warning "$file:$num" "User = \"eric\" without lib.mkForce in systemd service" "Use User = lib.mkForce \"eric\""
            fi
        done <<< "$users"
    fi

    local groups
    groups=$(rg -n '\bGroup\s*=\s*"users"' "$file" || true)
    if [[ -n "$groups" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local num="${line%%:*}"
            if ! rg -q '\bGroup\s*=\s*lib\.mkForce\s*"users"' "$file"; then
                lint_warning "$file:$num" "Group = \"users\" without lib.mkForce in systemd service" "Use Group = lib.mkForce \"users\""
            fi
        done <<< "$groups"
    fi
}

for module in $MODULE_FILES; do
    check_container_pgid "$module"
    check_statedirectory_user "$module"
    check_secret_permissions "$module"
    check_hardcoded_secret_paths "$module"
    check_mkforce_usage "$module"
done

echo ""
echo "======================================"
echo "Summary"
echo "======================================"
echo -e "${RED}Errors:${NC}   $ERRORS"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
if [[ "$FIX_MODE" == true ]]; then
    echo -e "${GREEN}Fixed:${NC}    $FIXED"
fi
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}❌ Permission pattern validation FAILED${NC}"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Permission pattern validation completed with warnings${NC}"
    exit 0
else
    echo -e "${GREEN}✅ All permission pattern checks passed${NC}"
    exit 0
fi
