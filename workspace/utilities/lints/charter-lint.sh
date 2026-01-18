#!/usr/bin/env bash
# Charter v10.3 Mechanical Validation Suite
# Runs all Charter law compliance checks

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
cd "$REPO_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VIOLATIONS=0

echo -e "${BLUE}=== Charter v10.3 Mechanical Validation Suite ===${NC}\n"

# Law 1: Safe osConfig access (allowlist-based)
echo -e "${BLUE}[Law 1] Checking osConfig safe access patterns...${NC}"
LAW1_VIOLATIONS=$(rg 'osConfig\.' domains/home --type nix | rg -v 'osConfig\.hwc or \{\}|attrByPath|lib\.mkIf isNixOS|\? hwc|isNixOSHost.*or false|\bor false\b' || true)
if [ -n "$LAW1_VIOLATIONS" ]; then
  echo -e "${RED}✗ Law 1 violations found (unsafe osConfig access):${NC}"
  echo "$LAW1_VIOLATIONS"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}✓ Law 1: All osConfig accesses use safe patterns${NC}"
fi
echo ""

# Law 2: Namespace fidelity (deprecated shortcuts)
echo -e "${BLUE}[Law 2] Checking namespace fidelity...${NC}"
LAW2_VIOLATIONS=$(rg 'hwc\.services\.|hwc\.features\.|hwc\.filesystem\.|hwc\.home\.fonts\.' domains --type nix | grep -v "^[^:]*:#" | grep -v description || true)
if [ -n "$LAW2_VIOLATIONS" ]; then
  echo -e "${RED}✗ Law 2 violations found (namespace shortcuts):${NC}"
  echo "$LAW2_VIOLATIONS"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}✓ Law 2: All namespaces match folder structure${NC}"
fi
echo ""

# Law 3: Path abstraction (hardened)
echo -e "${BLUE}[Law 3] Checking for hardcoded paths...${NC}"
LAW3_VIOLATIONS=$(rg '"/mnt/|"/home/eric/|"/opt/|'"'"'/mnt/|'"'"'/home/eric/|'"'"'/opt/' domains --type nix --glob '!domains/paths/**' --glob '!*.md' --glob '!*example*.nix' --glob '!*.sh' | grep -v '\bor "' || true)
if [ -n "$LAW3_VIOLATIONS" ]; then
  echo -e "${RED}✗ Law 3 violations found (hardcoded paths):${NC}"
  echo "$LAW3_VIOLATIONS"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}✓ Law 3: No hardcoded paths outside domains/paths/${NC}"
fi
echo ""

# Law 4: Permission model
echo -e "${BLUE}[Law 4] Checking permission model...${NC}"
if [ -f "./workspace/utilities/lints/permission-lint.sh" ]; then
  if bash ./workspace/utilities/lints/permission-lint.sh > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Law 4: Permission model compliant${NC}"
  else
    echo -e "${YELLOW}⚠ Law 4: Permission lint warnings (run permission-lint.sh for details)${NC}"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
else
  echo -e "${YELLOW}⚠ Law 4: permission-lint.sh not found, skipping${NC}"
fi
echo ""

# Law 7: sys.nix lane purity
echo -e "${BLUE}[Law 7] Checking sys.nix lane purity...${NC}"
LAW7_VIOLATIONS=$(rg 'import.*sys.nix' domains/home/*/index.nix 2>/dev/null || true)
if [ -n "$LAW7_VIOLATIONS" ]; then
  echo -e "${RED}✗ Law 7 violations found (home importing sys.nix):${NC}"
  echo "$LAW7_VIOLATIONS"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}✓ Law 7: sys.nix lane purity maintained${NC}"
fi
echo ""

# Law 10a: Option declaration purity (options.hwc outside options.nix)
echo -e "${BLUE}[Law 10a] Checking option declaration locations...${NC}"
LAW10A_VIOLATIONS=$(rg 'options\.hwc\.' domains --type nix --glob '!options.nix' --glob '!sys.nix' 2>/dev/null || true)
if [ -n "$LAW10A_VIOLATIONS" ]; then
  echo -e "${RED}✗ Law 10 violations found (options outside options.nix):${NC}"
  echo "$LAW10A_VIOLATIONS"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}✓ Law 10a: All options declared in options.nix${NC}"
fi
echo ""

# Law 10b: mkOption outside options.nix
echo -e "${BLUE}[Law 10b] Checking mkOption usage...${NC}"
LAW10B_VIOLATIONS=$(rg 'mkOption' domains --type nix --glob '!options.nix' --glob '!domains/paths/paths.nix' 2>/dev/null || true)
if [ -n "$LAW10B_VIOLATIONS" ]; then
  echo -e "${RED}✗ Law 10 violations found (mkOption outside options.nix):${NC}"
  echo "$LAW10B_VIOLATIONS"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}✓ Law 10b: mkOption only in options.nix (+ paths primitive)${NC}"
fi
echo ""

# Law 5: Container standard
echo -e "${BLUE}[Law 5] Checking container standard compliance...${NC}"
LAW5_VIOLATIONS=$(rg 'oci-containers\.containers\.[^=]+=' domains/server --glob '!mkContainer' 2>/dev/null || true)
if [ -n "$LAW5_VIOLATIONS" ]; then
  echo -e "${YELLOW}⚠ Law 5 warnings (raw OCI containers without mkContainer):${NC}"
  echo "$LAW5_VIOLATIONS"
  echo -e "${YELLOW}  (Check if these have HWC-EXCEPTION annotations)${NC}"
fi
echo ""

# Law 8: Data retention
echo -e "${BLUE}[Law 8] Checking data retention declarations...${NC}"
LAW8_MISSING=$(rg -L 'retain:|retention:|cleanup.timer' domains 2>/dev/null | head -20 || true)
if [ -n "$LAW8_MISSING" ]; then
  echo -e "${YELLOW}⚠ Law 8 info: Some modules may lack retention declarations${NC}"
  echo -e "${YELLOW}  (This is informational - check these modules):${NC}"
  echo "$LAW8_MISSING"
fi
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ $VIOLATIONS -eq 0 ]; then
  echo -e "${GREEN}✓ All Charter v10.3 mechanical validations passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ Found $VIOLATIONS law violation(s)${NC}"
  echo -e "${YELLOW}Fix violations before committing. See CHARTER.md for guidance.${NC}"
  exit 1
fi
