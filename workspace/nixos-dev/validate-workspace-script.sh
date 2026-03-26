#!/usr/bin/env bash
# Validates a workspace script meets promotion requirements
#
# Usage: validate-workspace-script.sh <script-path>
#
# Checks:
# - File exists
# - File is executable
# - Has proper shebang
# - Uses set -euo pipefail (best practice)
# - Has usage documentation
#
# Exit codes:
# - 0: Validation passed
# - 1: Validation failed (ERROR)
# - 2: Validation passed with warnings

set -euo pipefail

SCRIPT_PATH="${1:?Usage: $0 <script-path>}"

echo "Validating: $SCRIPT_PATH"
echo ""

WARNINGS=0
ERRORS=0

# Check exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "❌ ERROR: File not found"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ File exists"
fi

# Check executable
if [[ ! -x "$SCRIPT_PATH" ]]; then
  echo "❌ ERROR: Not executable (chmod +x needed)"
  ERRORS=$((ERRORS + 1))
else
  echo "✓ File is executable"
fi

# Check shebang (if file exists)
if [[ -f "$SCRIPT_PATH" ]]; then
  if ! head -1 "$SCRIPT_PATH" | grep -q '^#!/'; then
    echo "❌ ERROR: Missing shebang (first line should be #!/usr/bin/env bash or similar)"
    ERRORS=$((ERRORS + 1))
  else
    echo "✓ Has shebang: $(head -1 "$SCRIPT_PATH")"
  fi
fi

# Check set -euo pipefail (best practice, not required)
if [[ -f "$SCRIPT_PATH" ]]; then
  if ! grep -q 'set -euo pipefail' "$SCRIPT_PATH"; then
    echo "⚠️  WARNING: Missing 'set -euo pipefail' (best practice for robust scripts)"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "✓ Uses 'set -euo pipefail'"
  fi
fi

# Check has usage/help documentation
if [[ -f "$SCRIPT_PATH" ]]; then
  if ! grep -q -i 'Usage:' "$SCRIPT_PATH"; then
    echo "⚠️  WARNING: No usage documentation found (search for 'Usage:')"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "✓ Has usage documentation"
  fi
fi

echo ""

# Summary
if [[ $ERRORS -gt 0 ]]; then
  echo "❌ Validation FAILED: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo "✓ Validation PASSED with $WARNINGS warning(s)"
  exit 2
else
  echo "✓ Validation PASSED: Script meets all promotion requirements"
  exit 0
fi
