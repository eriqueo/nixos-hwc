#!/usr/bin/env bash
# domains/infrastructure/winapps/parts/winapps-helper.sh
# WinApps management helper commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/winapps"
WINAPPS_DIR="${HOME}/03-tech/local-storage/winapps"

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

show_help() {
    cat << EOF
WinApps Helper - Manage Windows applications on Linux

Usage: $(basename "$0") <command> [args]

Commands:
    setup           Run automated WinApps installation
    vm              VM management (status, start, stop, ip, etc.)
    excel           Launch Excel
    word            Launch Word (if installed)
    powerpoint      Launch PowerPoint (if installed)
    config          Edit WinApps configuration
    status          Show WinApps and VM status
    install-app     Install additional Windows app
    uninstall-app   Uninstall Windows app
    list-apps       List installed WinApps
    logs            Show relevant system logs
    help            Show this help

VM Commands:
    vm status       Show VM status
    vm start        Start Windows VM
    vm stop         Stop Windows VM
    vm ip           Get VM IP address
    vm rdp-test     Test RDP connection

Examples:
    $(basename "$0") setup
    $(basename "$0") vm status
    $(basename "$0") excel
    $(basename "$0") status
EOF
}

cmd_setup() {
    log_info "Running automated WinApps setup..."
    bash "$SCRIPT_DIR/install-winapps.sh"
}

cmd_vm() {
    bash "$SCRIPT_DIR/vm-manager.sh" "$@"
}

cmd_excel() {
    if [[ -f "$HOME/.local/bin/winapps" ]]; then
        log_info "Launching Excel..."
        "$HOME/.local/bin/winapps" excel
    elif [[ -f "$WINAPPS_DIR/winapps" ]]; then
        log_info "Launching Excel..."
        "$WINAPPS_DIR/winapps" excel
    else
        log_error "WinApps not found. Run '$0 setup' first"
        exit 1
    fi
}

cmd_word() {
    if [[ -f "$HOME/.local/bin/winapps" ]]; then
        log_info "Launching Word..."
        "$HOME/.local/bin/winapps" word
    elif [[ -f "$WINAPPS_DIR/winapps" ]]; then
        log_info "Launching Word..."
        "$WINAPPS_DIR/winapps" word
    else
        log_error "WinApps not found. Run '$0 setup' first"
        exit 1
    fi
}

cmd_powerpoint() {
    if [[ -f "$HOME/.local/bin/winapps" ]]; then
        log_info "Launching PowerPoint..."
        "$HOME/.local/bin/winapps" powerpoint
    elif [[ -f "$WINAPPS_DIR/winapps" ]]; then
        log_info "Launching PowerPoint..."
        "$WINAPPS_DIR/winapps" powerpoint
    else
        log_error "WinApps not found. Run '$0 setup' first"
        exit 1
    fi
}

cmd_config() {
    if [[ ! -f "$CONFIG_DIR/winapps.conf" ]]; then
        log_error "WinApps config not found. Run '$0 setup' first"
        exit 1
    fi

    if command -v "${EDITOR:-nano}" &>/dev/null; then
        "${EDITOR:-nano}" "$CONFIG_DIR/winapps.conf"
    else
        log_info "Config file location: $CONFIG_DIR/winapps.conf"
        log_info "Edit with your preferred editor"
    fi
}

cmd_status() {
    log_info "WinApps Status Check"
    echo

    # Check WinApps installation
    if [[ -f "$HOME/.local/bin/winapps" ]]; then
        log_success "WinApps binary: $HOME/.local/bin/winapps"
    elif [[ -f "$WINAPPS_DIR/winapps" ]]; then
        log_warning "WinApps found in source directory: $WINAPPS_DIR/winapps"
    else
        log_error "WinApps not installed"
    fi

    # Check config
    if [[ -f "$CONFIG_DIR/winapps.conf" ]]; then
        log_success "Config file: $CONFIG_DIR/winapps.conf"
        source "$CONFIG_DIR/winapps.conf"
        log_info "RDP Target: ${RDP_USER:-<not set>}@${RDP_IP:-<not set>}"
    else
        log_error "Config file not found"
    fi

    echo

    # Check VM status
    bash "$SCRIPT_DIR/vm-manager.sh" status

    echo

    # Check desktop files
    local desktop_files=(
        "$HOME/.local/share/applications/Excel.desktop"
        "$HOME/.local/share/applications/Word.desktop"
        "$HOME/.local/share/applications/PowerPoint.desktop"
    )

    log_info "Desktop Integration:"
    for desktop_file in "${desktop_files[@]}"; do
        if [[ -f "$desktop_file" ]]; then
            local app_name
            app_name=$(basename "$desktop_file" .desktop)
            log_success "$app_name desktop entry found"
        fi
    done
}

cmd_install_app() {
    local app_name="${1:-}"
    if [[ -z "$app_name" ]]; then
        log_error "Usage: $0 install-app <app_name>"
        log_info "Common apps: excel, word, powerpoint, notepad, calc"
        exit 1
    fi

    if [[ -f "$WINAPPS_DIR/winapps" ]]; then
        log_info "Installing $app_name..."
        cd "$WINAPPS_DIR"
        ./winapps install "$app_name"
    else
        log_error "WinApps not found. Run '$0 setup' first"
        exit 1
    fi
}

cmd_uninstall_app() {
    local app_name="${1:-}"
    if [[ -z "$app_name" ]]; then
        log_error "Usage: $0 uninstall-app <app_name>"
        exit 1
    fi

    if [[ -f "$WINAPPS_DIR/winapps" ]]; then
        log_info "Uninstalling $app_name..."
        cd "$WINAPPS_DIR"
        ./winapps uninstall "$app_name"
    else
        log_error "WinApps not found"
        exit 1
    fi
}

cmd_list_apps() {
    log_info "Installed WinApps:"
    echo

    local desktop_dir="$HOME/.local/share/applications"
    if [[ -d "$desktop_dir" ]]; then
        find "$desktop_dir" -name "*.desktop" -exec basename {} .desktop \; | sort
    else
        log_warning "No desktop applications directory found"
    fi
}

cmd_logs() {
    log_info "Showing recent WinApps-related logs..."
    echo

    # libvirtd logs
    log_info "Libvirtd logs (last 10 lines):"
    journalctl -u libvirtd --no-pager -n 10 || log_warning "Could not access libvirtd logs"
    echo

    # Check for WinApps errors in user logs
    if journalctl --user --no-pager -n 20 2>/dev/null | grep -i "winapps\|rdp\|freerdp" | head -5; then
        echo
    else
        log_info "No recent WinApps entries in user logs"
    fi
}

main() {
    case "${1:-help}" in
        setup)
            cmd_setup
            ;;
        vm)
            shift
            cmd_vm "$@"
            ;;
        excel)
            cmd_excel
            ;;
        word)
            cmd_word
            ;;
        powerpoint)
            cmd_powerpoint
            ;;
        config)
            cmd_config
            ;;
        status)
            cmd_status
            ;;
        install-app)
            shift
            cmd_install_app "$@"
            ;;
        uninstall-app)
            shift
            cmd_uninstall_app "$@"
            ;;
        list-apps)
            cmd_list_apps
            ;;
        logs)
            cmd_logs
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