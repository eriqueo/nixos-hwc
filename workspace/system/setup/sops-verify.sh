#!/usr/bin/env bash

# SOPS Verification and Testing Script
# This script provides comprehensive testing and troubleshooting
# tools for SOPS secrets management system.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$NIXOS_DIR/secrets"
SOPS_CONFIG="$NIXOS_DIR/.sops.yaml"
AGE_KEY_FILE="/etc/sops/age/keys.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $1"
}

# Print section header
print_section() {
    echo ""
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}================================${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect current host
detect_host() {
    local hostname=$(hostname)
    case "$hostname" in
        "homeserver")
            echo "server"
            ;;
        "heartwood-laptop")
            echo "laptop"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check system requirements
check_system_requirements() {
    print_section "System Requirements Check"
    
    local all_good=true
    
    # Check required commands
    local required_commands=("sops" "age" "ssh-to-age")
    for cmd in "${required_commands[@]}"; do
        if command_exists "$cmd"; then
            log_success "$cmd is installed"
        else
            log_error "$cmd is not installed"
            all_good=false
        fi
    done
    
    # Check NixOS SOPS module
    if systemctl list-unit-files | grep -q "sops-install-secrets.service"; then
        log_success "SOPS NixOS service is available"
    else
        log_error "SOPS NixOS service not found"
        log_error "Make sure sops-nix module is properly imported in flake.nix"
        all_good=false
    fi
    
    if [[ "$all_good" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Check SOPS configuration
check_sops_configuration() {
    print_section "SOPS Configuration Check"
    
    local all_good=true
    
    # Check .sops.yaml exists
    if [[ -f "$SOPS_CONFIG" ]]; then
        log_success "SOPS configuration file found: $SOPS_CONFIG"
        
        # Validate YAML syntax
        if command_exists "yq"; then
            if yq eval '.' "$SOPS_CONFIG" >/dev/null 2>&1; then
                log_success "SOPS configuration syntax is valid"
            else
                log_error "SOPS configuration has invalid YAML syntax"
                all_good=false
            fi
        fi
        
        # Show configuration summary
        log_debug "Configuration summary:"
        if command_exists "yq"; then
            echo "  Age keys configured: $(yq eval '.keys | length' "$SOPS_CONFIG" 2>/dev/null || echo 'unknown')"
            echo "  Creation rules: $(yq eval '.creation_rules | length' "$SOPS_CONFIG" 2>/dev/null || echo 'unknown')"
        else
            echo "  (Install yq for detailed analysis)"
        fi
    else
        log_error "SOPS configuration file not found: $SOPS_CONFIG"
        all_good=false
    fi
    
    if [[ "$all_good" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Check age key deployment
check_age_key_deployment() {
    print_section "Age Key Deployment Check"
    
    local all_good=true
    local host_type=$(detect_host)
    
    # Check age key file exists
    if [[ -f "$AGE_KEY_FILE" ]]; then
        log_success "Age key file found: $AGE_KEY_FILE"
        
        # Check permissions
        local perms=$(stat -c "%a" "$AGE_KEY_FILE" 2>/dev/null || echo "unknown")
        if [[ "$perms" == "600" ]]; then
            log_success "Age key file has correct permissions (600)"
        else
            log_error "Age key file has incorrect permissions: $perms (should be 600)"
            all_good=false
        fi
        
        # Check ownership
        local owner=$(stat -c "%U:%G" "$AGE_KEY_FILE" 2>/dev/null || echo "unknown")
        if [[ "$owner" == "root:root" ]]; then
            log_success "Age key file has correct ownership (root:root)"
        else
            log_error "Age key file has incorrect ownership: $owner (should be root:root)"
            all_good=false
        fi
        
        # Check key format
        if grep -q "^AGE-SECRET-KEY-" "$AGE_KEY_FILE"; then
            log_success "Age key file has valid format"
        else
            log_error "Age key file has invalid format"
            all_good=false
        fi
        
        # Show key info
        if command_exists "age-keygen"; then
            local public_key=$(age-keygen -y < "$AGE_KEY_FILE" 2>/dev/null || echo "error")
            if [[ "$public_key" != "error" ]]; then
                log_debug "Public key: $public_key"
            fi
        fi
        
    else
        log_error "Age key file not found: $AGE_KEY_FILE"
        log_error "Run 'sudo /etc/nixos/scripts/deploy-age-keys.sh' to deploy keys"
        all_good=false
    fi
    
    # Check host-specific key file in repository
    local repo_key_file="$SECRETS_DIR/keys/${host_type}.txt"
    if [[ -f "$repo_key_file" ]]; then
        log_success "Repository key file found for $host_type host: $repo_key_file"
    else
        log_warning "Repository key file not found: $repo_key_file"
        if [[ "$host_type" == "unknown" ]]; then
            log_info "Unknown host type - cannot verify repository key"
        fi
    fi
    
    if [[ "$all_good" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Check secrets files
check_secrets_files() {
    print_section "Secrets Files Check"
    
    local all_good=true
    local secrets_found=false
    
    # Find all encrypted YAML files
    while IFS= read -r -d '' file; do
        secrets_found=true
        local filename=$(basename "$file")
        
        log_info "Checking secret file: $filename"
        
        # Check if file is encrypted
        if grep -q "sops:" "$file" && grep -q "enc:" "$file"; then
            log_success "  File is properly encrypted"
            
            # Try to decrypt (requires proper key)
            if sops -d "$file" >/dev/null 2>&1; then
                log_success "  File can be decrypted successfully"
            else
                log_warning "  File cannot be decrypted (may be normal if encrypted for different host)"
                log_debug "    Error: $(sops -d "$file" 2>&1 | head -1 || true)"
            fi
        else
            log_error "  File does not appear to be SOPS encrypted"
            all_good=false
        fi
        
    done < <(find "$SECRETS_DIR" -name "*.yaml" -type f -print0 2>/dev/null || true)
    
    if [[ "$secrets_found" == false ]]; then
        log_warning "No encrypted secret files found in $SECRETS_DIR"
    fi
    
    if [[ "$all_good" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Check NixOS integration
check_nixos_integration() {
    print_section "NixOS Integration Check"
    
    local all_good=true
    
    # Check if sops-install-secrets service exists
    if systemctl list-unit-files | grep -q "sops-install-secrets.service"; then
        log_success "SOPS install secrets service is available"
        
        # Check service status
        local status=$(systemctl is-active sops-install-secrets.service 2>/dev/null || echo "unknown")
        case "$status" in
            "active")
                log_success "SOPS install secrets service is active"
                ;;
            "inactive")
                log_info "SOPS install secrets service is inactive (normal)"
                ;;
            "failed")
                log_error "SOPS install secrets service has failed"
                log_debug "Service logs:"
                systemctl status sops-install-secrets.service --no-pager -l | tail -5 | sed 's/^/    /'
                all_good=false
                ;;
            *)
                log_warning "SOPS install secrets service status: $status"
                ;;
        esac
    else
        log_error "SOPS install secrets service not found"
        all_good=false
    fi
    
    # Check for SOPS secrets in /run/secrets
    if [[ -d "/run/secrets" ]]; then
        local secret_count=$(find /run/secrets -type f 2>/dev/null | wc -l)
        if [[ "$secret_count" -gt 0 ]]; then
            log_success "Found $secret_count deployed secrets in /run/secrets/"
            log_debug "Deployed secrets:"
            find /run/secrets -type f -exec basename {} \; 2>/dev/null | sed 's/^/    /' || true
        else
            log_warning "No secrets found in /run/secrets/ (may be normal if not activated)"
        fi
    else
        log_warning "/run/secrets directory not found"
    fi
    
    if [[ "$all_good" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Test secret decryption
test_secret_decryption() {
    print_section "Secret Decryption Test"
    
    local test_passed=false
    
    # Find test files to decrypt
    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$SECRETS_DIR" -name "*.yaml" -type f -print0 2>/dev/null || true)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warning "No secret files found for testing"
        return 1
    fi
    
    # Test each file
    for file in "${test_files[@]}"; do
        local filename=$(basename "$file")
        log_info "Testing decryption of: $filename"
        
        if sops -d "$file" >/dev/null 2>&1; then
            log_success "  Successfully decrypted $filename"
            test_passed=true
            
            # Show a sample of the decrypted content (safely)
            log_debug "  Content preview:"
            sops -d "$file" 2>/dev/null | head -3 | sed 's/^/    /' || true
            echo "    ... (truncated)"
            
        else
            log_warning "  Failed to decrypt $filename"
            log_debug "    Error: $(sops -d "$file" 2>&1 | head -1 || true)"
        fi
    done
    
    if [[ "$test_passed" == true ]]; then
        log_success "At least one secret file was successfully decrypted"
        return 0
    else
        log_error "Could not decrypt any secret files"
        return 1
    fi
}

# Generate diagnostic report
generate_diagnostic_report() {
    print_section "Diagnostic Report"
    
    echo "System Information:"
    echo "  Hostname: $(hostname)"
    echo "  Host Type: $(detect_host)"
    echo "  Current User: $(whoami)"
    echo "  Date: $(date)"
    echo ""
    
    echo "SOPS Environment:"
    echo "  SOPS Version: $(sops --version 2>/dev/null || echo 'not found')"
    echo "  Age Version: $(age --version 2>/dev/null | head -1 || echo 'not found')"
    echo "  Age Key File: $AGE_KEY_FILE"
    echo "  Age Key Exists: $(test -f "$AGE_KEY_FILE" && echo 'yes' || echo 'no')"
    echo "  SOPS Config: $SOPS_CONFIG"
    echo "  SOPS Config Exists: $(test -f "$SOPS_CONFIG" && echo 'yes' || echo 'no')"
    echo ""
    
    echo "NixOS Integration:"
    echo "  SOPS Service Status: $(systemctl is-active sops-install-secrets.service 2>/dev/null || echo 'unknown')"
    echo "  Secrets Directory: /run/secrets"
    echo "  Deployed Secrets: $(find /run/secrets -type f 2>/dev/null | wc -l || echo '0')"
    echo ""
    
    echo "Secret Files:"
    find "$SECRETS_DIR" -name "*.yaml" -type f 2>/dev/null | while read -r file; do
        local filename=$(basename "$file")
        echo "  $filename: $(test -f "$file" && echo 'exists' || echo 'missing')"
    done || echo "  No secret files found"
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "SOPS verification and testing script"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  --quick             Quick check (skip detailed tests)"
    echo "  --decrypt-only      Only test secret decryption"
    echo "  --report            Generate diagnostic report"
    echo "  --fix-permissions   Fix age key file permissions"
    echo ""
    echo "Exit codes:"
    echo "  0 - All checks passed"
    echo "  1 - Some checks failed"
    echo "  2 - Critical error"
}

# Fix permissions
fix_permissions() {
    print_section "Fixing Age Key Permissions"
    
    if [[ $EUID -ne 0 ]]; then
        log_error "Permission fix requires root access (use sudo)"
        return 1
    fi
    
    if [[ -f "$AGE_KEY_FILE" ]]; then
        log_info "Fixing permissions for: $AGE_KEY_FILE"
        chown root:root "$AGE_KEY_FILE"
        chmod 600 "$AGE_KEY_FILE"
        log_success "Permissions fixed"
        return 0
    else
        log_error "Age key file not found: $AGE_KEY_FILE"
        return 1
    fi
}

# Main execution
main() {
    local quick_mode=false
    local decrypt_only=false
    local report_only=false
    local fix_perms=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --quick)
                quick_mode=true
                shift
                ;;
            --decrypt-only)
                decrypt_only=true
                shift
                ;;
            --report)
                report_only=true
                shift
                ;;
            --fix-permissions)
                fix_perms=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo -e "${CYAN}SOPS Verification and Testing Script${NC}"
    echo -e "${CYAN}===================================${NC}"
    
    # Handle special modes
    if [[ "$fix_perms" == true ]]; then
        fix_permissions
        exit $?
    fi
    
    if [[ "$report_only" == true ]]; then
        generate_diagnostic_report
        exit 0
    fi
    
    if [[ "$decrypt_only" == true ]]; then
        test_secret_decryption
        exit $?
    fi
    
    # Run checks
    local overall_status=0
    
    # System requirements check
    if ! check_system_requirements; then
        overall_status=1
    fi
    
    # SOPS configuration check
    if ! check_sops_configuration; then
        overall_status=1
    fi
    
    # Age key deployment check
    if ! check_age_key_deployment; then
        overall_status=1
    fi
    
    # Skip detailed checks in quick mode
    if [[ "$quick_mode" == false ]]; then
        # Secrets files check
        if ! check_secrets_files; then
            overall_status=1
        fi
        
        # NixOS integration check
        if ! check_nixos_integration; then
            overall_status=1
        fi
        
        # Secret decryption test
        if ! test_secret_decryption; then
            overall_status=1
        fi
    fi
    
    # Summary
    print_section "Summary"
    
    if [[ $overall_status -eq 0 ]]; then
        log_success "All SOPS checks passed successfully!"
        log_info "Your SOPS secrets management system is properly configured."
    else
        log_error "Some SOPS checks failed."
        log_info "Review the errors above and fix any issues."
        log_info "Common fixes:"
        log_info "  - Run: sudo /etc/nixos/scripts/deploy-age-keys.sh"
        log_info "  - Run: sudo nixos-rebuild switch"
        log_info "  - Check: sudo systemctl status sops-install-secrets.service"
    fi
    
    # Generate report if requested or if errors occurred
    if [[ $overall_status -ne 0 ]]; then
        echo ""
        log_info "Run '$0 --report' for detailed diagnostic information"
    fi
    
    exit $overall_status
}

# Run main function with all arguments
main "$@"