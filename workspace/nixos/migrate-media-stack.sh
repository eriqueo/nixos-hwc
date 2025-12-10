#\!/bin/bash
# migrate-media-stack.sh
# Migration script for boring-reliable media stack with deterministic Forms auth

set -euo pipefail

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/media-stack-backup-${TIMESTAMP}"
CONFIG_PATHS=("/opt/downloads" "/docker")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Function: Backup existing configurations
backup_configs() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    for config_path in "${CONFIG_PATHS[@]}"; do
        if [[ -d "$config_path" ]]; then
            log "Backing up $config_path to $BACKUP_DIR"
            cp -r "$config_path" "$BACKUP_DIR/" || warn "Failed to backup $config_path"
        else
            warn "Config path $config_path does not exist, skipping backup"
        fi
    done
    
    log "Backup completed at: $BACKUP_DIR"
}

# Function: Update *arr app configurations for deterministic Forms auth
update_arr_configs() {
    local app="$1"
    local url_base="$2"
    local config_file
    
    # Try both old (/opt/downloads) and new (/docker) paths
    for base_path in "/opt/downloads" "/docker"; do
        config_file="${base_path}/${app}/config.xml"
        
        if [[ -f "$config_file" ]]; then
            log "Updating $app configuration: $config_file"
            
            # Install xmlstarlet if not available
            if \! command -v xmlstarlet >/dev/null 2>&1; then
                warn "xmlstarlet not found, attempting to install"
                if command -v nix-env >/dev/null 2>&1; then
                    nix-env -iA nixpkgs.xmlstarlet
                else
                    error "Cannot install xmlstarlet - please install manually"
                    return 1
                fi
            fi
            
            # Create backup of original config
            cp "$config_file" "${config_file}.backup-${TIMESTAMP}"
            
            # Update authentication settings - handle both schema variations
            # Method 1: AuthenticationMethod (newer versions)
            xmlstarlet ed -L \
                -u '/Config/AuthenticationMethod' -v 'Forms' \
                -u '/Config/AuthenticationRequired' -v 'Enabled' \
                -u '/Config/UrlBase' -v "$url_base" \
                "$config_file" 2>/dev/null || {
                
                # Method 2: AuthenticationType (older versions)  
                xmlstarlet ed -L \
                    -u '/Config/AuthenticationType' -v 'Forms' \
                    -u '/Config/AuthenticationRequired' -v 'Enabled' \
                    -u '/Config/UrlBase' -v "$url_base" \
                    "$config_file" 2>/dev/null || {
                    
                    # Method 3: Insert missing elements if they don't exist
                    xmlstarlet ed -L \
                        -s '/Config[not(AuthenticationMethod)]' -t elem -n 'AuthenticationMethod' -v 'Forms' \
                        -s '/Config[not(AuthenticationRequired)]' -t elem -n 'AuthenticationRequired' -v 'Enabled' \
                        -s '/Config[not(UrlBase)]' -t elem -n 'UrlBase' -v "$url_base" \
                        "$config_file" || warn "Failed to update $config_file - manual intervention required"
                }
            }
            
            log "Updated $app: Forms auth enabled, UrlBase=$url_base"
            return 0
        fi
    done
    
    warn "Config file not found for $app - will be created on first container start"
}

# Function: Stop existing services
stop_services() {
    log "Stopping existing media services..."
    
    local services=(
        "podman-gluetun"
        "podman-qbittorrent" 
        "podman-sabnzbd"
        "podman-sonarr"
        "podman-radarr"
        "podman-lidarr"
        "podman-prowlarr"
        "podman-soularr"
        "podman-slskd"
        "podman-navidrome"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service.service" 2>/dev/null; then
            log "Stopping $service..."
            systemctl stop "$service.service" || warn "Failed to stop $service"
        fi
    done
}

# Function: Apply NixOS configuration
apply_nixos_config() {
    log "Applying new NixOS media stack configuration..."
    
    # Test configuration first
    if \! nixos-rebuild test --flake .#hwc-server; then
        error "NixOS configuration test failed\!"
        error "Check configuration syntax and try again"
        return 1
    fi
    
    log "Configuration test passed, applying..."
    nixos-rebuild switch --flake .#hwc-server
}

# Function: Start services in proper order
start_services() {
    log "Starting media services in dependency order..."
    
    local service_order=(
        "gluetun"
        "qbittorrent"
        "sabnzbd" 
        "sonarr"
        "radarr"
        "lidarr"
        "prowlarr"
        "soularr"
        "slskd"
    )
    
    for service in "${service_order[@]}"; do
        log "Starting podman-$service..."
        systemctl start "podman-$service.service"
        
        # Wait a moment for service to initialize
        sleep 5
        
        if systemctl is-active --quiet "podman-$service.service"; then
            log "✓ $service started successfully"
        else
            warn "✗ $service failed to start - check logs: journalctl -fu podman-$service.service"
        fi
    done
}

# Function: Health checks
health_checks() {
    log "Performing health checks..."
    
    local -A services=(
        ["sonarr"]="8989"
        ["radarr"]="7878"
        ["lidarr"]="8686"
        ["prowlarr"]="9696"
        ["soularr"]="9898"
        ["slskd"]="5030"
        ["qbittorrent"]="8080"  # Via Gluetun
        ["sabnzbd"]="8081"      # Via Gluetun
    )
    
    local failed_services=()
    
    # Wait for services to fully initialize
    log "Waiting 30 seconds for services to initialize..."
    sleep 30
    
    for service in "${\!services[@]}"; do
        local port="${services[$service]}"
        local url="https://hwc.ocelot-wahoo.ts.net/${service}/"
        
        log "Checking $service at $url..."
        
        if curl -sI --max-time 10 "$url" | head -n1 | grep -q "200\|302\|401"; then
            log "✓ $service: PASS (accessible via Tailscale)"
        else
            warn "✗ $service: FAIL (not accessible via Tailscale)"
            failed_services+=("$service")
        fi
    done
    
    # Summary
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log "🎉 All services passed health checks\!"
        log "Media stack migration completed successfully"
        log "Access your services at: https://hwc.ocelot-wahoo.ts.net/SERVICE/"
    else
        warn "❌ Failed services: ${failed_services[*]}"
        warn "Troubleshooting steps:"
        warn "1. Check service logs: journalctl -fu podman-SERVICE.service"
        warn "2. Verify container status: podman ps"
        warn "3. Test direct port access: curl -I http://127.0.0.1:PORT"
        warn "4. Hard refresh browser (Ctrl+F5) to clear cached assets"
    fi
}

# Main execution
main() {
    log "Starting media stack migration..."
    log "This will migrate to deterministic Forms auth with Caddy subpaths"
    
    # Confirmation prompt
    read -p "Continue with migration? (y/N): " -n 1 -r
    echo
    if [[ \! $REPLY =~ ^[Yy]$ ]]; then
        log "Migration cancelled"
        exit 0
    fi
    
    # Execute migration steps
    backup_configs
    
    # Update *arr configurations
    update_arr_configs "sonarr" "/sonarr"
    update_arr_configs "radarr" "/radarr"  
    update_arr_configs "lidarr" "/lidarr"
    update_arr_configs "prowlarr" "/prowlarr"
    
    stop_services
    apply_nixos_config
    start_services
    health_checks
    
    log "Migration completed\!"
    log "Backup stored at: $BACKUP_DIR"
}

# Execute main function
main "$@"
