#!/usr/bin/env bash
# HWC Service Lister
# Lists all configured services with status and access URLs

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get Tailscale domain from routes.nix or use default
DOMAIN="hwc.ocelot-wahoo.ts.net"

echo -e "${CYAN}=== HWC Server Services ===${NC}\n"

# Function to check if service is running
check_service() {
    local service=$1
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}●${NC}"
    else
        echo -e "${RED}○${NC}"
    fi
}

# Function to check if container is running
check_container() {
    local container=$1
    if podman ps --format "{{.Names}}" | grep -q "^${container}$" 2>/dev/null; then
        echo -e "${GREEN}●${NC}"
    else
        echo -e "${RED}○${NC}"
    fi
}

echo -e "${YELLOW}MEDIA SERVICES${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-3s %-15s %-10s %-50s\n" "●" "Service" "Type" "Access URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_service jellyfin)" \
    "Jellyfin" \
    "Native" \
    "https://${DOMAIN}/jellyfin"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container jellyseerr)" \
    "Jellyseerr" \
    "Container" \
    "https://${DOMAIN}/jellyseerr (alt :5543)"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_service navidrome)" \
    "Navidrome" \
    "Native" \
    "https://${DOMAIN}/music"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_service immich-server)" \
    "Immich" \
    "Native" \
    "https://${DOMAIN}:7443/"

echo ""
echo -e "${YELLOW}DOWNLOAD & INDEXING${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-3s %-15s %-10s %-50s\n" "●" "Service" "Type" "Access URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container sonarr)" \
    "Sonarr" \
    "Container" \
    "https://${DOMAIN}/sonarr"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container radarr)" \
    "Radarr" \
    "Container" \
    "https://${DOMAIN}/radarr"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container lidarr)" \
    "Lidarr" \
    "Container" \
    "https://${DOMAIN}/lidarr"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container prowlarr)" \
    "Prowlarr" \
    "Container" \
    "https://${DOMAIN}/prowlarr"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container sabnzbd)" \
    "Sabnzbd" \
    "Container" \
    "https://${DOMAIN}/sab"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container qbittorrent)" \
    "qBittorrent" \
    "Container" \
    "https://${DOMAIN}/qbt"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container slskd)" \
    "slskd" \
    "Container" \
    "https://${DOMAIN}:8443/"

echo ""
echo -e "${YELLOW}INFRASTRUCTURE${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-3s %-15s %-10s %-50s\n" "●" "Service" "Type" "Access URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_container frigate)" \
    "Frigate" \
    "Container" \
    "https://${DOMAIN}:5443/"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_service couchdb)" \
    "CouchDB" \
    "Native" \
    "https://${DOMAIN}/sync"

printf "%-3s %-15s %-10s %-50s\n" \
    "$(check_service caddy)" \
    "Caddy" \
    "Native" \
    "Reverse Proxy"

echo ""
echo -e "${CYAN}Legend:${NC} ${GREEN}●${NC} Running  ${RED}○${NC} Stopped"
echo ""
echo -e "${CYAN}Firewall Open Ports:${NC}"
echo "  8096 (TCP)     - Jellyfin HTTP"
echo "  7359 (TCP/UDP) - Jellyfin Discovery"
echo "  2283 (TCP)     - Immich HTTP"
echo "  4533 (TCP)     - Navidrome HTTP"
echo ""
echo -e "${CYAN}Commands:${NC}"
echo "  Health Check:  bash workspace/utilities/scripts/caddy-health-check.sh"
echo "  Full Docs:     cat domains/server/SERVICES.md"
echo "  Quick Ref:     cat domains/server/QUICK-REFERENCE.md"
echo ""
