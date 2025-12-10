#!/usr/bin/env bash
#
# Volume and Path Setup Script
# Creates required directories, sets permissions, verifies space
#
# Usage:
#   ./setup-volumes.sh [--config volumes.yaml] [--dry-run]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONFIG_FILE="${1:-volumes.yaml}"
DRY_RUN=false

if [[ "${2:-}" == "--dry-run" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

log() {
    echo -e "${GREEN}[setup-volumes]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

exec_or_print() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

# Generate default config if not exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Config file not found, generating default: $CONFIG_FILE"

    cat > "$CONFIG_FILE" <<'YAML_CONFIG'
# Volume Configuration for HWC Media Server
# Edit paths, sizes, and permissions as needed

volumes:
  # Mount points (expect these to be mounted)
  - path: /mnt/hot
    type: mount_point
    purpose: "Hot storage (SSD) for downloads and processing"
    size_required: 500GB
    owner: eric:eric
    mode: "0755"

  - path: /mnt/media
    type: mount_point
    purpose: "Media library (HDD) - movies, TV, music"
    size_required: 4TB
    owner: eric:eric
    mode: "0755"

  # Application directories
  - path: /opt/downloads
    type: directory
    purpose: "Download staging and processing"
    owner: eric:eric
    mode: "0755"

  - path: /opt/arr
    type: directory
    purpose: "*arr application configs"
    owner: eric:eric
    mode: "0755"

  - path: /opt/ai
    type: directory
    purpose: "AI models and data"
    size_required: 50GB
    owner: eric:eric
    mode: "0755"

  - path: /opt/secrets
    type: directory
    purpose: "Decrypted secrets for services"
    owner: root:secrets
    mode: "0750"

  # Service-specific directories
  - path: /opt/downloads/gluetun
    type: directory
    purpose: "Gluetun VPN config"
    owner: eric:eric
    mode: "0755"

  - path: /opt/downloads/qbittorrent
    type: directory
    purpose: "qBittorrent config"
    owner: eric:eric
    mode: "0755"

  - path: /opt/downloads/sabnzbd
    type: directory
    purpose: "SABnzbd config"
    owner: eric:eric
    mode: "0755"

  - path: /opt/arr/sonarr
    type: directory
    purpose: "Sonarr config"
    owner: eric:eric
    mode: "0755"

  - path: /opt/arr/radarr
    type: directory
    purpose: "Radarr config"
    owner: eric:eric
    mode: "0755"

  - path: /opt/arr/lidarr
    type: directory
    purpose: "Lidarr config"
    owner: eric:eric
    mode: "0755"

  - path: /opt/arr/prowlarr
    type: directory
    purpose: "Prowlarr config"
    owner: eric:eric
    mode: "0755"

  # Native service data directories
  - path: /var/lib/jellyfin
    type: directory
    purpose: "Jellyfin data"
    owner: jellyfin:jellyfin
    mode: "0755"

  - path: /var/lib/immich
    type: directory
    purpose: "Immich data"
    owner: immich:immich
    mode: "0755"
YAML_CONFIG

    info "Default config generated: $CONFIG_FILE"
    info "Edit this file to customize paths, then run again"
    exit 0
fi

log "Volume setup script"
[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN MODE"

log "Reading configuration: $CONFIG_FILE"

# Check for required tools
command -v yq >/dev/null 2>&1 || {
    warn "yq not found, installing..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sudo pacman -S --needed yq || error "Failed to install yq"
    fi
}

# Parse YAML and process each volume
VOLUME_COUNT=$(yq '.volumes | length' "$CONFIG_FILE")

log "Processing $VOLUME_COUNT volumes..."

SUCCESS_COUNT=0
FAILED_COUNT=0
WARNINGS_COUNT=0

for ((i=0; i<VOLUME_COUNT; i++)); do
    # Extract volume config
    vol_path=$(yq ".volumes[$i].path" "$CONFIG_FILE")
    vol_type=$(yq ".volumes[$i].type" "$CONFIG_FILE")
    vol_purpose=$(yq ".volumes[$i].purpose" "$CONFIG_FILE")
    vol_owner=$(yq ".volumes[$i].owner // \"root:root\"" "$CONFIG_FILE")
    vol_mode=$(yq ".volumes[$i].mode // \"0755\"" "$CONFIG_FILE")
    vol_size_required=$(yq ".volumes[$i].size_required // \"none\"" "$CONFIG_FILE")

    echo ""
    info "[$((i+1))/$VOLUME_COUNT] $vol_path"
    echo "  Type: $vol_type"
    echo "  Purpose: $vol_purpose"

    # Handle mount points
    if [[ "$vol_type" == "mount_point" ]]; then
        if mountpoint -q "$vol_path" 2>/dev/null; then
            info "  ✓ Already mounted"
            ((SUCCESS_COUNT++))
        else
            warn "  ✗ NOT MOUNTED"
            echo "  Action required: Mount a filesystem at $vol_path"
            echo "  Expected size: $vol_size_required"
            ((WARNINGS_COUNT++))
            continue
        fi
    fi

    # Create directory if it doesn't exist
    if [[ ! -d "$vol_path" ]]; then
        info "  Creating directory..."
        exec_or_print sudo mkdir -p "$vol_path"
    else
        info "  ✓ Directory exists"
    fi

    # Set ownership
    current_owner=$(stat -c '%U:%G' "$vol_path" 2>/dev/null || echo "unknown")
    if [[ "$current_owner" != "$vol_owner" ]]; then
        info "  Setting ownership: $vol_owner (was: $current_owner)"
        exec_or_print sudo chown "$vol_owner" "$vol_path"
    else
        info "  ✓ Ownership correct: $vol_owner"
    fi

    # Set permissions
    current_mode=$(stat -c '%a' "$vol_path" 2>/dev/null || echo "unknown")
    if [[ "$current_mode" != "${vol_mode#0}" ]]; then
        info "  Setting permissions: $vol_mode (was: $current_mode)"
        exec_or_print sudo chmod "$vol_mode" "$vol_path"
    else
        info "  ✓ Permissions correct: $vol_mode"
    fi

    # Check disk space if size_required specified
    if [[ "$vol_size_required" != "none" && "$vol_size_required" != "null" ]]; then
        # Convert size to bytes (simplified, assumes GB)
        required_gb=$(echo "$vol_size_required" | grep -oP '\d+')

        # Get available space in GB
        if [[ -d "$vol_path" ]]; then
            available_gb=$(df -BG "$vol_path" | awk 'NR==2 {print $4}' | sed 's/G//')

            if [[ "$available_gb" -lt "$required_gb" ]]; then
                warn "  ✗ Insufficient space: ${available_gb}GB available, ${required_gb}GB required"
                ((WARNINGS_COUNT++))
            else
                info "  ✓ Sufficient space: ${available_gb}GB available (${required_gb}GB required)"
            fi
        fi
    fi

    ((SUCCESS_COUNT++))
done

echo ""
echo "========================================="
echo "SUMMARY"
echo "========================================="
echo ""
log "Processed: $VOLUME_COUNT volumes"
echo "  ✓ Success: $SUCCESS_COUNT"
[[ "$WARNINGS_COUNT" -gt 0 ]] && echo "  ⚠ Warnings: $WARNINGS_COUNT"
[[ "$FAILED_COUNT" -gt 0 ]] && echo "  ✗ Failed: $FAILED_COUNT"
echo ""

# Generate verification report
REPORT_FILE="volume-setup-report.json"

log "Generating report: $REPORT_FILE"

if [[ "$DRY_RUN" == "false" ]]; then
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"volumes\": ["

        for ((i=0; i<VOLUME_COUNT; i++)); do
            vol_path=$(yq ".volumes[$i].path" "$CONFIG_FILE")
            vol_type=$(yq ".volumes[$i].type" "$CONFIG_FILE")

            status="ok"
            message=""

            # Check status
            if [[ "$vol_type" == "mount_point" ]]; then
                if ! mountpoint -q "$vol_path" 2>/dev/null; then
                    status="not_mounted"
                    message="Mount point not mounted"
                fi
            elif [[ ! -d "$vol_path" ]]; then
                status="missing"
                message="Directory does not exist"
            fi

            echo "    {"
            echo "      \"path\": \"$vol_path\","
            echo "      \"type\": \"$vol_type\","
            echo "      \"status\": \"$status\","
            echo "      \"message\": \"$message\""
            echo -n "    }"

            [[ $i -lt $((VOLUME_COUNT-1)) ]] && echo "," || echo ""
        done

        echo "  ]"
        echo "}"
    } > "$REPORT_FILE"

    info "Report saved: $REPORT_FILE"
fi

# Print action items if any warnings
if [[ "$WARNINGS_COUNT" -gt 0 ]]; then
    echo ""
    echo "========================================="
    echo "ACTION ITEMS"
    echo "========================================="
    echo ""

    # Check for unmounted filesystems
    for ((i=0; i<VOLUME_COUNT; i++)); do
        vol_path=$(yq ".volumes[$i].path" "$CONFIG_FILE")
        vol_type=$(yq ".volumes[$i].type" "$CONFIG_FILE")
        vol_size_required=$(yq ".volumes[$i].size_required // \"none\"" "$CONFIG_FILE")

        if [[ "$vol_type" == "mount_point" ]]; then
            if ! mountpoint -q "$vol_path" 2>/dev/null; then
                warn "Mount required: $vol_path ($vol_size_required)"
                echo "  Suggested commands:"
                echo "    # Create partition and filesystem"
                echo "    sudo mkfs.ext4 /dev/sdX1"
                echo "    # Add to /etc/fstab"
                echo "    sudo echo '/dev/sdX1 $vol_path ext4 defaults 0 2' >> /etc/fstab"
                echo "    # Mount"
                echo "    sudo mount $vol_path"
                echo ""
            fi
        fi
    done
fi

log "Volume setup complete!"
echo ""
echo "Verify with:"
echo "  cat $REPORT_FILE"
echo "  df -h"
echo "  ls -la /mnt /opt"
