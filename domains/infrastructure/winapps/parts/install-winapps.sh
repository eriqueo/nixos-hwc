#!/usr/bin/env bash
# domains/infrastructure/winapps/parts/install-winapps.sh
# Automated WinApps installation and setup script

set -euo pipefail

# Configuration
WINAPPS_DIR="${HOME}/03-tech/local-storage/winapps"
CONFIG_DIR="${HOME}/.config/winapps"
REPO_URL="https://github.com/winapps-org/winapps.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running on NixOS
    if [[ ! -f /etc/os-release ]] || ! grep -q "ID=nixos" /etc/os-release; then
        log_error "This script is designed for NixOS systems"
        exit 1
    fi

    # Check if virtualization is available
    if [[ ! -e /dev/kvm ]]; then
        log_error "KVM virtualization not available. Ensure virtualization is enabled in BIOS/UEFI"
        exit 1
    fi

    # Check required commands
    local required_commands=("git" "virsh")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found. Ensure WinApps infrastructure is enabled in NixOS config"
            exit 1
        fi
    done

    # Check for FreeRDP (try multiple versions)
    if ! command -v "xfreerdp3" &> /dev/null && ! command -v "xfreerdp" &> /dev/null; then
        log_error "FreeRDP not found. Ensure WinApps infrastructure is enabled in NixOS config"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

check_vm_status() {
    log_info "Checking RDPWindows VM status..."

    if ! virsh list --all | grep -q "RDPWindows"; then
        log_warning "RDPWindows VM not found. You need to create it manually with virt-manager"
        log_info "VM Requirements:"
        log_info "  - Name: RDPWindows (exact name required)"
        log_info "  - OS: Windows 10/11 Pro (RDP support needed)"
        log_info "  - RAM: 8GB minimum (16GB recommended)"
        log_info "  - Storage: 60GB minimum"
        return 1
    fi

    local vm_state=$(virsh domstate RDPWindows 2>/dev/null || echo "undefined")
    log_info "RDPWindows VM state: $vm_state"

    if [[ "$vm_state" == "running" ]]; then
        log_success "RDPWindows VM is running"
        return 0
    elif [[ "$vm_state" == "shut off" ]]; then
        log_warning "RDPWindows VM is shut off. You may need to start it for testing"
        return 0
    else
        log_warning "RDPWindows VM state is: $vm_state"
        return 1
    fi
}

test_rdp_connection() {
    log_info "Testing RDP connection..."

    if [[ ! -f "$CONFIG_DIR/winapps.conf" ]]; then
        log_warning "WinApps config not found. RDP test skipped"
        return 1
    fi

    # Source the config file
    source "$CONFIG_DIR/winapps.conf"

    if [[ -z "${RDP_IP:-}" ]]; then
        log_warning "RDP_IP not set in config. Cannot test connection"
        return 1
    fi

    log_info "Testing connection to $RDP_IP..."

    # Test if port 3389 is open
    if timeout 5 bash -c "</dev/tcp/$RDP_IP/3389" &>/dev/null; then
        log_success "RDP port 3389 is accessible on $RDP_IP"
        return 0
    else
        log_warning "Cannot connect to RDP port 3389 on $RDP_IP"
        log_info "Ensure:"
        log_info "  - Windows VM is running"
        log_info "  - RDP is enabled in Windows"
        log_info "  - Windows firewall allows RDP"
        log_info "  - IP address is correct"
        return 1
    fi
}

clone_winapps() {
    log_info "Setting up WinApps repository..."

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$WINAPPS_DIR")"

    if [[ -d "$WINAPPS_DIR" ]]; then
        log_info "WinApps directory exists, updating..."
        cd "$WINAPPS_DIR"
        git pull origin main || {
            log_warning "Git pull failed, trying fresh clone..."
            cd "$(dirname "$WINAPPS_DIR")"
            rm -rf "$WINAPPS_DIR"
            git clone "$REPO_URL" "$WINAPPS_DIR"
        }
    else
        log_info "Cloning WinApps repository..."
        git clone "$REPO_URL" "$WINAPPS_DIR"
    fi

    cd "$WINAPPS_DIR"
    log_success "WinApps repository ready at $WINAPPS_DIR"
}

install_winapps() {
    log_info "Installing WinApps..."

    cd "$WINAPPS_DIR"

    # Make installer executable
    chmod +x install.sh

    # Run installer
    log_info "Running WinApps installer..."
    if ./install.sh; then
        log_success "WinApps installed successfully"
    else
        log_error "WinApps installation failed"
        return 1
    fi

    # Verify installation
    if [[ -f "$HOME/.local/bin/winapps" ]]; then
        log_success "WinApps binary installed at $HOME/.local/bin/winapps"
    else
        log_warning "WinApps binary not found in expected location"
    fi
}

setup_excel() {
    log_info "Setting up Excel application..."

    cd "$WINAPPS_DIR"

    # Install Excel specifically
    if ./winapps install excel; then
        log_success "Excel application configured"

        # Check for desktop file
        if [[ -f "$HOME/.local/share/applications/Excel.desktop" ]]; then
            log_success "Excel desktop entry created"
        else
            log_warning "Excel desktop entry not found"
        fi
    else
        log_warning "Excel setup may have failed. Check if Windows VM is accessible"
    fi
}

print_next_steps() {
    log_success "WinApps installation complete!"
    echo
    log_info "Next steps:"
    echo "1. Ensure your Windows VM (RDPWindows) is running"
    echo "2. Verify RDP is enabled in Windows and firewall allows it"
    echo "3. Install Microsoft Office in the Windows VM"
    echo "4. Test Excel by running: winapps excel"
    echo "5. Or look for 'Microsoft Excel' in your application menu"
    echo
    log_info "Configuration files:"
    echo "  - WinApps config: $CONFIG_DIR/winapps.conf"
    echo "  - WinApps installation: $WINAPPS_DIR"
    echo "  - Desktop entries: $HOME/.local/share/applications/"
    echo
    log_info "Troubleshooting:"
    echo "  - Check VM status: virsh list --all"
    echo "  - Test RDP: xfreerdp /v:<VM_IP> /u:<username> /cert:ignore"
    echo "  - View logs: journalctl -u libvirtd"
}

main() {
    log_info "Starting WinApps automated installation..."
    echo

    check_prerequisites
    echo

    check_vm_status
    vm_available=$?
    echo

    clone_winapps
    echo

    install_winapps
    echo

    if [[ $vm_available -eq 0 ]]; then
        test_rdp_connection
        echo

        setup_excel
        echo
    else
        log_warning "Skipping Excel setup - VM not accessible"
        echo
    fi

    print_next_steps
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi