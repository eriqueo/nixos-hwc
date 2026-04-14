#!/usr/bin/env bash
# Secret Manager - Unified agenix secret management tool
# Location: workspace/system/secret-manager.sh
# Invoked by: Shell wrapper in domains/home/environment/shell/parts/secret.nix
#
# Features:
#   - Lookup: View secret info (value, locations, runtime status)
#   - Add: Create new encrypted secret with auto-declaration
#   - Edit: Update existing secret value
#   - Validate: Enhanced secrets setup validation

set -euo pipefail

#==============================================================================
# CONFIGURATION
#==============================================================================
readonly NIXOS_DIR="${HOME}/.nixos"
readonly SECRETS_PARTS="${NIXOS_DIR}/domains/secrets/parts"
readonly SECRETS_DECL="${NIXOS_DIR}/domains/secrets/declarations"
readonly AGE_KEY_FILE="/etc/age/keys.txt"
readonly RUNTIME_SECRETS="/run/agenix"

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================
log_info() { echo -e "${GREEN}✅${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $*"; }
log_error() { echo -e "${RED}❌${NC} $*" >&2; }
log_header() { echo -e "\n${BOLD}${BLUE}$*${NC}"; }
log_step() { echo -e "\n${BOLD}$*${NC}"; }

get_age_pubkey() {
  sudo cat "${AGE_KEY_FILE}" | grep "public key:" | awk '{print $4}'
}

validate_secret_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z0-9-]+$ ]]; then
    log_error "Invalid secret name: must be lowercase letters, numbers, and hyphens only"
    return 1
  fi
  return 0
}

find_secret_file() {
  local name="$1"
  find "${SECRETS_PARTS}" -name "${name}.age" 2>/dev/null | head -1
}

get_secret_category() {
  local secret_file="$1"
  # Extract category from path: domains/secrets/parts/<category>/name.age
  basename "$(dirname "$secret_file")"
}

#==============================================================================
# FEATURE: LOOKUP SECRET
#==============================================================================
lookup_secret() {
  log_header "Lookup Secret"

  # Prompt for secret name
  local secret_name
  if [[ $# -gt 0 ]]; then
    secret_name="$1"
  else
    read -rp "Enter secret name: " secret_name
  fi

  if [[ -z "$secret_name" ]]; then
    log_error "Secret name cannot be empty"
    return 1
  fi

  # Find the secret file
  local secret_file
  secret_file=$(find_secret_file "$secret_name")

  if [[ -z "$secret_file" ]]; then
    log_error "Secret not found: $secret_name"
    echo ""
    echo "Available secrets:"
    find "${SECRETS_PARTS}" -name "*.age" -type f | while read -r file; do
      echo "  - $(basename "${file%.age}")"
    done
    return 1
  fi

  local category
  category=$(get_secret_category "$secret_file")

  log_step "Secret Information: $secret_name"
  echo ""

  # File location and category
  echo "📁 File: $secret_file"
  echo "📂 Category: $category"
  echo ""

  # Runtime status
  echo "🔄 Runtime Status:"
  if [[ -f "${RUNTIME_SECRETS}/${secret_name}" ]]; then
    log_info "Decrypted and available at ${RUNTIME_SECRETS}/${secret_name}"
  else
    log_warn "Not currently decrypted in ${RUNTIME_SECRETS}/"
  fi
  echo ""

  # Decrypted value - show by default since this is what people usually want
  echo "🔐 Value:"
  if sudo age -d -i "${AGE_KEY_FILE}" "$secret_file" 2>/dev/null; then
    echo ""
  else
    log_error "Failed to decrypt secret"
    return 1
  fi
}

#==============================================================================
# FEATURE: ADD NEW SECRET
#==============================================================================
add_secret() {
  log_header "Add New Secret"

  # Step 1: Select category
  echo ""
  echo "Select category:"
  PS3="Category: "
  local categories=("services" "infrastructure" "home" "system" "caddy")
  local category=""

  select cat in "${categories[@]}"; do
    if [[ -n "$cat" ]]; then
      category="$cat"
      break
    else
      log_error "Invalid selection"
    fi
  done

  # Step 2: Enter secret name
  echo ""
  local secret_name
  while true; do
    read -rp "Enter secret name (lowercase, hyphens only): " secret_name
    if [[ -z "$secret_name" ]]; then
      log_error "Secret name cannot be empty"
      continue
    fi
    if validate_secret_name "$secret_name"; then
      break
    fi
  done

  # Check if secret already exists
  local existing_file
  existing_file=$(find_secret_file "$secret_name")
  if [[ -n "$existing_file" ]]; then
    log_error "Secret already exists: $existing_file"
    return 1
  fi

  # Step 3: Enter secret value
  echo ""
  local secret_value
  local secret_value_confirm
  while true; do
    read -rsp "Enter secret value (hidden): " secret_value
    echo ""
    if [[ -z "$secret_value" ]]; then
      read -rp "Empty value - are you sure? [y/N] " confirm_empty
      if [[ ! "$confirm_empty" =~ ^[Yy]$ ]]; then
        continue
      fi
    fi
    read -rsp "Confirm secret value (hidden): " secret_value_confirm
    echo ""
    if [[ "$secret_value" == "$secret_value_confirm" ]]; then
      break
    else
      log_error "Values do not match, try again"
    fi
  done

  # Step 4: Encrypt and save
  echo ""
  log_step "Creating encrypted secret..."

  local secret_dir="${SECRETS_PARTS}/${category}"
  local secret_file="${secret_dir}/${secret_name}.age"

  # Ensure category directory exists
  mkdir -p "$secret_dir"

  # Get age public key
  local age_pubkey
  age_pubkey=$(get_age_pubkey)

  # Encrypt secret (use printf to avoid trailing newline)
  if printf '%s' "$secret_value" | age -r "$age_pubkey" > "$secret_file"; then
    log_info "Encrypted secret saved: $secret_file"
  else
    log_error "Failed to encrypt secret"
    return 1
  fi

  # Step 5: Auto-update declaration file
  echo ""
  log_step "Updating declaration file..."

  if add_declaration "$category" "$secret_name"; then
    log_info "Declaration added successfully"
  else
    log_error "Failed to add declaration (but .age file was created)"
    log_warn "You may need to manually add the declaration to ${SECRETS_DECL}/${category}.nix"
    return 1
  fi

  # Step 6: Stage new files for flake visibility, then validate
  echo ""
  local decl_file="${SECRETS_DECL}/${category}.nix"
  log_step "Staging files for flake check..."
  (cd "${NIXOS_DIR}" && git add "$secret_file" "$decl_file")
  log_info "Staged $secret_file and $decl_file"

  log_step "Validating with nix flake check (this takes a moment)..."

  if (cd "${NIXOS_DIR}" && nix flake check); then
    log_info "Nix flake check passed"
  else
    log_error "Nix flake check failed - please review errors above"
    return 1
  fi

  # Step 7: Display next steps
  echo ""
  log_step "Secret Added Successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Reference in any module: config.hwc.secrets.api.\"${secret_name}\""
  echo "     Check existence:         config.hwc.secrets.api ? \"${secret_name}\""
  echo "  2. Rebuild NixOS: sudo nixos-rebuild switch --flake .#\$(hostname)"
  echo ""
}

#==============================================================================
# AUTO-DECLARATION HELPER
#==============================================================================
add_declaration() {
  local category="$1"
  local name="$2"
  local decl_file="${SECRETS_DECL}/${category}.nix"

  if [[ ! -f "$decl_file" ]]; then
    log_error "Declaration file not found: $decl_file"
    return 1
  fi

  # Backup original
  cp "${decl_file}" "${decl_file}.bak"

  # Create declaration snippet (4-space indentation to match existing files)
  local snippet="    ${name} = {
      file = ../parts/${category}/${name}.age;
      mode = \"0440\";
      owner = \"root\";
      group = \"secrets\";
    };"

  # Use awk to insert in alphabetical order within age.secrets block
  # Key: age.secrets opens at 2-space indent, entries at 4-space indent,
  # so only match the 2-space `};` as the block closer (not 4-space entry closers)
  awk -v snippet="$snippet" -v name="$name" '
  BEGIN { inserted = 0; in_secrets = 0 }

  # Enter age.secrets block (2-space indent)
  /^  age\.secrets = \{/ { in_secrets = 1; print; next }

  # Exit age.secrets block — only the 2-space indent closing brace
  /^  \};$/ && in_secrets {
    if (!inserted) {
      print ""
      print snippet
      inserted = 1
    }
    in_secrets = 0
    print
    next
  }

  # Within age.secrets, detect top-level entries (4-space indent)
  in_secrets && /^    [a-z][a-z0-9-]* = / {
    current_name = $0
    sub(/^[[:space:]]+/, "", current_name)
    sub(/ = .*/, "", current_name)

    if (!inserted && name < current_name) {
      print snippet
      print ""
      inserted = 1
    }
  }

  { print }

  END {
    if (!inserted) {
      print "ERROR: Could not find insertion point" > "/dev/stderr"
      exit 1
    }
  }
  ' "${decl_file}.bak" > "${decl_file}"

  # Check if awk succeeded
  if [[ $? -ne 0 ]]; then
    log_error "Failed to insert declaration"
    mv "${decl_file}.bak" "${decl_file}"
    return 1
  fi

  # Validate syntax with nix (quick check)
  if ! (cd "${NIXOS_DIR}" && nix-instantiate --parse "${decl_file}" &>/dev/null); then
    log_error "Declaration syntax error - restoring backup"
    mv "${decl_file}.bak" "${decl_file}"
    return 1
  fi

  # Success - remove backup
  rm "${decl_file}.bak"
  return 0
}

#==============================================================================
# FEATURE: EDIT EXISTING SECRET
#==============================================================================
edit_secret() {
  log_header "Edit Existing Secret"

  # Prompt for secret name
  local secret_name
  if [[ $# -gt 0 ]]; then
    secret_name="$1"
  else
    read -rp "Enter secret name to edit: " secret_name
  fi

  if [[ -z "$secret_name" ]]; then
    log_error "Secret name cannot be empty"
    return 1
  fi

  # Find the secret file
  local secret_file
  secret_file=$(find_secret_file "$secret_name")

  if [[ -z "$secret_file" ]]; then
    log_error "Secret not found: $secret_name"
    return 1
  fi

  echo ""
  log_step "Current secret value:"
  if ! sudo age -d -i "${AGE_KEY_FILE}" "$secret_file" 2>/dev/null; then
    log_error "Failed to decrypt current secret"
    return 1
  fi

  echo ""
  local new_value
  read -rsp "Enter new value (hidden): " new_value
  echo ""

  if [[ -z "$new_value" ]]; then
    read -rp "Empty value - are you sure? [y/N] " confirm_empty
    if [[ ! "$confirm_empty" =~ ^[Yy]$ ]]; then
      log_info "Edit cancelled"
      return 0
    fi
  fi

  # Get age public key
  local age_pubkey
  age_pubkey=$(get_age_pubkey)

  # Re-encrypt secret (use printf to avoid trailing newline)
  if printf '%s' "$new_value" | age -r "$age_pubkey" > "$secret_file"; then
    log_info "Secret updated: $secret_file"
    echo ""
    echo "Next step: sudo nixos-rebuild switch --flake .#\$(hostname)"
  else
    log_error "Failed to re-encrypt secret"
    return 1
  fi
}

#==============================================================================
# FEATURE: VALIDATE SECRETS SETUP
#==============================================================================
validate_secrets() {
  log_header "Validating HWC Secrets Setup"
  echo ""

  local errors=0

  # Check 1: Age key exists
  log_step "1. Age Key Infrastructure"
  if [[ -f "${AGE_KEY_FILE}" ]]; then
    log_info "${AGE_KEY_FILE} exists"
    # Verify it contains a valid age key
    if sudo cat "${AGE_KEY_FILE}" | grep -q "AGE-SECRET-KEY-"; then
      log_info "Valid age secret key found"
    else
      log_error "Age key file exists but does not contain valid key"
      ((errors++))
    fi
  else
    log_error "${AGE_KEY_FILE} NOT FOUND"
    ((errors++))
  fi
  echo ""

  # Check 2: Secrets mount
  log_step "2. Runtime Secrets Mount"
  if mount | grep -q "${RUNTIME_SECRETS}"; then
    log_info "${RUNTIME_SECRETS} is mounted"
  else
    log_warn "${RUNTIME_SECRETS} NOT MOUNTED (may be normal if no secrets declared)"
  fi
  echo ""

  # Check 3: Secret counts by category
  log_step "3. Encrypted Secrets Inventory"
  for category in services infrastructure home system caddy; do
    local count
    count=$(find "${SECRETS_PARTS}/${category}" -name "*.age" 2>/dev/null | wc -l)
    echo "  📊 ${category}: ${count} secrets"
  done
  local total_encrypted
  total_encrypted=$(find "${SECRETS_PARTS}" -name "*.age" 2>/dev/null | wc -l)
  echo "  📊 TOTAL: ${total_encrypted} encrypted secrets"
  echo ""

  # Check 4: Decrypted secrets count
  log_step "4. Decrypted Secrets"
  if [[ -d "${RUNTIME_SECRETS}" ]]; then
    local decrypted_count
    decrypted_count=$(sudo ls "${RUNTIME_SECRETS}/" 2>/dev/null | wc -l)
    echo "  📊 ${decrypted_count} secrets currently decrypted"
  else
    log_warn "Runtime secrets directory does not exist"
  fi
  echo ""

  # Check 5: Declaration consistency
  log_step "5. Declaration Consistency Check"

  # Find all .age files
  local age_files
  age_files=$(find "${SECRETS_PARTS}" -name "*.age" -type f 2>/dev/null)

  local missing_declarations=0
  while IFS= read -r age_file; do
    local filename
    filename=$(basename "$age_file")
    # Extract top-level category (first dir under parts/, handles subdirs like home/scraper/)
    local rel_path="${age_file#${SECRETS_PARTS}/}"
    local category="${rel_path%%/*}"
    local decl_file="${SECRETS_DECL}/${category}.nix"

    # Search for the filename anywhere in secrets domain nix files
    # (handles declarations/*.nix and parts/*.nix with dynamic selection)
    if ! grep -rq "${filename}" "${NIXOS_DIR}/domains/secrets/" --include="*.nix" 2>/dev/null; then
      log_warn "Missing declaration for: ${filename} (${category})"
      ((missing_declarations++))
    fi
  done <<< "$age_files"

  if [[ $missing_declarations -eq 0 ]]; then
    log_info "All .age files have declarations"
  else
    log_warn "${missing_declarations} secrets missing declarations"
  fi
  echo ""

  # Check 6: Permission audit
  log_step "6. Permission Audit"
  local permission_issues=0

  while IFS= read -r age_file; do
    local perms
    perms=$(stat -c "%a" "$age_file" 2>/dev/null)
    if [[ "$perms" != "644" && "$perms" != "640" && "$perms" != "600" ]]; then
      log_warn "Unusual permissions on ${age_file}: ${perms}"
      ((permission_issues++))
    fi
  done <<< "$age_files"

  if [[ $permission_issues -eq 0 ]]; then
    log_info "All .age files have acceptable permissions"
  fi

  # Check if secrets group exists
  if getent group secrets &>/dev/null; then
    log_info "Secrets group exists"
  else
    log_error "Secrets group does NOT exist"
    ((errors++))
  fi
  echo ""

  # Check 7: Encryption validation (optional)
  log_step "7. Encryption Validation"
  read -rp "Test decrypt all secrets? (requires sudo) [y/N] " test_decrypt
  if [[ "$test_decrypt" =~ ^[Yy]$ ]]; then
    local decrypt_failures=0
    while IFS= read -r age_file; do
      if ! sudo age -d -i "${AGE_KEY_FILE}" "$age_file" &>/dev/null; then
        log_error "Failed to decrypt: $age_file"
        ((decrypt_failures++))
      fi
    done <<< "$age_files"

    if [[ $decrypt_failures -eq 0 ]]; then
      log_info "All secrets decrypt successfully"
    else
      log_error "${decrypt_failures} secrets failed to decrypt"
      ((errors++))
    fi
  else
    echo "  - Skipped encryption validation"
  fi
  echo ""

  # Summary
  log_step "Validation Summary"
  if [[ $errors -eq 0 ]]; then
    log_info "All critical checks passed!"
  else
    log_error "${errors} critical issues found"
    return 1
  fi
}

#==============================================================================
# MAIN MENU
#==============================================================================
main_menu() {
  log_header "HWC Secret Management"
  echo "====================="
  echo ""

  PS3="Select an option: "
  options=("Lookup secret" "Add new secret" "Edit existing secret" "Validate secrets setup" "Quit")

  select opt in "${options[@]}"; do
    case "$REPLY" in
      1) lookup_secret; break;;
      2) add_secret; break;;
      3) edit_secret; break;;
      4) validate_secrets; break;;
      5) exit 0;;
      *) log_error "Invalid option"; continue;;
    esac
  done
}

#==============================================================================
# ENTRY POINT
#==============================================================================
# If no args, show menu; otherwise handle specific command
if [[ $# -eq 0 ]]; then
  main_menu
else
  # Handle direct commands: secret lookup, secret add, etc.
  case "$1" in
    lookup|l) shift; lookup_secret "$@";;
    add|a) shift; add_secret "$@";;
    edit|e) shift; edit_secret "$@";;
    validate|v) shift; validate_secrets "$@";;
    help|h|-h|--help)
      echo "HWC Secret Manager"
      echo ""
      echo "Usage: secret [COMMAND]"
      echo ""
      echo "Commands:"
      echo "  lookup, l      Lookup secret information"
      echo "  add, a         Add new encrypted secret"
      echo "  edit, e        Edit existing secret"
      echo "  validate, v    Validate secrets setup"
      echo "  help, h        Show this help"
      echo ""
      echo "If no command is provided, an interactive menu is shown."
      ;;
    *) log_error "Unknown command: $1 (try 'secret help')"; exit 1;;
  esac
fi
