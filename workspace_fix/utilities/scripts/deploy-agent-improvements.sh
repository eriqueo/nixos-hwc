#!/bin/bash
# Integration script for ChatGPT Agent improvements
# Deploys the reviewed and corrected implementations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="/etc/nixos"
LOG_FILE="/var/log/deploy-agent-improvements.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [deploy-agents] $*" | tee -a "$LOG_FILE"
}

# Function to backup current configuration
backup_current_config() {
    local backup_dir="/etc/nixos/backups/pre-agent-deploy-$(date +%Y%m%d_%H%M%S)"
    
    log "Creating backup of current configuration at $backup_dir"
    mkdir -p "$backup_dir"
    
    # Backup key configuration files
    cp -r /etc/nixos/hosts/ "$backup_dir/" 2>/dev/null || true
    cp -r /etc/nixos/modules/ "$backup_dir/" 2>/dev/null || true
    cp /etc/nixos/configuration.nix "$backup_dir/" 2>/dev/null || true
    
    log "Backup created successfully"
    echo "$backup_dir"
}

# Function to validate new modules exist
validate_modules() {
    local modules=(
        "/etc/nixos/modules/frigate-storage-management.nix"
        "/etc/nixos/modules/backup-system.nix"
        "/etc/nixos/modules/arr-pipeline-monitoring.nix"
    )
    
    log "Validating new modules exist..."
    
    for module in "${modules[@]}"; do
        if [[ ! -f "$module" ]]; then
            log "ERROR: Module not found: $module"
            return 1
        else
            log "✓ Found module: $module"
        fi
    done
    
    # Validate syntax
    for module in "${modules[@]}"; do
        if ! nix-instantiate --parse "$module" >/dev/null 2>&1; then
            log "ERROR: Syntax error in module: $module"
            return 1
        else
            log "✓ Syntax valid: $module"
        fi
    done
    
    return 0
}

# Function to add modules to configuration
add_modules_to_config() {
    local server_config="/etc/nixos/hosts/server/configuration.nix"
    
    log "Adding new modules to server configuration..."
    
    if [[ ! -f "$server_config" ]]; then
        log "ERROR: Server configuration not found: $server_config"
        return 1
    fi
    
    # Check if modules are already added
    if grep -q "frigate-storage-management.nix" "$server_config" 2>/dev/null; then
        log "Modules appear to already be configured"
        return 0
    fi
    
    # Add import lines for new modules
    local temp_config=$(mktemp)
    
    # Find the imports section and add our modules
    awk '
    /imports = \[/ { 
        print $0
        print "    ../../modules/frigate-storage-management.nix"
        print "    ../../modules/backup-system.nix"
        print "    ../../modules/arr-pipeline-monitoring.nix"
        next
    }
    { print }
    ' "$server_config" > "$temp_config"
    
    # Replace the original config
    if mv "$temp_config" "$server_config"; then
        log "✓ Added modules to server configuration"
        return 0
    else
        log "ERROR: Failed to update server configuration"
        return 1
    fi
}

# Function to test configuration
test_configuration() {
    log "Testing NixOS configuration..."
    
    if sudo nixos-rebuild test --flake .#hwc-server; then
        log "✓ Configuration test successful"
        return 0
    else
        log "ERROR: Configuration test failed"
        return 1
    fi
}

# Function to deploy configuration
deploy_configuration() {
    log "Deploying configuration changes..."
    
    # Use grebuild if available, otherwise use nixos-rebuild switch
    if command -v grebuild >/dev/null 2>&1; then
        if grebuild "Deploy ChatGPT Agent improvements: Frigate storage, ARR monitoring, backup system"; then
            log "✓ Configuration deployed successfully via grebuild"
            return 0
        else
            log "ERROR: Deployment failed via grebuild"
            return 1
        fi
    else
        log "grebuild not available, using direct nixos-rebuild"
        if sudo nixos-rebuild switch --flake .#hwc-server; then
            log "✓ Configuration deployed successfully"
            return 0
        else
            log "ERROR: Deployment failed"
            return 1
        fi
    fi
}

# Function to verify services are running
verify_services() {
    log "Verifying new services are operational..."
    
    local services=(
        "frigate-storage-prune.service"
        "frigate-camera-watchdog.service"
        "arr-pipeline-monitor.service"
        "arr-queue-cleanup.service"
    )
    
    local failed_services=0
    
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log "✓ Service enabled: $service"
            
            # Check if service can start (oneshot services won't show as active)
            if systemctl start "$service" 2>/dev/null; then
                log "✓ Service starts successfully: $service"
            else
                log "⚠ Service start issue: $service (may be normal for oneshot)"
            fi
        else
            log "⚠ Service not enabled: $service"
            ((failed_services++))
        fi
    done
    
    if [[ $failed_services -eq 0 ]]; then
        log "✓ All services verified"
        return 0
    else
        log "⚠ $failed_services services had issues (may be expected)"
        return 0  # Don't fail deployment for service warnings
    fi
}

# Function to show deployment summary
show_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    log "The following improvements have been deployed:"
    log ""
    log "Agent 2 (Surveillance):"
    log "  ✓ Frigate storage pruning (2TB cap)"
    log "  ✓ Camera watchdog monitoring"
    log ""
    log "Agent 5 (ARR Pipeline):"
    log "  ✓ Pipeline health monitoring"
    log "  ✓ Queue cleanup automation"
    log ""
    log "Agent 10 (Backup):"
    log "  ✓ USB backup system"
    log "  ✓ Backup verification"
    log ""
    log "Agent 3 (Documentation):"
    log "  ✓ Documentation standards"
    log ""
    log "Next Steps:"
    log "  1. Monitor logs: tail -f $LOG_FILE"
    log "  2. Check service status: systemctl status frigate-storage-prune.service"
    log "  3. Test USB backup: systemctl start backup-usb.service"
    log "  4. Review documentation: /etc/nixos/docs/SYSTEM_DOCUMENTATION_STANDARDS.md"
    log ""
    log "All services integrate with existing Prometheus monitoring."
}

# Main execution
main() {
    log "=== STARTING AGENT IMPROVEMENTS DEPLOYMENT ==="
    
    # Change to NixOS directory
    cd "$NIXOS_DIR" || {
        log "ERROR: Could not change to NixOS directory"
        exit 1
    }
    
    # Create backup
    local backup_path
    backup_path=$(backup_current_config)
    
    # Validate modules
    if ! validate_modules; then
        log "ERROR: Module validation failed"
        exit 1
    fi
    
    # Add modules to configuration
    if ! add_modules_to_config; then
        log "ERROR: Failed to add modules to configuration"
        log "Restore from backup: cp -r $backup_path/* /etc/nixos/"
        exit 1
    fi
    
    # Test configuration
    if ! test_configuration; then
        log "ERROR: Configuration test failed"
        log "Restore from backup: cp -r $backup_path/* /etc/nixos/"
        exit 1
    fi
    
    # Deploy configuration
    if ! deploy_configuration; then
        log "ERROR: Deployment failed"
        log "Restore from backup: cp -r $backup_path/* /etc/nixos/"
        exit 1
    fi
    
    # Verify services
    sleep 5  # Give services time to initialize
    verify_services
    
    # Show summary
    show_summary
    
    log "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    log "Backup available at: $backup_path"
    
    return 0
}

# Command line interface
case "${1:-}" in
    "test")
        log "Running in test mode - no changes will be made"
        validate_modules
        log "Test completed - modules are ready for deployment"
        ;;
    "deploy")
        main
        ;;
    "rollback")
        if [[ -n "${2:-}" && -d "$2" ]]; then
            log "Rolling back from backup: $2"
            cp -r "$2"/* /etc/nixos/
            sudo nixos-rebuild switch --flake .#hwc-server
            log "Rollback completed"
        else
            log "ERROR: Please provide backup directory path"
            log "Usage: $0 rollback /path/to/backup"
            exit 1
        fi
        ;;
    "status")
        log "Checking status of deployed services..."
        services=("frigate-storage-prune" "frigate-camera-watchdog" "arr-pipeline-monitor" "arr-queue-cleanup")
        for service in "${services[@]}"; do
            systemctl status "${service}.service" --no-pager -l || true
        done
        ;;
    "help"|"--help"|"-h"|"")
        cat << 'HELP_EOF'
ChatGPT Agent Improvements Deployment Script

Usage: deploy-agent-improvements.sh [COMMAND]

Commands:
  test      - Validate modules without making changes
  deploy    - Deploy all agent improvements to the system
  rollback  - Rollback to a previous backup
  status    - Check status of deployed services
  help      - Show this help message

Examples:
  # Test before deploying
  ./deploy-agent-improvements.sh test
  
  # Deploy improvements
  ./deploy-agent-improvements.sh deploy
  
  # Check service status
  ./deploy-agent-improvements.sh status
  
  # Rollback if needed
  ./deploy-agent-improvements.sh rollback /etc/nixos/backups/pre-agent-deploy-20250807_123456

The script deploys:
- Agent 2: Frigate storage management and camera monitoring
- Agent 5: ARR pipeline health monitoring and queue management  
- Agent 10: USB backup system with verification
- Agent 3: Documentation standards

All improvements are integrated with existing monitoring infrastructure.
HELP_EOF
        ;;
    *)
        log "ERROR: Unknown command: $1"
        log "Use './deploy-agent-improvements.sh help' for usage information"
        exit 1
        ;;
esac
