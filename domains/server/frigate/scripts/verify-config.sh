#!/usr/bin/env bash
# Verify Frigate config.yml structure and required fields
#
# Charter v7.0 Section 19 - Config validation for config-first pattern
#
# Usage:
#   ./scripts/verify-config.sh
#   ./scripts/verify-config.sh /path/to/config.yml

set -euo pipefail

CONFIG_PATH="${1:-domains/server/frigate/config/config.yml}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "❌ Config file not found: $CONFIG_PATH"
  exit 1
fi

echo "🔍 Verifying Frigate configuration: $CONFIG_PATH"
echo ""

# Check for critical YAML structure issues
ERRORS=0

# 1. Check that model block exists and is top-level
if grep -q "^model:" "$CONFIG_PATH"; then
  echo "✅ Model block is top-level (correct)"
else
  echo "❌ Model block is missing or nested (must be top-level, sibling to detectors)"
  ERRORS=$((ERRORS + 1))
fi

# 2. Check for input_dtype field (critical for ONNX)
if grep -q "input_dtype:\s*float" "$CONFIG_PATH"; then
  echo "✅ input_dtype: float field present (prevents uint8→float errors)"
elif grep -q "input_dtype:" "$CONFIG_PATH"; then
  echo "⚠️  input_dtype field present but may not be 'float'"
  DTYPE=$(grep "input_dtype:" "$CONFIG_PATH" | head -1)
  echo "   Found: $DTYPE"
  echo "   Expected: input_dtype: float"
  ERRORS=$((ERRORS + 1))
else
  echo "⚠️  input_dtype field missing (may cause dtype errors with ONNX)"
fi

# 3. Check that detectors block exists
if grep -q "^detectors:" "$CONFIG_PATH"; then
  echo "✅ Detectors block present"
else
  echo "❌ Detectors block missing"
  ERRORS=$((ERRORS + 1))
fi

# 4. Check for at least one camera
if grep -q "^cameras:" "$CONFIG_PATH"; then
  CAMERA_COUNT=$(grep -A 1000 "^cameras:" "$CONFIG_PATH" | grep -c "^\s\{2\}[a-zA-Z_]" || true)
  if [[ $CAMERA_COUNT -gt 0 ]]; then
    echo "✅ Cameras block present ($CAMERA_COUNT camera(s) defined)"
  else
    echo "⚠️  Cameras block present but no cameras defined"
  fi
else
  echo "⚠️  Cameras block missing"
fi

# 5. Check for common secret leaks
if grep -qE "(password|secret|token|key):\s*['\"]?[^'\"\s]{8,}" "$CONFIG_PATH"; then
  echo "⚠️  Potential secret found in config (should use placeholders or references)"
  echo "   Review: $(grep -nE '(password|secret|token|key):' "$CONFIG_PATH" || true)"
fi

# 6. Basic YAML syntax check (if yamllint available)
if command -v yamllint &> /dev/null; then
  if yamllint -d relaxed "$CONFIG_PATH" > /dev/null 2>&1; then
    echo "✅ YAML syntax valid (yamllint)"
  else
    echo "❌ YAML syntax errors detected:"
    yamllint -d relaxed "$CONFIG_PATH" || true
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "ℹ️  yamllint not available (install for syntax validation)"
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "✅ Configuration validation passed"
  exit 0
else
  echo "❌ Configuration validation failed ($ERRORS error(s))"
  exit 1
fi
