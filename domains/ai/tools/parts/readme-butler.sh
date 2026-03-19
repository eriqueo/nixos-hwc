#!/usr/bin/env bash
# domains/ai/tools/parts/readme-butler.sh
#
# Post-commit README changelog updater with context-aware AI
# Runs after git commit, before push - updates changelogs and amends commit
#
# Law 12 Compliance: Automatically updates domain README changelogs when
# commits touch a domain, using AI to generate human-readable descriptions.

set -euo pipefail

OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://localhost:11434}"
NIXOS_DIR="${NIXOS_DIR:-/home/eric/.nixos}"
MODEL="${MODEL:-qwen2.5-coder:3b}"
TIMEOUT="${TIMEOUT:-30}"

# Track modified READMEs for precise git add
MODIFIED_READMES=()

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
log_step() { echo -e "\n${BOLD}$*${NC}"; }

#==============================================================================
# DEPENDENCY CHECKS
#==============================================================================
check_dependencies() {
    local missing=()
    for cmd in curl jq rg awk git; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        return 1
    fi
}

check_ollama() {
    if ! curl -s --connect-timeout 3 "$OLLAMA_ENDPOINT/api/tags" &>/dev/null; then
        log_warn "Ollama not available at $OLLAMA_ENDPOINT"
        return 1
    fi
}

#==============================================================================
# DOMAIN DISCOVERY
#==============================================================================
get_changed_domains() {
    # Get unique directories with changes, filter to those with README.md
    # Only processes leaf domains (nearest parent with README.md)
    # Excludes README.md files themselves to prevent picking up butler's own changes
    git diff HEAD~1 --name-only 2>/dev/null | \
        rg '^domains/' | \
        rg -v 'README\.md$' | \
        while read -r file; do
            local dir
            dir=$(dirname "$file")
            # Find nearest parent with README.md (leaf-first)
            local check="$dir"
            while [[ "$check" != "." && "$check" != "domains" ]]; do
                if [[ -f "$check/README.md" ]]; then
                    echo "$check"
                    break
                fi
                check=$(dirname "$check")
            done
        done | sort -u
}

#==============================================================================
# CONTEXT EXTRACTION
#==============================================================================
get_readme_context() {
    local readme="$1"
    # Get Purpose/Overview section (first 30 lines, stop at Structure)
    head -n 30 "$readme" 2>/dev/null | awk '/^## Structure/{exit} {print}'
}

get_changelog_examples() {
    local readme="$1"
    # Extract last 3 changelog entries as format examples
    awk '/^## Changelog/{found=1; next} found && /^## /{exit} found && /^- /{print}' "$readme" | head -n 3
}

get_domain_diff() {
    local domain="$1"
    # Exclude README.md from diff to avoid seeing butler's own changes
    git diff HEAD~1 --unified=2 -- "$domain" ':(exclude)*.md' 2>/dev/null | head -n 100
}

#==============================================================================
# AI CHANGELOG GENERATION
#==============================================================================

# Few-shot examples for changelog transformation
# Format: commit message | diff summary | good changelog entry
# Note: read returns 1 at EOF, so we suppress with || true
read -r -d '' FEW_SHOT_EXAMPLES << 'EOF' || true
Example 1:
Commit: "feat(frigate): add reolink_cam_2 with RTSP stream configuration"
Diff shows: +reolink_cam_2 = { ffmpeg.inputs = [{ path = "rtsp://...@192.168.0.205" }] }
README says: "4 cameras (3 Cobra PoE + 1 Reolink)"
Good changelog: "Add second Reolink camera, expanding to 5 total"
Why: Transforms technical config into user-facing impact

Example 2:
Commit: "fix(jellyfin): correct CUDA path for hardware transcoding"
Diff shows: -cudaPath = "/usr/lib"; +cudaPath = "/run/opengl-driver"
README says: "Hardware-accelerated transcoding via NVIDIA GPU"
Good changelog: "Fix GPU transcoding by correcting CUDA library path"
Why: Explains the fix's effect, not just what changed

Example 3:
Commit: "refactor(secrets): migrate permissions to group-based access"
Diff shows: -mode = "0400"; +mode = "0440"; +group = "secrets"
README says: "Manages encrypted secrets for system services"
Good changelog: "Enable shared secret access across multiple services"
Why: Describes the capability gained, not the implementation
EOF

generate_changelog_entry() {
    local domain="$1"
    local commit_msg="$2"
    local readme="$domain/README.md"

    local context
    context=$(get_readme_context "$readme")
    local examples
    examples=$(get_changelog_examples "$readme")
    local diff
    diff=$(get_domain_diff "$domain")

    # Skip if no meaningful diff
    [[ -z "$diff" ]] && return 1

    local prompt="You are a changelog writer. Transform git commits into human-readable changelog entries.

CRITICAL RULES:
1. NEVER copy or paraphrase the commit message - that's for developers, not users
2. Describe the IMPACT or CAPABILITY, not the implementation
3. Maximum 12 words, past tense
4. No prefixes (no 'feat:', 'fix:', bullets, or dates)
5. Use terminology from the README context

$FEW_SHOT_EXAMPLES

---

Now generate a changelog entry for this change:

<README_CONTEXT>
$context
</README_CONTEXT>

<COMMIT_MESSAGE_DO_NOT_COPY>
$commit_msg
</COMMIT_MESSAGE_DO_NOT_COPY>

<DIFF>
$diff
</DIFF>

<EXISTING_STYLE>
$examples
</EXISTING_STYLE>

Write ONE changelog line describing the user-facing change:"

    # Call Ollama with timeout - use custom model if available, fallback to base
    local model_to_use="$MODEL"
    if curl -s "$OLLAMA_ENDPOINT/api/tags" 2>/dev/null | jq -e '.models[] | select(.name == "changelog-writer")' &>/dev/null; then
        model_to_use="changelog-writer"
    fi

    local response
    response=$(timeout "$TIMEOUT" curl -s -X POST "$OLLAMA_ENDPOINT/api/generate" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg m "$model_to_use" --arg p "$prompt" \
            '{model: $m, prompt: $p, stream: false, options: {temperature: 0.3, num_predict: 50}}')" 2>/dev/null | \
        jq -r '.response // empty' | tr -d '\n' | xargs) || return 1

    # Validate response
    [[ -z "$response" || "$response" == "null" ]] && return 1

    # Clean up response - remove leading/trailing quotes, bullet points, dates, common prefixes
    response=$(echo "$response" | sed -E '
        s/^[-*•]+\s*//
        s/^[0-9]{4}-[0-9]{2}-[0-9]{2}:\s*//
        s/^"//
        s/"$//
        s/^(feat|fix|refactor|docs|chore|style|test)(\([^)]*\))?:\s*//i
    ')

    echo "$response"
}

#==============================================================================
# CHANGELOG INSERTION (awk-based, robust)
#==============================================================================
append_changelog() {
    local readme="$1"
    local entry="$2"
    local date
    date=$(date +%Y-%m-%d)
    local line="- $date: $entry"

    # Check if ## Changelog section exists
    if ! rg -q '^## Changelog' "$readme"; then
        log_warn "No ## Changelog section in $readme"
        return 1
    fi

    # Use awk for robust insertion (handles special chars better than sed)
    awk -v entry="$line" '
        /^## Changelog$/ { print; print entry; next }
        { print }
    ' "$readme" > "${readme}.tmp" && mv "${readme}.tmp" "$readme"

    MODIFIED_READMES+=("$readme")
}

#==============================================================================
# MAIN
#==============================================================================
main() {
    cd "$NIXOS_DIR"

    # Preflight checks
    check_dependencies || return 1
    check_ollama || {
        log_warn "Skipping changelog generation (Ollama unavailable)"
        return 0
    }

    # Check if there's a commit to process
    if ! git rev-parse HEAD~1 &>/dev/null; then
        log_warn "No previous commit to diff against"
        return 0
    fi

    local commit_msg
    commit_msg=$(git log -1 --pretty=%B 2>/dev/null | head -n 1)

    log_step "📝 README Butler: Processing changelogs..."

    local domains_processed=0
    for domain in $(get_changed_domains); do
        [[ -f "$domain/README.md" ]] || continue

        log_info "Processing: $domain"
        local entry
        if entry=$(generate_changelog_entry "$domain" "$commit_msg"); then
            if append_changelog "$domain/README.md" "$entry"; then
                log_info "  Added: $entry"
                ((++domains_processed))
            fi
        else
            log_warn "  Skipped (no meaningful diff or AI failed)"
        fi
    done

    # Amend commit with ONLY the modified READMEs
    if [[ ${#MODIFIED_READMES[@]} -eq 0 ]]; then
        log_info "No changelog updates needed"
        return 0
    fi

    log_step "📦 Amending commit with ${#MODIFIED_READMES[@]} README update(s)..."

    # Determine if we need to run git as the repo owner
    local repo_owner
    repo_owner=$(stat -c '%U' "$NIXOS_DIR/.git")
    local current_user
    current_user=$(whoami)

    if [[ "$current_user" != "$repo_owner" ]]; then
        # Running as different user (likely root via sudo), use sudo -u
        sudo -u "$repo_owner" git add "${MODIFIED_READMES[@]}"
        sudo -u "$repo_owner" git commit --amend --no-edit
    else
        git add "${MODIFIED_READMES[@]}"
        git commit --amend --no-edit
    fi

    log_info "Commit amended successfully ($domains_processed domain(s) updated)"
}

# Show usage
show_usage() {
    cat <<EOF
${BOLD}README Butler - AI-Powered Changelog Updater${NC}

Post-commit script that updates domain README changelogs with AI-generated
descriptions of what changed. Supports Law 12 compliance automation.

${BOLD}USAGE:${NC}
    readme-butler.sh

${BOLD}ENVIRONMENT:${NC}
    OLLAMA_ENDPOINT      Ollama API URL (default: http://localhost:11434)
    NIXOS_DIR            NixOS config directory (default: /home/eric/.nixos)
    MODEL                AI model to use (default: qwen2.5-coder:3b)
    TIMEOUT              Ollama request timeout in seconds (default: 30)

${BOLD}WORKFLOW:${NC}
    1. Discovers domains changed in HEAD~1..HEAD
    2. For each domain with README.md:
       - Reads README context (Purpose/Overview)
       - Reads git diff for the domain
       - Reads existing changelog entries (format guide)
       - Generates AI changelog entry
       - Appends to ## Changelog section
    3. Amends the current commit with README updates

${BOLD}REQUIREMENTS:${NC}
    - Run after git commit, before git push
    - Ollama running with qwen2.5-coder:3b model
    - Domain READMEs must have ## Changelog section

${BOLD}INTEGRATION:${NC}
    Called by grebuild.sh after git_commit() but before test_configuration()
    to ensure changelog updates are included in the commit.

EOF
}

# Entry point
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    show_usage
    exit 0
fi

main "$@"
