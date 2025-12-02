#!/usr/bin/env bash

# SOPS Age Key Deployment Script
# This script deploys age private keys to the correct system locations
# for SOPS secrets decryption on both laptop and server hosts.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$NIXOS_DIR/secrets/keys"
TARGET_DIR="/etc/sops/age"
TARGET_FILE="$TARGET_DIR/keys.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
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
            log_error "Unknown hostname: $hostname"
            log_error "Expected 'homeserver' or 'heartwood-laptop'"
            exit 1
            ;;
    esac
}

# Validate source key file exists
validate_source_key() {
    local host_type="$1"
    local source_file="$SECRETS_DIR/${host_type}.txt"
    
    if [[ ! -f "$source_file" ]]; then
        log_error "Source key file not found: $source_file"
        exit 1
    fi
    
    if [[ ! -s "$source_file" ]]; then
        log_error "Source key file is empty: $source_file"
        exit 1
    fi
    
    # Basic validation - age keys should start with "AGE-SECRET-KEY-"
    if ! grep -q "^AGE-SECRET-KEY-" "$source_file"; then
        log_error "Invalid age key format in: $source_file"
        log_error "Age private keys should start with 'AGE-SECRET-KEY-'"
        exit 1
    fi
    
    log_success "Source key file validated: $source_file"
}

# Create target directory with proper permissions
create_target_directory() {
    log_info "Creating target directory: $TARGET_DIR"
    
    # Create directory structure
    mkdir -p "$TARGET_DIR"
    
    # Set proper ownership and permissions
    chown root:root "$TARGET_DIR"
    chmod 755 "$TARGET_DIR"
    
    log_success "Target directory created with proper permissions"
}

# Deploy age key
deploy_age_key() {
    local host_type="$1"
    local source_file="$SECRETS_DIR/${host_type}.txt"
    
    log_info "Deploying age key for $host_type host"
    
    # Backup existing key if it exists
    if [[ -f "$TARGET_FILE" ]]; then
        local backup_file="${TARGET_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_warning "Existing key file found, creating backup: $backup_file"
        cp "$TARGET_FILE" "$backup_file"
        chmod 600 "$backup_file"
    fi
    
    # Copy the key file
    cp "$source_file" "$TARGET_FILE"
    
    # Set proper ownership and permissions
    chown root:root "$TARGET_FILE"
    chmod 600 "$TARGET_FILE"
    
    log_success "Age key deployed successfully"
    log_info "Key location: $TARGET_FILE"
    log_info "Permissions: $(ls -la "$TARGET_FILE")"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check file exists
    if [[ ! -f "$TARGET_FILE" ]]; then
        log_error "Target file does not exist: $TARGET_FILE"
        return 1
    fi
    
    # Check permissions
    local perms=$(stat -c "%a" "$TARGET_FILE")
    if [[ "$perms" != "600" ]]; then
        log_error "Incorrect permissions: $perms (expected 600)"
        return 1
    fi
    
    # Check ownership
    local owner=$(stat -c "%U:%G" "$TARGET_FILE")
    if [[ "$owner" != "root:root" ]]; then
        log_error "Incorrect ownership: $owner (expected root:root)"
        return 1
    fi
    
    # Check content format
    if ! grep -q "^AGE-SECRET-KEY-" "$TARGET_FILE"; then
        log_error "Invalid key format in deployed file"
        return 1
    fi
    
    log_success "Deployment verification passed"
    return 0
}

# Test SOPS functionality
test_sops_functionality() {
    log_info "Testing SOPS functionality..."
    
    # Try to decrypt a test secret
    local test_files=("$NIXOS_DIR/secrets/admin.yaml" "$NIXOS_DIR/secrets/database.yaml")
    
    for test_file in "${test_files[@]}"; do
        if [[ -f "$test_file" ]]; then
            log_info "Testing decryption of: $(basename "$test_file")"
            
            if sops -d "$test_file" >/dev/null 2>&1; then
                log_success "Successfully decrypted: $(basename "$test_file")"
                return 0
            else
                log_warning "Failed to decrypt: $(basename "$test_file")"
            fi
        fi
    done
    
    log_error "Could not decrypt any test files"
    log_error "This may indicate an issue with the key deployment"
    return 1
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy SOPS age private keys to system locations"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  --verify-only    Only verify existing deployment"
    echo "  --test-only      Only test SOPS functionality"
    echo ""
    echo "This script automatically detects the host type and deploys"
    echo "the appropriate age key for SOPS secrets decryption."
}

# Main execution
main() {
    local verify_only=false
    local test_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            --test-only)
                test_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "SOPS Age Key Deployment Script"
    log_info "=============================="
    
    # Check if running as root
    check_root
    
    # Handle special modes
    if [[ "$verify_only" == true ]]; then
        verify_deployment
        exit $?
    fi
    
    if [[ "$test_only" == true ]]; then
        test_sops_functionality
        exit $?
    fi
    
    # Detect host type
    local host_type
    host_type=$(detect_host)
    log_info "Detected host type: $host_type"
    
    # Validate source key
    validate_source_key "$host_type"
    
    # Create target directory
    create_target_directory
    
    # Deploy age key
    deploy_age_key "$host_type"
    
    # Verify deployment
    if ! verify_deployment; then
        log_error "Deployment verification failed"
        exit 1
    fi
    
    # Test SOPS functionality
    if ! test_sops_functionality; then
        log_warning "SOPS functionality test failed"
        log_warning "The key was deployed but decryption test failed"
        log_warning "This may be normal if secrets were encrypted with different keys"
    fi
    
    echo ""
    log_success "Age key deployment completed successfully!"
    log_info "You can now use SOPS to decrypt secrets on this host"
    log_info ""
    log_info "Next steps:"
    log_info "1. Run 'sudo nixos-rebuild switch' to apply SOPS configuration"
    log_info "2. Restart services that depend on SOPS secrets if needed"
    log_info "3. Test secret access: sops -d /etc/nixos/secrets/admin.yaml"
}

# Run main function with all arguments
main "$@"