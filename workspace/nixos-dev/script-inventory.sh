#!/usr/bin/env bash
# script-inventory.sh - Comprehensive script inventory and analysis tool
# Finds all scripts (.sh, .py), functions (in .nix files), and analyzes organization

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="${HWC_NIXOS_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
readonly OUTPUT_DIR="${1:-$REPO_ROOT/.script-inventory}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Create output directory
mkdir -p "$OUTPUT_DIR"

log_info "Scanning repository: $REPO_ROOT"
log_info "Output directory: $OUTPUT_DIR"
echo ""

#==============================================================================
# 1. FIND ALL SHELL SCRIPTS
#==============================================================================

log_info "Finding all shell scripts (.sh)..."
find "$REPO_ROOT" -type f -name "*.sh" \
  ! -path "*/.git/*" \
  ! -path "*/node_modules/*" \
  ! -path "*/.direnv/*" \
  > "$OUTPUT_DIR/shell-scripts.txt"

SHELL_COUNT=$(wc -l < "$OUTPUT_DIR/shell-scripts.txt")
log_success "Found $SHELL_COUNT shell scripts"

#==============================================================================
# 2. FIND ALL PYTHON SCRIPTS
#==============================================================================

log_info "Finding all Python scripts (.py)..."
find "$REPO_ROOT" -type f -name "*.py" \
  ! -path "*/.git/*" \
  ! -path "*/node_modules/*" \
  ! -path "*/.direnv/*" \
  ! -path "*/__pycache__/*" \
  ! -name "__init__.py" \
  > "$OUTPUT_DIR/python-scripts.txt"

PYTHON_COUNT=$(wc -l < "$OUTPUT_DIR/python-scripts.txt")
log_success "Found $PYTHON_COUNT Python scripts"

#==============================================================================
# 3. FIND NIX-DEFINED SCRIPTS (writeShellApplication)
#==============================================================================

log_info "Finding Nix-defined scripts (writeShellApplication)..."
grep -r "writeShellApplication" "$REPO_ROOT" \
  --include="*.nix" \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  -l | sort -u > "$OUTPUT_DIR/nix-scripts.txt" || true

NIX_SCRIPT_COUNT=$(wc -l < "$OUTPUT_DIR/nix-scripts.txt")
log_success "Found $NIX_SCRIPT_COUNT Nix script definitions"

#==============================================================================
# 4. FIND SHELL FUNCTIONS (in .nix files)
#==============================================================================

log_info "Finding shell functions defined in Nix files..."
{
  # Find function definitions in initContent/initExtra
  grep -r "initContent\|initExtra" "$REPO_ROOT" \
    --include="*.nix" \
    --exclude-dir=.git \
    -A 20 | \
    grep -E "^\s*[a-zA-Z_][a-zA-Z0-9_-]*\(\)" || true
} > "$OUTPUT_DIR/nix-functions-raw.txt"

# Extract unique function names
grep -oE "[a-zA-Z_][a-zA-Z0-9_-]*\(\)" "$OUTPUT_DIR/nix-functions-raw.txt" | \
  sed 's/()$//' | \
  sort -u > "$OUTPUT_DIR/nix-functions.txt" || true

FUNCTION_COUNT=$(wc -l < "$OUTPUT_DIR/nix-functions.txt")
log_success "Found $FUNCTION_COUNT shell functions in Nix files"

#==============================================================================
# 5. FIND ALIASES
#==============================================================================

log_info "Finding shell aliases..."
{
  # Find in options.nix
  grep -r "shellAliases\|aliases =" "$REPO_ROOT" \
    --include="*.nix" \
    --exclude-dir=.git \
    -A 50 | \
    grep -E '^\s*"[^"]+"\s*=' || true
} > "$OUTPUT_DIR/aliases-raw.txt"

# Extract alias names
grep -oE '"[^"]+"' "$OUTPUT_DIR/aliases-raw.txt" | \
  tr -d '"' | \
  sort -u > "$OUTPUT_DIR/aliases.txt" || true

ALIAS_COUNT=$(wc -l < "$OUTPUT_DIR/aliases.txt")
log_success "Found $ALIAS_COUNT shell aliases"

#==============================================================================
# 6. ANALYZE SCRIPT LOCATIONS
#==============================================================================

log_info "Analyzing script locations..."

cat > "$OUTPUT_DIR/location-analysis.txt" << 'EOF'
# Script Location Analysis

## Shell Scripts by Directory
EOF

# Count scripts by directory
while IFS= read -r script; do
  dirname "$script"
done < "$OUTPUT_DIR/shell-scripts.txt" | \
  sort | uniq -c | sort -rn >> "$OUTPUT_DIR/location-analysis.txt"

cat >> "$OUTPUT_DIR/location-analysis.txt" << 'EOF'

## Python Scripts by Directory
EOF

while IFS= read -r script; do
  dirname "$script"
done < "$OUTPUT_DIR/python-scripts.txt" | \
  sort | uniq -c | sort -rn >> "$OUTPUT_DIR/location-analysis.txt"

#==============================================================================
# 7. IDENTIFY EXECUTABLE SCRIPTS
#==============================================================================

log_info "Checking which scripts are executable..."

{
  echo "# Executable Shell Scripts"
  while IFS= read -r script; do
    if [[ -x "$script" ]]; then
      echo "$script"
    fi
  done < "$OUTPUT_DIR/shell-scripts.txt"
} > "$OUTPUT_DIR/executable-shell.txt"

{
  echo "# Executable Python Scripts"
  while IFS= read -r script; do
    if [[ -x "$script" ]]; then
      echo "$script"
    fi
  done < "$OUTPUT_DIR/python-scripts.txt"
} > "$OUTPUT_DIR/executable-python.txt"

EXEC_SHELL=$(grep -v "^#" "$OUTPUT_DIR/executable-shell.txt" | wc -l)
EXEC_PYTHON=$(grep -v "^#" "$OUTPUT_DIR/executable-python.txt" | wc -l)
log_success "Found $EXEC_SHELL executable shell scripts, $EXEC_PYTHON executable Python scripts"

#==============================================================================
# 8. FIND SCRIPTS WITH SHEBANGS
#==============================================================================

log_info "Checking for proper shebangs..."

{
  echo "# Scripts with #!/usr/bin/env bash"
  while IFS= read -r script; do
    if head -1 "$script" | grep -q "#!/usr/bin/env bash"; then
      echo "$script"
    fi
  done < "$OUTPUT_DIR/shell-scripts.txt"
} > "$OUTPUT_DIR/shebang-env-bash.txt"

{
  echo "# Scripts with #!/bin/bash (should use /usr/bin/env)"
  while IFS= read -r script; do
    if head -1 "$script" | grep -q "#!/bin/bash"; then
      echo "$script"
    fi
  done < "$OUTPUT_DIR/shell-scripts.txt"
} > "$OUTPUT_DIR/shebang-bin-bash.txt"

{
  echo "# Python scripts with #!/usr/bin/env python3"
  while IFS= read -r script; do
    if head -1 "$script" | grep -q "#!/usr/bin/env python3"; then
      echo "$script"
    fi
  done < "$OUTPUT_DIR/python-scripts.txt"
} > "$OUTPUT_DIR/shebang-env-python.txt"

#==============================================================================
# 9. GENERATE SUMMARY REPORT
#==============================================================================

log_info "Generating summary report..."

cat > "$OUTPUT_DIR/SUMMARY.md" << EOF
# HWC NixOS Script Inventory

**Generated:** $(date)
**Repository:** $REPO_ROOT

---

## Overview

| Category | Count |
|----------|-------|
| Shell Scripts (.sh) | $SHELL_COUNT |
| Python Scripts (.py) | $PYTHON_COUNT |
| Nix Script Definitions | $NIX_SCRIPT_COUNT |
| Shell Functions (in Nix) | $FUNCTION_COUNT |
| Shell Aliases | $ALIAS_COUNT |
| **Total Scripts** | **$((SHELL_COUNT + PYTHON_COUNT))** |

---

## Executable Scripts

| Type | Executable | Non-Executable |
|------|------------|----------------|
| Shell | $EXEC_SHELL | $((SHELL_COUNT - EXEC_SHELL)) |
| Python | $EXEC_PYTHON | $((PYTHON_COUNT - EXEC_PYTHON)) |

---

## Script Organization

### Top Directories (Shell Scripts)

\`\`\`
$(head -20 "$OUTPUT_DIR/location-analysis.txt" | tail -n +3 | head -10)
\`\`\`

### Top Directories (Python Scripts)

\`\`\`
$(tail -n +$(grep -n "Python Scripts by Directory" "$OUTPUT_DIR/location-analysis.txt" | cut -d: -f1) "$OUTPUT_DIR/location-analysis.txt" | head -10)
\`\`\`

---

## Nix-Defined Scripts

These scripts are defined using \`writeShellApplication\` in Nix files:

\`\`\`
$(cat "$OUTPUT_DIR/nix-scripts.txt" | sed "s|$REPO_ROOT/||g")
\`\`\`

---

## Shell Functions

Functions defined in Nix \`initContent\`/\`initExtra\`:

\`\`\`
$(cat "$OUTPUT_DIR/nix-functions.txt")
\`\`\`

---

## Shell Aliases

Defined aliases (first 30):

\`\`\`
$(head -30 "$OUTPUT_DIR/aliases.txt")
\`\`\`

$(if [[ $ALIAS_COUNT -gt 30 ]]; then echo "... and $((ALIAS_COUNT - 30)) more"; fi)

---

## Detailed Files

- **All shell scripts:** \`shell-scripts.txt\`
- **All Python scripts:** \`python-scripts.txt\`
- **Nix script definitions:** \`nix-scripts.txt\`
- **Shell functions:** \`nix-functions.txt\`
- **Aliases:** \`aliases.txt\`
- **Location analysis:** \`location-analysis.txt\`
- **Executable scripts:** \`executable-shell.txt\`, \`executable-python.txt\`

---

## Recommendations

### Script Organization (Updated 2025-12-10)

**Current Structure** (Purpose-Driven):

1. **Organized by trigger/purpose** (not arbitrary categories)
   - workspace/nixos/ - NixOS development tools
   - workspace/monitoring/ - System health checks
   - workspace/hooks/ - Event-driven automation
   - workspace/diagnostics/ - Troubleshooting tools
   - workspace/setup/ - One-time deployment
   - workspace/bible/ - Domain-specific automation
   - workspace/media/ - Media management
   - workspace/projects/ - Standalone projects

2. **Naming standards**
   - User-facing commands: via Nix wrappers (grebuild, charter-lint, etc.)
   - Implementation scripts: kebab-case with .sh/.py extensions
   - Three-tier architecture (Nix → workspace → domain)

3. **No duplicates**
   - User commands are Nix derivations wrapping workspace scripts
   - Scripts can be edited without rebuilding NixOS
   - Single canonical location per script

### Current Structure Benefits

\`\`\`
workspace/
├── nixos/         # Clear: NixOS config development
├── monitoring/    # Clear: System health monitoring
├── hooks/         # Clear: Triggered by events
├── diagnostics/   # Clear: Troubleshooting
├── setup/         # Clear: One-time deployment
├── bible/         # Clear: Domain-specific
├── media/         # Clear: Media tools
└── projects/      # Clear: Standalone projects
\`\`\`

vs. old ambiguous structure:
- development/ - development of what?
- automation/ - automated how?
- utilities/ - utility for what?

See workspace/README.md for full documentation.

EOF

log_success "Summary report generated: $OUTPUT_DIR/SUMMARY.md"

#==============================================================================
# 10. DISPLAY SUMMARY
#==============================================================================

echo ""
echo -e "${BOLD}${CYAN}=== Script Inventory Summary ===${NC}"
echo ""
echo -e "${BOLD}Total Scripts:${NC}"
echo -e "  Shell scripts:        ${GREEN}$SHELL_COUNT${NC}"
echo -e "  Python scripts:       ${GREEN}$PYTHON_COUNT${NC}"
echo -e "  Nix script defs:      ${GREEN}$NIX_SCRIPT_COUNT${NC}"
echo -e "  Shell functions:      ${GREEN}$FUNCTION_COUNT${NC}"
echo -e "  Shell aliases:        ${GREEN}$ALIAS_COUNT${NC}"
echo ""
echo -e "${BOLD}Executable:${NC}"
echo -e "  Shell:                ${GREEN}$EXEC_SHELL${NC} / $SHELL_COUNT"
echo -e "  Python:               ${GREEN}$EXEC_PYTHON${NC} / $PYTHON_COUNT"
echo ""
echo -e "${BOLD}Output Location:${NC}"
echo -e "  ${CYAN}$OUTPUT_DIR/${NC}"
echo ""
echo -e "${BOLD}Key Files:${NC}"
echo -e "  📄 ${CYAN}SUMMARY.md${NC}           - Full report with recommendations"
echo -e "  📄 ${CYAN}shell-scripts.txt${NC}    - All .sh files"
echo -e "  📄 ${CYAN}python-scripts.txt${NC}   - All .py files"
echo -e "  📄 ${CYAN}nix-scripts.txt${NC}      - Nix script definitions"
echo -e "  📄 ${CYAN}nix-functions.txt${NC}    - Shell functions in Nix"
echo -e "  📄 ${CYAN}aliases.txt${NC}          - All defined aliases"
echo ""
echo -e "${GREEN}✓ Inventory complete!${NC}"
echo ""
echo -e "View summary: ${CYAN}cat $OUTPUT_DIR/SUMMARY.md${NC}"
echo -e "Or open in editor: ${CYAN}micro $OUTPUT_DIR/SUMMARY.md${NC}"
