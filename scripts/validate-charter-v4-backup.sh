#!/usr/bin/env bash
# Charter v4 Compliance Validator
# Checks for common domain separation and structure violations

set -euo pipefail

echo "🔍 Charter v4 Compliance Check"
echo "=============================="

violations=0

# Function to report violations
report_violation() {
    local check_name="$1"
    local details="$2"
    echo "❌ $check_name"
    echo "   $details"
    violations=$((violations + 1))
    echo
}

# Function to report success  
report_success() {
    local check_name="$1"
    echo "✅ $check_name"
}

echo "Checking domain separation violations..."
echo

# Check 1: Hardware scripts in UI (home/)
echo "1. Hardware scripts in UI modules"
if rg -q "writeScriptBin|writeShellScript" domains/home/ 2>/dev/null; then
    report_violation "Hardware scripts in home/" "$(rg -l "writeScriptBin|writeShellScript" domains/home/ | sed 's/^/     /')"
else
    report_success "No hardware scripts in home/"
fi

# Check 2: Hardware config in services
echo "2. Hardware configuration in services"
if rg -q "hardware\." domains/services/ 2>/dev/null; then
    report_violation "Hardware config in services/" "$(rg -l "hardware\." domains/services/ | sed 's/^/     /')"
else
    report_success "No hardware config in services/"
fi

# Check 3: System services in home
echo "3. System services in home modules"
if rg -q "systemd\.services" domains/home/ 2>/dev/null; then
    report_violation "System services in home/" "$(rg -l "systemd\.services" domains/home/ | sed 's/^/     /')"
else
    report_success "No system services in home/"
fi

# Check 4: Hardcoded paths
echo "4. Hardcoded paths instead of hwc.paths.*"
if rg -q "/mnt/|/opt/|/var/lib/" domains/ --exclude="*.md" 2>/dev/null; then
    report_violation "Hardcoded paths found" "$(rg -l "/mnt/|/opt/|/var/lib/" domains/ --exclude="*.md" | sed 's/^/     /')"
else
    report_success "No hardcoded paths found"
fi

# Check 5: Module headers compliance
echo "5. Module headers (Charter v4 format)"
missing_headers=()
while IFS= read -r file; do
    if ! grep -q "# DEPENDENCIES (Upstream):" "$file" 2>/dev/null; then
        missing_headers+=("$file")
    fi
done < <(find domains/ -name "*.nix" -not -path "*/.*")

if [ ${#missing_headers[@]} -gt 0 ]; then
    report_violation "Missing Charter v4 headers" "$(printf '%s\n' "${missing_headers[@]}" | sed 's/^/     /')"
else
    report_success "All modules have proper headers"
fi

# Check 6: Section headers
echo "6. Standard section headers"
missing_sections=()
while IFS= read -r file; do
    if ! grep -q "#============================================================================" "$file" 2>/dev/null; then
        missing_sections+=("$file")
    fi
done < <(find domains/ -name "*.nix" -not -path "*/.*")

if [ ${#missing_sections[@]} -gt 0 ]; then
    report_violation "Missing section headers" "$(printf '%s\n' "${missing_sections[@]}" | head -10 | sed 's/^/     /')"
    if [ ${#missing_sections[@]} -gt 10 ]; then
        echo "     ... and $((${#missing_sections[@]} - 10)) more files"
    fi
else
    report_success "All modules have section headers"
fi

# Check 7: Naming conventions
echo "7. File naming conventions (kebab-case)"
bad_names=()
while IFS= read -r file; do
    filename=$(basename "$file" .nix)
    if [[ "$filename" =~ [A-Z_] ]]; then
        bad_names+=("$file")
    fi
done < <(find domains/ -name "*.nix" -not -path "*/.*")

if [ ${#bad_names[@]} -gt 0 ]; then
    report_violation "Non-kebab-case filenames" "$(printf '%s\n' "${bad_names[@]}" | sed 's/^/     /')"
else
    report_success "All files use kebab-case naming"
fi

# Summary
echo "=============================="
if [ $violations -eq 0 ]; then
    echo "🎉 Charter v4 compliant! No violations found."
    exit 0
else
    echo "⚠️  Found $violations violation categories."
    echo "Run specific fixes to address these issues."
    exit 1
fi