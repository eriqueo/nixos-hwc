#!/usr/bin/env bash
set -euo pipefail

# Monitoring Infrastructure Setup Script
# Deploys Prometheus, Grafana, and custom monitoring containers
#
# Usage: setup-monitoring.sh [OPTIONS]
#
# Examples:
#   setup-monitoring.sh
#   setup-monitoring.sh --dry-run
#   setup-monitoring.sh --skip-build
#   setup-monitoring.sh --help

# Configuration (can be overridden by environment variables)
readonly DEFAULT_MONITORING_ROOT="/opt/monitoring"
readonly DEFAULT_NODE_EXPORTER_DIR="/var/lib/node_exporter/textfile_collector"
readonly DEFAULT_OWNER="eric"
readonly DEFAULT_GROUP="users"
readonly PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
readonly GRAFANA_PORT="${GRAFANA_PORT:-3000}"
readonly BUSINESS_DASHBOARD_PORT="${BUSINESS_DASHBOARD_PORT:-8501}"

# Script state
DRY_RUN=false
SKIP_BUILD=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging functions
log_header() { echo -e "\n${BOLD}${BLUE}$*${NC}"; }
log_info() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "\n${BOLD}$*${NC}"; }

# Usage information
show_usage() {
    cat << EOF
${BOLD}Monitoring Infrastructure Setup Script${NC}

Deploys and configures monitoring infrastructure including Prometheus, Grafana,
Alertmanager, and custom business/media monitoring dashboards.

${BOLD}USAGE:${NC}
    $(basename "$0") [OPTIONS]

${BOLD}OPTIONS:${NC}
    -n, --dry-run           Show what would be done without making changes
    -s, --skip-build        Skip container build steps
    -r, --root DIR          Monitoring root directory
                            (default: ${DEFAULT_MONITORING_ROOT})
    -o, --owner USER        File owner for monitoring directories
                            (default: ${DEFAULT_OWNER})
    -g, --group GROUP       File group for monitoring directories
                            (default: ${DEFAULT_GROUP})
    -h, --help              Show this help message

${BOLD}EXAMPLES:${NC}
    # Standard setup
    $(basename "$0")

    # Preview changes without applying
    $(basename "$0") --dry-run

    # Skip building containers (if already built)
    $(basename "$0") --skip-build

    # Custom monitoring root
    $(basename "$0") --root /srv/monitoring

${BOLD}ENVIRONMENT VARIABLES:${NC}
    MONITORING_ROOT         Override monitoring root directory
    PROMETHEUS_PORT         Prometheus port (default: 9090)
    GRAFANA_PORT            Grafana port (default: 3000)
    BUSINESS_DASHBOARD_PORT Business dashboard port (default: 8501)

${BOLD}WHAT THIS SCRIPT DOES:${NC}
    1. Creates monitoring directory structure
    2. Builds custom monitoring containers (media-monitor, business-dashboard)
    3. Sets proper permissions
    4. Creates systemd health check service
    5. Displays next steps for deployment

${BOLD}PREREQUISITES:${NC}
    - podman installed and accessible
    - sudo privileges
    - systemctl available
    - curl installed (for health checks)

EOF
}

# Parse command line arguments
parse_args() {
    MONITORING_ROOT="${MONITORING_ROOT:-$DEFAULT_MONITORING_ROOT}"
    NODE_EXPORTER_DIR="${NODE_EXPORTER_DIR:-$DEFAULT_NODE_EXPORTER_DIR}"
    OWNER="${OWNER:-$DEFAULT_OWNER}"
    GROUP="${GROUP:-$DEFAULT_GROUP}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                log_warn "DRY RUN MODE - No changes will be made"
                shift
                ;;
            -s|--skip-build)
                SKIP_BUILD=true
                shift
                ;;
            -r|--root)
                MONITORING_ROOT="$2"
                shift 2
                ;;
            -o|--owner)
                OWNER="$2"
                shift 2
                ;;
            -g|--group)
                GROUP="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_usage
                exit 2
                ;;
        esac
    done
}

# Check dependencies
check_dependencies() {
    log_step "🔍 Checking dependencies..."

    local missing=()
    for cmd in sudo podman systemctl curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        echo ""
        echo "Please install missing dependencies and try again."
        exit 1
    fi

    log_info "All dependencies found"
}

# Validate configuration
validate_config() {
    log_step "✅ Validating configuration..."

    # Check if owner exists
    if ! id "$OWNER" >/dev/null 2>&1; then
        log_error "User '$OWNER' does not exist"
        exit 1
    fi

    # Check if group exists
    if ! getent group "$GROUP" >/dev/null 2>&1; then
        log_error "Group '$GROUP' does not exist"
        exit 1
    fi

    # Check if parent directory exists
    local parent_dir
    parent_dir="$(dirname "$MONITORING_ROOT")"
    if [[ ! -d "$parent_dir" ]]; then
        log_error "Parent directory does not exist: $parent_dir"
        exit 1
    fi

    log_info "Configuration valid"
    echo "  Monitoring root: $MONITORING_ROOT"
    echo "  Node exporter dir: $NODE_EXPORTER_DIR"
    echo "  Owner: $OWNER:$GROUP"
}

# Execute command with dry-run support
execute() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

# Create monitoring directories
create_directories() {
    log_step "📁 Creating monitoring directories..."

    local dirs=(
        "$MONITORING_ROOT/prometheus"
        "$MONITORING_ROOT/grafana"
        "$MONITORING_ROOT/alertmanager"
        "$MONITORING_ROOT/blackbox"
        "$MONITORING_ROOT/media-monitor"
        "$MONITORING_ROOT/business"
        "$NODE_EXPORTER_DIR"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Directory already exists: $dir"
        else
            execute sudo mkdir -p "$dir"
            log_info "Created: $dir"
        fi
    done
}

# Build monitoring containers
build_containers() {
    if [[ "$SKIP_BUILD" == true ]]; then
        log_step "🐳 Skipping container builds (--skip-build specified)"
        return 0
    fi

    log_step "🐳 Building custom monitoring containers..."

    # Build media monitor container
    local media_monitor_dir="$MONITORING_ROOT/media-monitor"
    if [[ -d "$media_monitor_dir" ]]; then
        if [[ -f "$media_monitor_dir/Dockerfile" || -f "$media_monitor_dir/Containerfile" ]]; then
            log_info "Building media-pipeline-monitor..."
            if ! execute sudo podman build -t media-pipeline-monitor:latest "$media_monitor_dir"; then
                log_error "Failed to build media-pipeline-monitor"
                return 1
            fi
            log_info "Built media-pipeline-monitor:latest"
        else
            log_warn "No Dockerfile found in $media_monitor_dir, skipping media monitor build"
        fi
    else
        log_warn "Media monitor directory does not exist: $media_monitor_dir"
    fi

    # Build business dashboard container
    local business_dir="$MONITORING_ROOT/business"
    if [[ -d "$business_dir" ]]; then
        if [[ -f "$business_dir/Dockerfile" || -f "$business_dir/Containerfile" ]]; then
            log_info "Building business-dashboard..."
            if ! execute sudo podman build -t business-dashboard:latest "$business_dir"; then
                log_error "Failed to build business-dashboard"
                return 1
            fi
            log_info "Built business-dashboard:latest"
        else
            log_warn "No Dockerfile found in $business_dir, skipping business dashboard build"
        fi
    else
        log_warn "Business directory does not exist: $business_dir"
    fi
}

# Set proper permissions
set_permissions() {
    log_step "🔑 Setting permissions..."

    # Set ownership of monitoring root
    if [[ -d "$MONITORING_ROOT" ]]; then
        execute sudo chown -R "$OWNER:$GROUP" "$MONITORING_ROOT"
        log_info "Set ownership: $OWNER:$GROUP on $MONITORING_ROOT"
    fi

    # Make scripts executable if they exist
    local scripts=(
        "$MONITORING_ROOT/media-monitor/media_monitor.py"
        "$MONITORING_ROOT/business/dashboard.py"
        "$MONITORING_ROOT/business/business_metrics.py"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            execute sudo chmod +x "$script"
            log_info "Made executable: $script"
        fi
    done
}

# Create systemd health check service
create_systemd_service() {
    log_step "⚙️ Creating monitoring health check service..."

    local service_file="/tmp/monitoring-health-check.service"
    local target_file="/etc/systemd/system/monitoring-health-check.service"

    # Create service file
    cat > "$service_file" << 'EOF'
[Unit]
Description=Monitoring Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for i in {1..30}; do curl -s http://localhost:9090/-/healthy && curl -s http://localhost:3000/api/health && exit 0; sleep 10; done; exit 1'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Install service file
    if execute sudo mv "$service_file" "$target_file"; then
        log_info "Created systemd service: $target_file"
    else
        log_error "Failed to create systemd service"
        rm -f "$service_file"
        return 1
    fi

    # Reload systemd
    if execute sudo systemctl daemon-reload; then
        log_info "Reloaded systemd daemon"
    else
        log_error "Failed to reload systemd daemon"
        return 1
    fi
}

# Show completion summary
show_summary() {
    log_header "📊 Monitoring Infrastructure Setup Complete!"

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        log_warn "DRY RUN completed - no changes were made"
        echo "Run without --dry-run to apply changes."
        return 0
    fi

    cat << EOF

${BOLD}Next Steps:${NC}
  1. Run 'sudo nixos-rebuild switch' to deploy the monitoring stack
  2. Access Grafana at http://localhost:${GRAFANA_PORT}
  3. Access Prometheus at http://localhost:${PROMETHEUS_PORT}
  4. Access Business Dashboard at http://localhost:${BUSINESS_DASHBOARD_PORT}

${BOLD}Services Being Monitored:${NC}
  • 12 media containers (Sonarr, Radarr, Lidarr, etc.)
  • System metrics (CPU, Memory, Disk, Network)
  • GPU utilization and temperature
  • Storage tiers (hot/cold)
  • Business intelligence metrics
  • Custom media pipeline health

${BOLD}Features:${NC}
  • Mobile access: All dashboards are mobile-optimized
  • Alerts: Configured for storage, performance, and service issues
  • Health checks: Automated monitoring of service availability

${BOLD}Configuration:${NC}
  • Monitoring root: ${MONITORING_ROOT}
  • Owner: ${OWNER}:${GROUP}

EOF

    log_info "Setup complete!"
}

# Main function
main() {
    # Parse arguments
    parse_args "$@"

    # Show header
    log_header "🔧 Heartwood Craft Monitoring Infrastructure Setup"

    # Pre-flight checks
    check_dependencies
    validate_config

    # Execute setup steps
    create_directories || {
        log_error "Failed to create directories"
        exit 1
    }

    build_containers || {
        log_error "Failed to build containers"
        exit 1
    }

    set_permissions || {
        log_error "Failed to set permissions"
        exit 1
    }

    create_systemd_service || {
        log_error "Failed to create systemd service"
        exit 1
    }

    # Show summary
    show_summary

    exit 0
}

# Execute main function
main "$@"
