#!/usr/bin/env bash
# domains/infrastructure/winapps/parts/vm-manager.sh
# VM management utilities for WinApps

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

VM_NAME="RDPWindows"

show_help() {
    cat << EOF
VM Manager for WinApps

Usage: $(basename "$0") <command>

Commands:
    status      Show VM status and info
    start       Start the VM
    stop        Stop the VM gracefully
    restart     Restart the VM
    ip          Get VM IP address
    rdp-test    Test RDP connection
    snapshot    Create VM snapshot
    info        Show detailed VM information
    help        Show this help

Examples:
    $(basename "$0") status
    $(basename "$0") start
    $(basename "$0") ip
EOF
}

check_vm_exists() {
    if ! virsh list --all | grep -q "$VM_NAME"; then
        log_error "VM '$VM_NAME' not found"
        log_info "Create the VM using virt-manager with exact name: $VM_NAME"
        exit 1
    fi
}

get_vm_state() {
    virsh domstate "$VM_NAME" 2>/dev/null
}

get_vm_ip() {
    local ip
    ip=$(virsh domifaddr "$VM_NAME" 2>/dev/null | awk '/vnet/ {print $4}' | cut -d'/' -f1 | head -1)
    echo "$ip"
}

cmd_status() {
    check_vm_exists

    local state
    state=$(get_vm_state)

    log_info "VM Status: $state"

    if [[ "$state" == "running" ]]; then
        local ip
        ip=$(get_vm_ip)
        if [[ -n "$ip" ]]; then
            log_info "VM IP: $ip"
        else
            log_warning "VM running but IP not found"
        fi

        # Check RDP port
        if [[ -n "$ip" ]] && timeout 2 bash -c "</dev/tcp/$ip/3389" &>/dev/null; then
            log_success "RDP port accessible"
        elif [[ -n "$ip" ]]; then
            log_warning "RDP port not accessible on $ip"
        fi
    fi
}

cmd_start() {
    check_vm_exists

    local state
    state=$(get_vm_state)

    if [[ "$state" == "running" ]]; then
        log_info "VM is already running"
        return 0
    fi

    log_info "Starting VM '$VM_NAME'..."
    if virsh start "$VM_NAME"; then
        log_success "VM started successfully"

        # Wait for IP
        log_info "Waiting for VM to get IP address..."
        for i in {1..30}; do
            local ip
            ip=$(get_vm_ip)
            if [[ -n "$ip" ]]; then
                log_success "VM IP: $ip"
                break
            fi
            sleep 2
        done
    else
        log_error "Failed to start VM"
        exit 1
    fi
}

cmd_stop() {
    check_vm_exists

    local state
    state=$(get_vm_state)

    if [[ "$state" == "shut off" ]]; then
        log_info "VM is already stopped"
        return 0
    fi

    log_info "Stopping VM '$VM_NAME' gracefully..."
    if virsh shutdown "$VM_NAME"; then
        log_info "Shutdown signal sent, waiting..."

        # Wait up to 60 seconds for graceful shutdown
        for i in {1..30}; do
            state=$(get_vm_state)
            if [[ "$state" == "shut off" ]]; then
                log_success "VM stopped gracefully"
                return 0
            fi
            sleep 2
        done

        log_warning "Graceful shutdown timed out, forcing shutdown..."
        virsh destroy "$VM_NAME"
        log_warning "VM forcefully stopped"
    else
        log_error "Failed to stop VM"
        exit 1
    fi
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_ip() {
    check_vm_exists

    local state
    state=$(get_vm_state)

    if [[ "$state" != "running" ]]; then
        log_error "VM is not running (state: $state)"
        exit 1
    fi

    local ip
    ip=$(get_vm_ip)

    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        log_error "Could not determine VM IP address"
        exit 1
    fi
}

cmd_rdp_test() {
    local ip
    ip=$(cmd_ip)

    log_info "Testing RDP connection to $ip..."

    if timeout 5 bash -c "</dev/tcp/$ip/3389" &>/dev/null; then
        log_success "RDP port 3389 is accessible"

        # Test with xfreerdp if available
        if command -v xfreerdp &>/dev/null; then
            log_info "You can test RDP connection with:"
            echo "xfreerdp /v:$ip /u:<username> /cert:ignore"
        fi
    else
        log_error "Cannot connect to RDP port 3389"
        log_info "Check that:"
        log_info "  - RDP is enabled in Windows"
        log_info "  - Windows firewall allows RDP"
        log_info "  - VM network is properly configured"
    fi
}

cmd_snapshot() {
    check_vm_exists

    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local snapshot_name="winapps-$timestamp"
    local description="WinApps snapshot created $(date)"

    log_info "Creating snapshot '$snapshot_name'..."

    if virsh snapshot-create-as "$VM_NAME" "$snapshot_name" "$description"; then
        log_success "Snapshot created: $snapshot_name"
        log_info "List snapshots with: virsh snapshot-list $VM_NAME"
        log_info "Restore with: virsh snapshot-revert $VM_NAME $snapshot_name"
    else
        log_error "Failed to create snapshot"
        exit 1
    fi
}

cmd_info() {
    check_vm_exists

    log_info "VM Information:"
    echo

    # Basic info
    virsh dominfo "$VM_NAME"
    echo

    # Network interfaces
    log_info "Network Interfaces:"
    virsh domifaddr "$VM_NAME" || log_warning "Could not get interface info"
    echo

    # Snapshots
    log_info "Snapshots:"
    virsh snapshot-list "$VM_NAME" || log_info "No snapshots found"
}

main() {
    case "${1:-help}" in
        status)
            cmd_status
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        ip)
            cmd_ip
            ;;
        rdp-test)
            cmd_rdp_test
            ;;
        snapshot)
            cmd_snapshot
            ;;
        info)
            cmd_info
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"