#!/usr/bin/env bash
set -euo pipefail

# Frigate Container Launcher
# Launches Frigate NVR with proper configuration and media storage
#
# Usage: launch_frigate.sh [OPTIONS]
#
# Examples:
#   launch_frigate.sh
#   launch_frigate.sh --dry-run
#   launch_frigate.sh --config /custom/path

# Configuration (can be overridden by environment variables)
readonly DEFAULT_DOTFILES_CONFIG="${HOME}/workspace/dotfiles/frigate"
readonly DEFAULT_LOCAL_CONFIG="${HOME}/frigate/config"
readonly DEFAULT_LOCAL_MEDIA="${HOME}/frigate/media"
readonly DEFAULT_CONTAINER_NAME="frigate"
readonly DEFAULT_FRIGATE_IMAGE="ghcr.io/blakeblackshear/frigate:stable"
readonly DEFAULT_TMPFS_SIZE="100000000"  # 100MB

# SECURITY WARNING: Default password for backward compatibility only
# STRONGLY RECOMMENDED: Set FRIGATE_RTSP_PASSWORD environment variable!
readonly DEFAULT_RTSP_PASSWORD="iL0wwlm?"

# Script state
DRY_RUN=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }

# Usage information
show_usage() {
    cat << EOF
Frigate Container Launcher

Launches Frigate NVR container with proper configuration.

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    -n, --dry-run           Show what would be done without making changes
    -c, --config PATH       Custom configuration path (default: ${DEFAULT_LOCAL_CONFIG})
    -m, --media PATH        Custom media storage path (default: ${DEFAULT_LOCAL_MEDIA})
    --name NAME             Container name (default: ${DEFAULT_CONTAINER_NAME})
    -h, --help              Show this help message

ENVIRONMENT VARIABLES:
    FRIGATE_RTSP_PASSWORD   RTSP password (RECOMMENDED for security)
    DOTFILES_CONFIG         Dotfiles configuration path
    FRIGATE_LOCAL_CONFIG    Local configuration path
    FRIGATE_LOCAL_MEDIA     Media storage path
    FRIGATE_IMAGE           Container image

SECURITY WARNING:
    This script uses a default RTSP password for backward compatibility.
    ${RED}SET FRIGATE_RTSP_PASSWORD environment variable for production!${NC}

    Example:
        export FRIGATE_RTSP_PASSWORD="your-secure-password"
        $(basename "$0")

EXAMPLES:
    # Launch with environment password
    export FRIGATE_RTSP_PASSWORD="my-secret-password"
    $(basename "$0")

    # Dry run
    $(basename "$0") --dry-run

    # Custom paths
    $(basename "$0") --config /custom/config --media /custom/media

EOF
}

# Parse command line arguments
parse_args() {
    DOTFILES_CONFIG="${DOTFILES_CONFIG:-$DEFAULT_DOTFILES_CONFIG}"
    LOCAL_CONFIG="${FRIGATE_LOCAL_CONFIG:-$DEFAULT_LOCAL_CONFIG}"
    LOCAL_MEDIA="${FRIGATE_LOCAL_MEDIA:-$DEFAULT_LOCAL_MEDIA}"
    CONTAINER_NAME="${FRIGATE_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
    FRIGATE_IMAGE="${FRIGATE_IMAGE:-$DEFAULT_FRIGATE_IMAGE}"

    # SECURITY: Use environment variable or fall back to default (with warning)
    RTSP_PASSWORD="${FRIGATE_RTSP_PASSWORD:-$DEFAULT_RTSP_PASSWORD}"

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
            -c|--config)
                LOCAL_CONFIG="$2"
                shift 2
                ;;
            -m|--media)
                LOCAL_MEDIA="$2"
                shift 2
                ;;
            --name)
                CONTAINER_NAME="$2"
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

    readonly DOTFILES_CONFIG LOCAL_CONFIG LOCAL_MEDIA CONTAINER_NAME FRIGATE_IMAGE RTSP_PASSWORD
}

# Validate configuration
validate_config() {
    log_info "Validating configuration..."

    # Check if dotfiles config exists
    if [[ ! -d "$DOTFILES_CONFIG" ]]; then
        log_error "Dotfiles configuration not found: $DOTFILES_CONFIG"
        exit 1
    fi

    # SECURITY CHECK: Warn if using default password
    if [[ "$RTSP_PASSWORD" == "$DEFAULT_RTSP_PASSWORD" ]]; then
        echo ""
        log_warn "═════════════════════════════════════════════════════════"
        log_warn "SECURITY WARNING: Using default RTSP password!"
        log_warn "Set FRIGATE_RTSP_PASSWORD environment variable"
        log_warn "═════════════════════════════════════════════════════════"
        echo ""
    fi

    # Check if docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "docker command not found"
        exit 1
    fi

    log_info "Configuration validated"
}

# Setup directories
setup_directories() {
    log_info "Setting up directories..."

    # Create frigate base directory
    local base_dir="${LOCAL_CONFIG%/*}"
    if [[ ! -d "$base_dir" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY RUN] mkdir -p $base_dir"
        else
            mkdir -p "$base_dir"
            log_info "Created: $base_dir"
        fi
    fi

    # Symlink config if not already linked
    if [[ ! -L "$LOCAL_CONFIG" ]]; then
        if [[ -e "$LOCAL_CONFIG" ]]; then
            log_warn "Config exists but is not a symlink: $LOCAL_CONFIG"
        else
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] ln -s $DOTFILES_CONFIG $LOCAL_CONFIG"
            else
                ln -s "$DOTFILES_CONFIG" "$LOCAL_CONFIG"
                log_info "Linked $LOCAL_CONFIG -> $DOTFILES_CONFIG"
            fi
        fi
    else
        log_info "Config already symlinked"
    fi

    # Create media directory
    if [[ ! -d "$LOCAL_MEDIA" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY RUN] mkdir -p $LOCAL_MEDIA"
        else
            mkdir -p "$LOCAL_MEDIA"
            log_info "Created: $LOCAL_MEDIA"
        fi
    else
        log_info "Media directory exists"
    fi
}

# Remove existing container if present
remove_existing() {
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Container '$CONTAINER_NAME' exists, removing..."

        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY RUN] docker stop $CONTAINER_NAME"
            echo "[DRY RUN] docker rm $CONTAINER_NAME"
        else
            docker stop "$CONTAINER_NAME" 2>/dev/null || true
            docker rm "$CONTAINER_NAME" 2>/dev/null || true
            log_info "Removed existing container"
        fi
    fi
}

# Launch container
launch_container() {
    log_info "Launching Frigate container..."

    local cmd=(
        docker run -d
        --name "$CONTAINER_NAME"
        --restart=unless-stopped
        --privileged
        --mount "type=tmpfs,target=/tmp/cache,tmpfs-size=${DEFAULT_TMPFS_SIZE}"
        -v "${LOCAL_CONFIG}:/config"
        -v "${LOCAL_MEDIA}:/media"
        -v "/etc/localtime:/etc/localtime:ro"
        -p "5000:5000"
        -e "FRIGATE_RTSP_PASSWORD=${RTSP_PASSWORD}"
        "$FRIGATE_IMAGE"
    )

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] ${cmd[*]}"
    else
        if "${cmd[@]}"; then
            log_info "Container launched successfully"
        else
            log_error "Failed to launch container"
            return 1
        fi
    fi
}

# Show summary
show_summary() {
    echo ""
    log_info "Frigate setup complete!"

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        log_warn "DRY RUN completed - no changes made"
        return 0
    fi

    cat << EOF

Container Information:
  Name:    $CONTAINER_NAME
  Image:   $FRIGATE_IMAGE
  Config:  $LOCAL_CONFIG
  Media:   $LOCAL_MEDIA
  Web UI:  http://localhost:5000

Useful Commands:
  View logs:  docker logs -f $CONTAINER_NAME
  Stop:       docker stop $CONTAINER_NAME
  Restart:    docker restart $CONTAINER_NAME
  Remove:     docker rm -f $CONTAINER_NAME

Security:
  RTSP Password: ${RTSP_PASSWORD:0:3}***
  ${YELLOW}Set FRIGATE_RTSP_PASSWORD for production use!${NC}

EOF
}

# Main function
main() {
    parse_args "$@"

    echo -e "${BLUE}Frigate Container Launcher${NC}"
    echo ""

    validate_config
    setup_directories
    remove_existing
    launch_container || exit 1
    show_summary

    exit 0
}

# Execute main function
main "$@"
