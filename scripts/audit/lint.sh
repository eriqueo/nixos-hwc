#!/usr/bin/env bash
# CHARTER v8 Compliance Linter - Hard Blocker Gates
# Enforces fail-fast validation of CHARTER architectural rules
#
# Usage: ./lint.sh [path]
#
# Exit codes:
#   0 - All checks passed
#   1 - CHARTER violations detected
#
# CHARTER References:
#   Section 14: Validation & Anti-Patterns
#   Section 3: Domain Boundaries
#   Section 4: Unit Anatomy
#   Section 8: Home Manager Boundary

set -uo pipefail  # Don't use -e, it breaks iteration over rg results

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
ERRORS=0

# Parse arguments
SEARCH_PATH="${1:-.}"

echo "======================================"
echo "CHARTER v8 Compliance Linter"
echo "======================================"
echo ""
echo "Checking: $SEARCH_PATH"
echo ""

lint_error() {
    local category=$1
    local severity=$2
    local location=$3
    local message=$4

    echo -e "${RED}$category${NC} | $severity | $location | $message"
    ((ERRORS++))
}

#==========================================================================
# HARD BLOCKER 1: Options defined outside options.nix
# CHARTER Section 4, 14
#==========================================================================
check_options_placement() {
    echo -e "${BLUE}[1/8]${NC} Checking options placement..."

    # Find all .nix files that are NOT options.nix and NOT sys.nix
    while IFS= read -r file; do
        # Skip if this IS options.nix or sys.nix
        [[ "$file" =~ options\.nix$ ]] && continue
        [[ "$file" =~ sys\.nix$ ]] && continue  # sys.nix defines system-lane options (CHARTER §6)

        # Check for options definitions
        if rg -n '^\s*options\.[a-zA-Z]' "$file" 2>/dev/null; then
            while IFS=: read -r line_num match; do
                lint_error "OPTIONS_PLACEMENT" "HIGH" "$file:$line_num" \
                    "Options defined outside options.nix or sys.nix (CHARTER §4, §14)"
            done < <(rg -n '^\s*options\.[a-zA-Z]' "$file" 2>/dev/null || true)
        fi
    done < <(find "$SEARCH_PATH" -type f -name "*.nix" 2>/dev/null || true)
}

#==========================================================================
# HARD BLOCKER 2: Namespace not matching folder structure
# CHARTER Section 1, 4, 12
#==========================================================================
check_namespace_alignment() {
    echo -e "${BLUE}[2/8]${NC} Checking namespace alignment..."

    # Find all options.nix files in domains/
    while IFS= read -r file; do
        # Extract folder path: domains/home/apps/firefox/options.nix -> home/apps/firefox
        if [[ "$file" =~ domains/([^/]+/[^/]+/[^/]+)/options\.nix ]]; then
            domain_path="${BASH_REMATCH[1]}"
            expected_ns="hwc.${domain_path//\//.}"

            # Check if options use the expected namespace
            if rg -q "options\." "$file" 2>/dev/null; then
                # Get actual namespace
                actual_ns=$(rg -o 'options\.(hwc\.[a-zA-Z0-9.]+)' "$file" 2>/dev/null | head -1 | cut -d' ' -f1 | sed 's/options\.//')

                if [[ -n "$actual_ns" ]] && [[ "$actual_ns" != "$expected_ns"* ]]; then
                    local line_num=$(rg -n "options\.$actual_ns" "$file" 2>/dev/null | head -1 | cut -d: -f1)
                    lint_error "NAMESPACE_MISMATCH" "HIGH" "$file:$line_num" \
                        "Namespace '$actual_ns' doesn't match folder path (expected: $expected_ns.*) (CHARTER §1, §4, §12)"
                fi
            fi
        fi
    done < <(find "$SEARCH_PATH" -type f -path "*/domains/*/options.nix" 2>/dev/null || true)
}

#==========================================================================
# HARD BLOCKER 3: HM activation in profiles (except profiles/home.nix)
# CHARTER Section 8, 14
#==========================================================================
check_hm_activation_in_profiles() {
    echo -e "${BLUE}[3/8]${NC} Checking HM activation in profiles..."

    while IFS= read -r file; do
        # Skip profiles/home.nix - it's the exception
        [[ "$file" =~ profiles/home\.nix$ ]] && continue

        # Check for home-manager activation
        if rg -n 'home-manager\.(users|extraSpecialArgs|useGlobalPkgs|useUserPackages)' "$file" 2>/dev/null; then
            while IFS=: read -r line_num match; do
                lint_error "HM_IN_PROFILES" "HIGH" "$file:$line_num" \
                    "Home Manager activation in profiles (only allowed in machines/<host>/home.nix and profiles/home.nix menu) (CHARTER §8, §14)"
            done < <(rg -n 'home-manager\.(users|extraSpecialArgs|useGlobalPkgs|useUserPackages)' "$file" 2>/dev/null || true)
        fi
    done < <(find "$SEARCH_PATH" -type f -path "*/profiles/*.nix" 2>/dev/null || true)
}

#==========================================================================
# HARD BLOCKER 4: Mixed-domain modules
# CHARTER Section 3, 14
#==========================================================================
check_mixed_domain_modules() {
    echo -e "${BLUE}[4/8]${NC} Checking for mixed-domain modules..."

    # Check system/server domains for HM configs
    while IFS= read -r file; do
        if rg -n '^\s*(programs|home|xdg)\.[a-zA-Z].*=' "$file" 2>/dev/null; then
            while IFS=: read -r line_num match; do
                lint_error "MIXED_DOMAIN" "HIGH" "$file:$line_num" \
                    "Home Manager config in system/server domain (CHARTER §3, §14)"
            done < <(rg -n '^\s*(programs|home|xdg)\.[a-zA-Z].*=' "$file" 2>/dev/null || true)
        fi
    done < <(find "$SEARCH_PATH" -type f \( -path "*/domains/system/*" -o -path "*/domains/server/*" -o -path "*/domains/infrastructure/*" \) -name "*.nix" 2>/dev/null || true)

    # Check for users.users outside domains/system/users/
    while IFS= read -r file; do
        # Skip files in domains/system/users/
        [[ "$file" =~ domains/system/users/ ]] && continue

        if rg -n '^\s*users\.users\.[a-zA-Z]' "$file" 2>/dev/null; then
            while IFS=: read -r line_num match; do
                lint_error "MIXED_DOMAIN" "HIGH" "$file:$line_num" \
                    "User definition outside domains/system/users/ (CHARTER §3, §14)"
            done < <(rg -n '^\s*users\.users\.[a-zA-Z]' "$file" 2>/dev/null || true)
        fi
    done < <(find "$SEARCH_PATH" -type f -name "*.nix" 2>/dev/null || true)
}

#==========================================================================
# HARD BLOCKER 5: Home domain anti-patterns (CHARTER §14)
#==========================================================================
check_home_domain_antipatterns() {
    echo -e "${BLUE}[5/8]${NC} Checking home domain anti-patterns..."

    # systemd.services in domains/home/ (but NOT in sys.nix - that's system lane)
    if [[ -d "$SEARCH_PATH/domains/home" ]] || [[ "$SEARCH_PATH" =~ domains/home ]]; then
        local search_dir="$SEARCH_PATH"
        [[ -d "$SEARCH_PATH/domains/home" ]] && search_dir="$SEARCH_PATH/domains/home"

        while IFS= read -r file; do
            # Skip sys.nix - it's system lane (CHARTER §6)
            [[ "$file" =~ sys\.nix$ ]] && continue

            if rg -n 'systemd\.services\.' "$file" 2>/dev/null; then
                while IFS=: read -r line_num match; do
                    lint_error "HOME_ANTIPATTERN" "HIGH" "$file:$line_num" \
                        "systemd.services in home domain (CHARTER §14)"
                done < <(rg -n 'systemd\.services\.' "$file" 2>/dev/null || true)
            fi
        done < <(find "$search_dir" -type f -name "*.nix" 2>/dev/null || true)

        # environment.systemPackages in domains/home/ (but NOT in sys.nix)
        while IFS= read -r file; do
            # Skip sys.nix - it's system lane (CHARTER §6)
            [[ "$file" =~ sys\.nix$ ]] && continue

            if rg -n 'environment\.systemPackages' "$file" 2>/dev/null; then
                while IFS=: read -r line_num match; do
                    lint_error "HOME_ANTIPATTERN" "HIGH" "$file:$line_num" \
                        "environment.systemPackages in home domain (CHARTER §14)"
                done < <(rg -n 'environment\.systemPackages' "$file" 2>/dev/null || true)
            fi
        done < <(find "$search_dir" -type f -name "*.nix" 2>/dev/null || true)

        # writeScriptBin in domains/home/ (even in sys.nix - should use parts/)
        while IFS= read -r file; do
            if rg -n 'writeScriptBin' "$file" 2>/dev/null; then
                while IFS=: read -r line_num match; do
                    lint_error "HOME_ANTIPATTERN" "HIGH" "$file:$line_num" \
                        "writeScriptBin in home domain (should use parts/) (CHARTER §14)"
                done < <(rg -n 'writeScriptBin' "$file" 2>/dev/null || true)
            fi
        done < <(find "$search_dir" -type f -name "*.nix" 2>/dev/null || true)
    fi
}

#==========================================================================
# HARD BLOCKER 6: /mnt/ paths in domains/
# CHARTER Section 14
#==========================================================================
check_hardcoded_mnt_paths() {
    echo -e "${BLUE}[6/8]${NC} Checking for hardcoded /mnt/ paths in domains..."

    if [[ -d "$SEARCH_PATH/domains" ]] || [[ "$SEARCH_PATH" =~ domains/ ]]; then
        local search_dir="$SEARCH_PATH"
        [[ -d "$SEARCH_PATH/domains" ]] && search_dir="$SEARCH_PATH/domains"

        while IFS= read -r file; do
            # Skip comments
            if rg -n '"/mnt/' "$file" 2>/dev/null | grep -v '^\s*#' | grep -q .; then
                while IFS=: read -r line_num match; do
                    # Double-check it's not a comment
                    if ! echo "$match" | grep -q '^\s*#'; then
                        lint_error "HARDCODED_PATH" "HIGH" "$file:$line_num" \
                            "Hardcoded /mnt/ path in domains (CHARTER §14)"
                    fi
                done < <(rg -n '"/mnt/' "$file" 2>/dev/null | grep -v '^\s*#' || true)
            fi
        done < <(find "$search_dir" -type f -name "*.nix" 2>/dev/null || true)
    fi
}

#==========================================================================
# HARD BLOCKER 7: Structural file integrity
# CHARTER Section 9
#==========================================================================
check_structural_files() {
    echo -e "${BLUE}[7/8]${NC} Checking structural file integrity..."

    # Verify flake.nix and flake.lock exist
    if [[ -f "$SEARCH_PATH/flake.nix" ]] || [[ "$SEARCH_PATH" == "." ]]; then
        local flake_path="flake.nix"
        [[ "$SEARCH_PATH" != "." ]] && flake_path="$SEARCH_PATH/flake.nix"

        if [[ ! -f "$flake_path" ]]; then
            lint_error "STRUCTURAL_INTEGRITY" "HIGH" "$SEARCH_PATH" \
                "Missing flake.nix (CHARTER §9)"
        fi
    fi
}

#==========================================================================
# HARD BLOCKER 8: Floating container tags
# Security and reproducibility requirement
#==========================================================================
check_floating_container_tags() {
    echo -e "${BLUE}[8/8]${NC} Checking for floating container tags..."

    while IFS= read -r file; do
        # Check for :latest tag
        if rg -n ':latest["\047]' "$file" 2>/dev/null; then
            while IFS=: read -r line_num match; do
                lint_error "FLOATING_TAG" "HIGH" "$file:$line_num" \
                    "Floating container tag :latest (pin to specific version)"
            done < <(rg -n ':latest["\047]' "$file" 2>/dev/null || true)
        fi

        # Check for potentially unpinned tags (image without version)
        # This is a heuristic - look for image = "repo/name" without :version
        if rg -n 'image\s*=\s*"[^"]+/[^":]+"\s*;' "$file" 2>/dev/null; then
            while IFS=: read -r line_num match; do
                # Only report if it's not already caught by :latest check
                if ! echo "$match" | grep -q ':latest'; then
                    lint_error "UNPINNED_TAG" "MED" "$file:$line_num" \
                        "Potentially unpinned container image (consider explicit version tag)"
                fi
            done < <(rg -n 'image\s*=\s*"[^"]+/[^":]+"\s*;' "$file" 2>/dev/null || true)
        fi
    done < <(find "$SEARCH_PATH" -type f -name "*.nix" 2>/dev/null || true)
}

#==========================================================================
# EXECUTION
#==========================================================================

check_options_placement
check_namespace_alignment
check_hm_activation_in_profiles
check_mixed_domain_modules
check_home_domain_antipatterns
check_hardcoded_mnt_paths
check_structural_files
check_floating_container_tags

#==========================================================================
# SUMMARY
#==========================================================================

echo ""
echo "======================================"
echo "Summary"
echo "======================================"

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✅ All CHARTER compliance checks passed${NC}"
    echo ""
    echo "No violations detected."
    exit 0
else
    echo -e "${RED}❌ CHARTER violations detected: $ERRORS${NC}"
    echo ""
    echo "Fix violations above before committing."
    echo "See CHARTER.md sections referenced in each error."
    exit 1
fi
