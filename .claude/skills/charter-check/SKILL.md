---
name: Charter Check
description: Fast Charter v6.0 compliance validation for nixos-hwc using targeted searches to detect violations without reading entire codebase
---

# Charter Check Workflow

This skill provides **fast compliance validation** against Charter v6.0 using targeted grep patterns.

## What This Skill Does

Runs automated compliance checks to find:
- ❌ Domain boundary violations
- ❌ Namespace mismatches
- ❌ Missing options.nix files
- ❌ Missing validation sections
- ❌ Lane purity violations
- ❌ Hardcoded values (colors, secrets)

**Token savings**: ~90% - uses grep patterns instead of reading all files.

## Usage

Say: **"Run charter check"** or **"Check charter compliance on [path]"**

Examples:
- "Run charter check"
- "Check charter compliance on domains/home/apps/firefox"
- "Validate my recent changes against charter"

## Full Repository Scan

### 1. Domain Boundary Violations

**HM options in system domain**:
```bash
echo "=== HM Options in System Domain ==="
rg "programs\." domains/system/ --type nix -l | head -10
rg "^[[:space:]]*home\." domains/system/ --type nix -l | head -10
```

**System options in home domain** (excluding sys.nix):
```bash
echo "=== System Options in Home Domain ==="
rg "systemd\.services" domains/home/ --type nix | grep -v sys.nix | head -10
rg "environment\.systemPackages" domains/home/ --type nix | grep -v sys.nix | head -10
```

**HM activation in profiles** (except profiles/home.nix):
```bash
echo "=== HM Activation in Profiles ==="
rg "home-manager\.users" profiles/ --type nix | grep -v home.nix | head -5
```

### 2. Missing options.nix Files

```bash
echo "=== Missing options.nix ==="
find domains/ -type d -mindepth 3 -maxdepth 4 | while read dir; do
  # Check if it's a module (has index.nix)
  if [ -f "$dir/index.nix" ] && [ ! -f "$dir/options.nix" ]; then
    echo "❌ Missing: $dir/options.nix"
  fi
done
```

### 3. Options Defined Outside options.nix

```bash
echo "=== Options Defined in index.nix ==="
find domains/ -name "index.nix" -exec grep -l "options\.hwc\." {} \; | head -10
```

### 4. Namespace Alignment

For each module, verify namespace matches folder:

```bash
echo "=== Potential Namespace Mismatches ==="

# Check domains/home/apps/* for hwc.home.apps.* namespace
find domains/home/apps/*/options.nix 2>/dev/null | while read file; do
  dir=$(dirname "$file")
  name=$(basename "$dir")

  # Expected namespace: hwc.home.apps.<name>
  if ! grep -q "options\.hwc\.home\.apps\.$name" "$file"; then
    echo "❌ $file - Expected hwc.home.apps.$name namespace"
  fi
done
```

### 5. Missing Validation Sections

```bash
echo "=== Missing Validation Sections ==="

# Find modules with enable option but no assertions
find domains/ -name "index.nix" | while read file; do
  if grep -q "mkEnableOption\|enable.*=.*lib\.mkOption" "$file"; then
    if ! grep -q "# VALIDATION\|assertions.*=.*\[" "$file"; then
      echo "⚠️  $file - Has enable option but no VALIDATION section"
    fi
  fi
done
```

### 6. Hardcoded Colors

```bash
echo "=== Hardcoded Colors (Should Use Theme) ==="
rg '#[0-9a-fA-F]{6}' domains/home/apps/ --type nix -n | head -10
```

### 7. Hardcoded Secrets

```bash
echo "=== Potential Hardcoded Secrets ==="
rg 'password.*=.*"[^/].*"' domains/ --type nix | grep -v agenix | head -10
rg 'apikey.*=.*"[^/].*"' domains/ --type nix -i | grep -v agenix | head -10
```

### 8. Lane Purity Violations

```bash
echo "=== Cross-Lane Imports ==="

# Home importing system index.nix
rg 'import.*domains/system/.*/index\.nix' domains/home/ --type nix | head -5

# System importing home index.nix
rg 'import.*domains/home/.*/index\.nix' domains/system/ --type nix | head -5
```

### 9. Circular Import Risks

```bash
echo "=== Potential Circular Imports ==="
# Look for cross-imports between modules
rg 'import.*\.\./\.\./' domains/ --type nix | grep -v "parts\|adapters" | head -10
```

### 10. Profile Structure

```bash
echo "=== Profile Section Headers ==="
for profile in profiles/*.nix; do
  echo "Checking $profile..."
  if ! grep -q "# BASE\|# OPTIONAL" "$profile"; then
    echo "⚠️  Missing BASE/OPTIONAL section headers"
  fi
done
```

## Quick Check Script

Create executable script for fast checks:

```bash
#!/bin/bash
# .claude/skills/charter-check/scripts/quick-check.sh

echo "🔍 Charter v6.0 Compliance Check"
echo "================================"

violations=0

# 1. HM in system domain
echo -e "\n1. HM Options in System Domain"
count=$(rg "programs\.|^[[:space:]]*home\." domains/system/ --type nix -c 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
if [ "$count" -gt 0 ]; then
  echo "❌ Found $count violations"
  violations=$((violations + count))
else
  echo "✅ None found"
fi

# 2. System in home domain (excluding sys.nix)
echo -e "\n2. System Options in Home Domain (excluding sys.nix)"
count=$(rg "systemd\.services|environment\.systemPackages" domains/home/ --type nix 2>/dev/null | grep -v sys.nix | wc -l)
if [ "$count" -gt 0 ]; then
  echo "❌ Found $count violations"
  violations=$((violations + count))
else
  echo "✅ None found"
fi

# 3. Missing options.nix
echo -e "\n3. Missing options.nix Files"
missing=0
find domains/ -type d -mindepth 3 -maxdepth 4 2>/dev/null | while read dir; do
  if [ -f "$dir/index.nix" ] && [ ! -f "$dir/options.nix" ]; then
    echo "❌ $dir/"
    missing=$((missing + 1))
  fi
done
if [ "$missing" -eq 0 ]; then
  echo "✅ All modules have options.nix"
fi

# 4. Hardcoded colors
echo -e "\n4. Hardcoded Colors"
count=$(rg '#[0-9a-fA-F]{6}' domains/home/apps/ --type nix -c 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
if [ "$count" -gt 0 ]; then
  echo "⚠️  Found $count instances (review if they should use theme)"
else
  echo "✅ None found"
fi

# 5. Profile structure
echo -e "\n5. Profile Section Headers"
for profile in profiles/*.nix; do
  if [ ! -f "$profile" ]; then continue; fi
  if ! grep -q "# BASE\|# OPTIONAL" "$profile" 2>/dev/null; then
    echo "⚠️  $profile missing section headers"
  fi
done

echo -e "\n================================"
if [ "$violations" -eq 0 ]; then
  echo "✅ Charter compliance check passed!"
  exit 0
else
  echo "❌ Found $violations violations - review above"
  exit 1
fi
```

## Targeted Module Check

To check a specific module:

```bash
#!/bin/bash
# Usage: check-module.sh domains/home/apps/firefox

MODULE_PATH="$1"
MODULE_NAME=$(basename "$MODULE_PATH")

echo "Checking module: $MODULE_PATH"
echo "=============================="

# 1. Check options.nix exists
if [ ! -f "$MODULE_PATH/options.nix" ]; then
  echo "❌ Missing options.nix"
else
  echo "✅ options.nix exists"
fi

# 2. Check namespace alignment
DOMAIN=$(echo "$MODULE_PATH" | cut -d'/' -f2)
CATEGORY=$(echo "$MODULE_PATH" | cut -d'/' -f3)

EXPECTED_NS="hwc.$DOMAIN.$CATEGORY.$MODULE_NAME"

if [ -f "$MODULE_PATH/options.nix" ]; then
  if grep -q "options\.$EXPECTED_NS" "$MODULE_PATH/options.nix"; then
    echo "✅ Namespace matches folder structure"
  else
    echo "❌ Namespace mismatch - expected: $EXPECTED_NS"
    echo "   Found:"
    grep "options\.hwc\." "$MODULE_PATH/options.nix" | head -3
  fi
fi

# 3. Check index.nix imports options.nix
if [ -f "$MODULE_PATH/index.nix" ]; then
  if grep -q 'imports.*\./options\.nix' "$MODULE_PATH/index.nix"; then
    echo "✅ index.nix imports options.nix"
  else
    echo "❌ index.nix does not import options.nix"
  fi
fi

# 4. Check validation section
if [ -f "$MODULE_PATH/index.nix" ]; then
  if grep -q "mkEnableOption" "$MODULE_PATH/options.nix"; then
    if grep -q "# VALIDATION\|assertions" "$MODULE_PATH/index.nix"; then
      echo "✅ Has validation section"
    else
      echo "⚠️  Has enable option but no validation section"
    fi
  fi
fi

# 5. Check domain boundaries
if [ "$DOMAIN" = "home" ]; then
  if grep -q "systemd\.services\|environment\.systemPackages" "$MODULE_PATH/index.nix" 2>/dev/null; then
    echo "❌ Home module contains system options (should be in sys.nix)"
  else
    echo "✅ No domain boundary violations in index.nix"
  fi
fi

echo "=============================="
```

## Git Pre-Commit Hook Integration

Optional: Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Run charter check on staged .nix files

STAGED_NIX=$(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$')

if [ -n "$STAGED_NIX" ]; then
  echo "Running charter compliance checks on staged files..."

  # Run quick checks
  bash .claude/skills/charter-check/scripts/quick-check.sh

  if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Charter compliance check failed!"
    echo "   Fix violations or use 'git commit --no-verify' to skip"
    exit 1
  fi
fi
```

## Output Format

Results should be presented as:

```
🔍 Charter v6.0 Compliance Check
================================

1. Domain Boundary Violations
   ❌ domains/system/apps/firefox/index.nix:12
      Contains: programs.firefox (HM option in system domain)

   ✅ No system options in home domain

2. Namespace Alignment
   ❌ domains/home/apps/waybar/options.nix
      Expected: hwc.home.apps.waybar.*
      Found: hwc.home.waybar.*

   ✅ All other modules aligned

3. Missing options.nix
   ✅ All modules have options.nix

4. Missing Validation
   ⚠️  domains/home/apps/slack/index.nix
      Has enable option but no VALIDATION section
      (May not need assertions if no dependencies)

================================
Summary: 2 violations, 1 warning
```

## Fix Recommendations

For each violation type, provide fix:

**Domain Violation**:
```
Move domains/system/apps/firefox → domains/home/apps/firefox
Update namespace in options.nix
Update profile imports
```

**Namespace Mismatch**:
```
Update domains/home/apps/waybar/options.nix:
- options.hwc.home.waybar = { ... };
+ options.hwc.home.apps.waybar = { ... };
```

**Missing Validation**:
```
Add to index.nix:
  # VALIDATION
  assertions = [{
    assertion = !cfg.enable || <dependency check>;
    message = "<module> requires <dependency>";
  }];
```

## When to Run

- ✅ Before committing changes
- ✅ After creating new modules
- ✅ During code review
- ✅ Weekly as part of maintenance
- ✅ Before major refactoring

## Remember

**Fast validation is valuable validation!**

Use grep patterns to find issues in seconds, not minutes.
Focus on violations that break builds or violate charter principles.
Warnings are advisory - use judgment on whether to fix.

Charter checks should be **instant feedback**, not lengthy audits!
