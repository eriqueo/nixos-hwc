#!/usr/bin/env bash
# Permission Pattern Linter for nixos-hwc
# Validates compliance with docs/standards/permission-patterns.md
#
# Usage: ./permission-lint.sh [domain_path] [--fix]
#
# Examples:
#   ./permission-lint.sh domains/server
#   ./permission-lint.sh domains/server --fix
#   ./permission-lint.sh                      # Check all domains

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
FIXED=0

# Mode
FIX_MODE=false

# Parse arguments
SEARCH_PATH="${1:-.}"
if [[ "${2:-}" == "--fix" ]] || [[ "${1:-}" == "--fix" ]]; then
    FIX_MODE=true
    echo -e "${BLUE}Running in FIX mode${NC}"
fi

lint_error() {
    local file=$1
    local message=$2
    local suggestion=$3

    echo -e "${RED}ERROR${NC}: $file"
    echo "  Issue: $message"
    echo "  Fix: $suggestion"
    echo ""
    ((ERRORS++))
}

lint_warning() {
    local file=$1
    local message=$2
    local suggestion=$3

    echo -e "${YELLOW}WARNING${NC}: $file"
    echo "  Issue: $message"
    echo "  Suggestion: $suggestion"
    echo ""
    ((WARNINGS++))
}

lint_info() {
    local message=$1
    echo -e "${BLUE}INFO${NC}: $message"
}

#==========================================================================
# PERMISSION PATTERN VALIDATION
#==========================================================================

check_container_pgid() {
    local module_file=$1

    # Check for PGID="1000" in container configurations
    if rg -q 'PGID.*=.*"1000"' "$module_file" 2>/dev/null; then
        local line_num=$(rg -n 'PGID.*=.*"1000"' "$module_file" | head -1 | cut -d: -f1)
        lint_error "$module_file:$line_num" \
            "Container uses PGID=\"1000\" but users group is GID 100" \
            "Change to PGID=\"100\" (see docs/standards/permission-patterns.md Pattern 1)"

        if [[ "$FIX_MODE" == true ]]; then
            # Auto-fix: Replace PGID="1000" with PGID="100"
            sed -i 's/PGID.*=.*"1000"/PGID = "100"/' "$module_file"
            echo -e "${GREEN}  ✓ Auto-fixed PGID${NC}"
            ((FIXED++))
        fi
    fi
}

check_statedirectory_user() {
    local module_file=$1

    # Check for StateDirectory without User/Group
    if rg -q 'StateDirectory.*=' "$module_file" 2>/dev/null; then
        if ! rg -q 'User.*=.*eric' "$module_file" 2>/dev/null; then
            local line_num=$(rg -n 'StateDirectory.*=' "$module_file" | head -1 | cut -d: -f1)
            lint_warning "$module_file:$line_num" \
                "StateDirectory defined without User = eric" \
                "Add User = lib.mkForce \"eric\" (see docs/standards/permission-patterns.md Pattern 2)"
        fi

        if ! rg -q 'Group.*=.*users' "$module_file" 2>/dev/null; then
            local line_num=$(rg -n 'StateDirectory.*=' "$module_file" | head -1 | cut -d: -f1)
            lint_warning "$module_file:$line_num" \
                "StateDirectory defined without Group = users" \
                "Add Group = lib.mkForce \"users\" (see docs/standards/permission-patterns.md Pattern 2)"
        fi
    fi
}

check_secret_permissions() {
    local module_file=$1

    # Check for age.secrets without mode/group
    if rg -q 'age\.secrets\.' "$module_file" 2>/dev/null; then
        # Get all secret declarations
        local secrets=$(rg -o 'age\.secrets\.[a-zA-Z0-9_-]+' "$module_file" 2>/dev/null | cut -d. -f3 | sort -u)

        for secret in $secrets; do
            # Check if this is a declaration (has = {)
            if rg -q "age\.secrets\.$secret.*=.*\{" "$module_file" 2>/dev/null; then
                # Check for mode
                if ! rg -A5 "age\.secrets\.$secret" "$module_file" 2>/dev/null | rg -q 'mode.*=.*"0440"'; then
                    local line_num=$(rg -n "age\.secrets\.$secret" "$module_file" | head -1 | cut -d: -f1)
                    lint_warning "$module_file:$line_num" \
                        "Secret '$secret' missing mode = \"0440\"" \
                        "All secrets should be mode 0440 for read-only access (see Pattern 3)"
                fi

                # Check for group
                if ! rg -A5 "age\.secrets\.$secret" "$module_file" 2>/dev/null | rg -q 'group.*=.*"secrets"'; then
                    local line_num=$(rg -n "age\.secrets\.$secret" "$module_file" | head -1 | cut -d: -f1)
                    lint_warning "$module_file:$line_num" \
                        "Secret '$secret' missing group = \"secrets\"" \
                        "All secrets should use group secrets for access control (see Pattern 3)"
                fi
            fi
        done
    fi
}

check_hardcoded_secret_paths() {
    local module_file=$1

    # Check for hardcoded /run/agenix paths instead of config.age.secrets
    if rg -q '"/run/agenix/' "$module_file" 2>/dev/null; then
        local line_num=$(rg -n '"/run/agenix/' "$module_file" | head -1 | cut -d: -f1)
        lint_error "$module_file:$line_num" \
            "Hardcoded /run/agenix path detected" \
            "Use config.age.secrets.<name>.path instead (see Pattern 3)"
    fi
}

check_mkforce_usage() {
    local module_file=$1

    # Check if User/Group set without mkForce
    if rg -q 'User.*=.*"eric"' "$module_file" 2>/dev/null; then
        if ! rg -q 'User.*=.*lib\.mkForce.*"eric"' "$module_file" 2>/dev/null; then
            local line_num=$(rg -n 'User.*=.*"eric"' "$module_file" | head -1 | cut -d: -f1)
            lint_warning "$module_file:$line_num" \
                "User = \"eric\" without lib.mkForce" \
                "Use User = lib.mkForce \"eric\" to override NixOS defaults (see Pattern 2)"
        fi
    fi

    if rg -q 'Group.*=.*"users"' "$module_file" 2>/dev/null; then
        if ! rg -q 'Group.*=.*lib\.mkForce.*"users"' "$module_file" 2>/dev/null; then
            local line_num=$(rg -n 'Group.*=.*"users"' "$module_file" | head -1 | cut -d: -f1)
            lint_warning "$module_file:$line_num" \
                "Group = \"users\" without lib.mkForce" \
                "Use Group = lib.mkForce \"users\" to override NixOS defaults (see Pattern 2)"
        fi
    fi
}

#==========================================================================
# MAIN
#==========================================================================

echo "Permission Pattern Linter - nixos-hwc"
echo "======================================"
echo ""
echo "Checking: $SEARCH_PATH"
echo ""

# Find all Nix module files
MODULE_FILES=$(find "$SEARCH_PATH" -type f \( -name "index.nix" -o -name "options.nix" -o -name "*.nix" \) 2>/dev/null || true)

if [[ -z "$MODULE_FILES" ]]; then
    echo "No Nix files found in $SEARCH_PATH"
    exit 0
fi

# Run permission checks on all modules
for module in $MODULE_FILES; do
    check_container_pgid "$module"
    check_statedirectory_user "$module"
    check_secret_permissions "$module"
    check_hardcoded_secret_paths "$module"
    check_mkforce_usage "$module"
done

# Summary
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
    echo "See docs/standards/permission-patterns.md for correct patterns"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Permission pattern validation completed with warnings${NC}"
    echo "Review warnings and consider fixing them"
    exit 0
else
    echo -e "${GREEN}✅ All permission pattern checks passed${NC}"
    exit 0
fi
