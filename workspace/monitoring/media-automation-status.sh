#!/usr/bin/env bash
#
# Media Automation Pipeline Status Checker
# Comprehensive diagnostics for nixos-hwc media automation
#
# Usage: ./media-automation-status.sh [--verbose]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

# Helper functions
print_header() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${BOLD}${CYAN}▶ $1${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

check_service() {
    local service=$1
    local status
    if systemctl is-active --quiet "$service"; then
        status="active"
        print_ok "Service: $service (${GREEN}active${NC})"
        return 0
    else
        status=$(systemctl is-active "$service" 2>&1 || true)
        print_error "Service: $service (${RED}$status${NC})"
        return 1
    fi
}

check_container() {
    local container=$1
    if sudo podman ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        local status=$(sudo podman ps --filter "name=$container" --format "{{.Status}}")
        print_ok "Container: $container (${GREEN}running${NC} - $status)"
        return 0
    else
        print_error "Container: $container (${RED}not running${NC})"
        return 1
    fi
}

count_files() {
    local path=$1
    local depth=${2:-1}
    if [[ -d "$path" ]]; then
        find "$path" -maxdepth "$depth" -mindepth 1 | wc -l
    else
        echo "0"
    fi
}

# ============================================================================
# MAIN STATUS CHECK
# ============================================================================

print_header "MEDIA AUTOMATION PIPELINE STATUS"
echo -e "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "Hostname: $(hostname)"

# ============================================================================
# 1. SYSTEM SERVICES
# ============================================================================
print_header "1. SYSTEM SERVICES"

print_section "Core Media Services"
check_service "media-orchestrator.service" || true
check_service "media-orchestrator-install.service" || true

print_section "Arr Container Services"
check_service "podman-sonarr.service" || true
check_service "podman-radarr.service" || true
check_service "podman-lidarr.service" || true
check_service "podman-prowlarr.service" || true

print_section "Download Client Services"
check_service "podman-qbittorrent.service" || true
check_service "podman-sabnzbd.service" || true
check_service "podman-slskd.service" || true

print_section "Supporting Services"
check_service "podman-jellyfin.service" || true
check_service "podman-gluetun.service" || true
check_service "podman-caddy.service" || true

# ============================================================================
# 2. CONTAINER STATUS
# ============================================================================
print_header "2. CONTAINER STATUS"

print_section "Arr Apps"
check_container "sonarr" || true
check_container "radarr" || true
check_container "lidarr" || true
check_container "prowlarr" || true

print_section "Download Clients"
check_container "qbittorrent" || true
check_container "sabnzbd" || true
check_container "slskd" || true

print_section "Media Servers"
check_container "jellyfin" || true

print_section "Networking"
check_container "gluetun" || true
check_container "caddy" || true

# ============================================================================
# 3. STORAGE STATUS
# ============================================================================
print_header "3. STORAGE STATUS"

print_section "Mount Points"
if mountpoint -q /mnt/hot; then
    hot_usage=$(df -h /mnt/hot | awk 'NR==2 {print $5}')
    print_ok "/mnt/hot mounted (${hot_usage} used)"
else
    print_error "/mnt/hot NOT mounted"
fi

if mountpoint -q /mnt/media; then
    media_usage=$(df -h /mnt/media | awk 'NR==2 {print $5}')
    print_ok "/mnt/media mounted (${media_usage} used)"
else
    print_error "/mnt/media NOT mounted"
fi

print_section "Download Directory Structure"
if [[ -d /mnt/hot/downloads ]]; then
    print_ok "/mnt/hot/downloads exists"
    tv_count=$(count_files "/mnt/hot/downloads/tv" 1)
    movie_count=$(count_files "/mnt/hot/downloads/movies" 1)
    music_count=$(count_files "/mnt/hot/downloads/music" 1)
    print_info "  TV shows: $tv_count items"
    print_info "  Movies: $movie_count items"
    print_info "  Music: $music_count items"
else
    print_error "/mnt/hot/downloads does not exist"
fi

print_section "Media Library Structure"
if [[ -d /mnt/media ]]; then
    print_ok "/mnt/media exists"
    tv_lib=$(count_files "/mnt/media/tv" 1)
    movie_lib=$(count_files "/mnt/media/movies" 1)
    music_lib=$(count_files "/mnt/media/music" 1)
    print_info "  TV library: $tv_lib shows"
    print_info "  Movie library: $movie_lib movies"
    print_info "  Music library: $music_lib albums"
else
    print_error "/mnt/media does not exist"
fi

# ============================================================================
# 4. EVENT SPOOL STATUS
# ============================================================================
print_header "4. EVENT SPOOL STATUS"

print_section "Event Files"
if [[ -d /mnt/hot/events ]]; then
    print_ok "/mnt/hot/events directory exists"

    for event_file in qbt.ndjson sab.ndjson slskd.ndjson; do
        path="/mnt/hot/events/$event_file"
        if [[ -f "$path" ]]; then
            size=$(du -h "$path" | cut -f1)
            lines=$(wc -l < "$path" 2>/dev/null || echo "0")
            print_ok "$event_file exists (${size}, ${lines} events)"

            if $VERBOSE && [[ $lines -gt 0 ]]; then
                echo -e "    ${BLUE}Last 3 events:${NC}"
                tail -3 "$path" | while read -r line; do
                    echo -e "      $(echo "$line" | jq -c '.' 2>/dev/null || echo "$line")"
                done
            fi
        else
            print_warn "$event_file does not exist"
        fi
    done
else
    print_error "/mnt/hot/events directory does not exist"
fi

# ============================================================================
# 5. CONTAINER FILE VISIBILITY
# ============================================================================
print_header "5. CONTAINER FILE VISIBILITY"

print_section "Sonarr (TV)"
if sudo podman ps --filter "name=sonarr" --format "{{.Names}}" | grep -q "sonarr"; then
    visible=$(sudo podman exec sonarr ls /downloads/tv 2>/dev/null | wc -l || echo "0")
    if [[ $visible -gt 0 ]]; then
        print_ok "Can see $visible items in /downloads/tv"
        if $VERBOSE; then
            echo -e "    ${BLUE}Sample files:${NC}"
            sudo podman exec sonarr ls /downloads/tv 2>/dev/null | head -3 | while read -r line; do
                echo -e "      - $line"
            done
        fi
    else
        print_error "Cannot see any files in /downloads/tv (bind mount issue?)"
    fi
else
    print_warn "Container not running, skipping check"
fi

print_section "Radarr (Movies)"
if sudo podman ps --filter "name=radarr" --format "{{.Names}}" | grep -q "radarr"; then
    visible=$(sudo podman exec radarr ls /downloads/movies 2>/dev/null | wc -l || echo "0")
    if [[ $visible -gt 0 ]]; then
        print_ok "Can see $visible items in /downloads/movies"
        if $VERBOSE; then
            echo -e "    ${BLUE}Sample files:${NC}"
            sudo podman exec radarr ls /downloads/movies 2>/dev/null | head -3 | while read -r line; do
                echo -e "      - $line"
            done
        fi
    else
        print_error "Cannot see any files in /downloads/movies (bind mount issue?)"
    fi
else
    print_warn "Container not running, skipping check"
fi

print_section "Lidarr (Music)"
if sudo podman ps --filter "name=lidarr" --format "{{.Names}}" | grep -q "lidarr"; then
    visible=$(sudo podman exec lidarr ls /downloads/music 2>/dev/null | wc -l || echo "0")
    if [[ $visible -gt 0 ]]; then
        print_ok "Can see $visible items in /downloads/music"
        if $VERBOSE; then
            echo -e "    ${BLUE}Sample files:${NC}"
            sudo podman exec lidarr ls /downloads/music 2>/dev/null | head -3 | while read -r line; do
                echo -e "      - $line"
            done
        fi
    else
        print_error "Cannot see any files in /downloads/music (bind mount issue?)"
    fi
else
    print_warn "Container not running, skipping check"
fi

# ============================================================================
# 6. PERMISSIONS CHECK
# ============================================================================
print_header "6. PERMISSIONS CHECK"

print_section "Download Directory Ownership"
if [[ -d /mnt/hot/downloads/tv ]]; then
    tv_owner=$(stat -c '%U:%G' /mnt/hot/downloads/tv)
    print_info "TV downloads: $tv_owner"
fi
if [[ -d /mnt/hot/downloads/movies ]]; then
    movie_owner=$(stat -c '%U:%G' /mnt/hot/downloads/movies)
    print_info "Movie downloads: $movie_owner"
fi
if [[ -d /mnt/hot/downloads/music ]]; then
    music_owner=$(stat -c '%U:%G' /mnt/hot/downloads/music)
    print_info "Music downloads: $music_owner"
fi

print_section "Sample File Ownership"
if $VERBOSE; then
    if [[ -d /mnt/hot/downloads/tv ]]; then
        echo -e "  ${BLUE}TV shows (first 3):${NC}"
        find /mnt/hot/downloads/tv -maxdepth 1 -mindepth 1 -type d | head -3 | while read -r dir; do
            owner=$(stat -c '%U:%G' "$dir")
            echo -e "    $(basename "$dir"): $owner"
        done
    fi

    if [[ -d /mnt/hot/downloads/music ]]; then
        echo -e "  ${BLUE}Music albums (first 3):${NC}"
        find /mnt/hot/downloads/music -maxdepth 1 -mindepth 1 -type d | head -3 | while read -r dir; do
            owner=$(stat -c '%U:%G' "$dir")
            echo -e "    $(basename "$dir"): $owner"
        done
    fi
fi

# ============================================================================
# 7. SERVICE LOGS (RECENT ERRORS)
# ============================================================================
print_header "7. SERVICE LOGS (RECENT ACTIVITY)"

print_section "Media Orchestrator"
if systemctl is-active --quiet media-orchestrator.service; then
    log_lines=$(journalctl -u media-orchestrator.service -n 10 --no-pager 2>/dev/null | wc -l)
    if [[ $log_lines -gt 0 ]]; then
        print_ok "Log available (showing last 5 lines)"
        journalctl -u media-orchestrator.service -n 5 --no-pager | tail -5 | while read -r line; do
            echo -e "    ${NC}$line${NC}"
        done
    else
        print_warn "No recent logs (journal rotated?)"
    fi
else
    print_warn "Service not active, skipping logs"
fi

print_section "Sonarr Container"
if sudo podman ps --filter "name=sonarr" --format "{{.Names}}" | grep -q "sonarr"; then
    errors=$(sudo podman logs sonarr 2>&1 | grep -i "error\|warn" | tail -5 || true)
    if [[ -n "$errors" ]]; then
        print_warn "Recent errors/warnings found:"
        echo "$errors" | while read -r line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
    else
        print_ok "No recent errors in logs"
    fi
fi

print_section "Radarr Container"
if sudo podman ps --filter "name=radarr" --format "{{.Names}}" | grep -q "radarr"; then
    errors=$(sudo podman logs radarr 2>&1 | grep -i "error\|warn" | tail -5 || true)
    if [[ -n "$errors" ]]; then
        print_warn "Recent errors/warnings found:"
        echo "$errors" | while read -r line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
    else
        print_ok "No recent errors in logs"
    fi
fi

print_section "Lidarr Container"
if sudo podman ps --filter "name=lidarr" --format "{{.Names}}" | grep -q "lidarr"; then
    errors=$(sudo podman logs lidarr 2>&1 | grep -i "error\|warn" | tail -5 || true)
    if [[ -n "$errors" ]]; then
        print_warn "Recent errors/warnings found:"
        echo "$errors" | while read -r line; do
            echo -e "    ${YELLOW}$line${NC}"
        done
    else
        print_ok "No recent errors in logs"
    fi
fi

# ============================================================================
# 8. CONFIGURATION SOURCES
# ============================================================================
print_header "8. CONFIGURATION SOURCES"

print_section "NixOS Module Locations"
print_info "Media Orchestrator: domains/server/orchestration/media-orchestrator.nix"
print_info "Orchestrator Script: workspace/hooks/media-orchestrator.py"
print_info "qBittorrent Hook: workspace/hooks/qbt-finished.sh"
print_info "SABnzbd Hook: workspace/hooks/sab-finished.py"
print_info "Sonarr Module: domains/server/containers/sonarr/"
print_info "Radarr Module: domains/server/containers/radarr/"
print_info "Lidarr Module: domains/server/containers/lidarr/"
print_info "Path Config: domains/system/core/paths.nix"
print_info "Storage Cleanup: domains/server/storage/options.nix"

print_section "Active Configuration"
print_info "Hostname: $(hostname)"
print_info "Hot Storage: /mnt/hot ($(df -h /mnt/hot 2>/dev/null | awk 'NR==2 {print $2}' || echo 'N/A'))"
print_info "Media Storage: /mnt/media ($(df -h /mnt/media 2>/dev/null | awk 'NR==2 {print $2}' || echo 'N/A'))"
print_info "System User: eric"
print_info "Container Runtime: podman"

# ============================================================================
# 9. AUTOMATION SCRIPTS
# ============================================================================
print_header "9. AUTOMATION SCRIPTS"

print_section "Installed Scripts"
if [[ -d /opt/downloads/scripts ]]; then
    print_ok "/opt/downloads/scripts exists"
    if [[ -f /opt/downloads/scripts/qbt-finished.sh ]]; then
        print_ok "qbt-finished.sh (qBittorrent hook)"
    else
        print_warn "qbt-finished.sh missing"
    fi

    if [[ -f /opt/downloads/scripts/sab-finished.py ]]; then
        print_ok "sab-finished.py (SABnzbd hook)"
    else
        print_warn "sab-finished.py missing"
    fi

    if [[ -f /opt/downloads/scripts/media-orchestrator.py ]]; then
        print_ok "media-orchestrator.py (main daemon)"
    else
        print_warn "media-orchestrator.py missing"
    fi
else
    print_error "/opt/downloads/scripts does not exist"
fi

# ============================================================================
# 10. SYSTEMD TIMERS
# ============================================================================
print_header "10. SYSTEMD TIMERS"

print_section "Active Timers (Related to Media)"
systemctl list-timers --no-pager | grep -i "storage\|cleanup\|media" || print_info "No media-related timers found"

# ============================================================================
# 11. NETWORK STATUS
# ============================================================================
print_header "11. NETWORK STATUS"

print_section "Container Networks"
if command -v podman &> /dev/null; then
    print_info "Available networks:"
    sudo podman network ls --format "  - {{.Name}} ({{.Driver}})"
fi

print_section "Service Endpoints"
print_info "Sonarr: http://localhost:8989"
print_info "Radarr: http://localhost:7878"
print_info "Lidarr: http://localhost:8686"
print_info "Prowlarr: http://localhost:9696"
print_info "qBittorrent: http://localhost:8080"
print_info "SABnzbd: http://localhost:8085"
print_info "Jellyfin: http://localhost:8096"

# ============================================================================
# SUMMARY
# ============================================================================
print_header "SUMMARY"

echo -e "\n${BOLD}Pipeline Status:${NC}"

# Count services
total_services=0
active_services=0
for svc in media-orchestrator podman-sonarr podman-radarr podman-lidarr podman-qbittorrent podman-sabnzbd podman-slskd; do
    ((total_services++)) || true
    if systemctl is-active --quiet "${svc}.service" 2>/dev/null; then
        ((active_services++)) || true
    fi
done

# Count containers
total_containers=0
running_containers=0
for ctr in sonarr radarr lidarr qbittorrent sabnzbd slskd jellyfin; do
    ((total_containers++)) || true
    if sudo podman ps --filter "name=$ctr" --format "{{.Names}}" | grep -q "$ctr"; then
        ((running_containers++)) || true
    fi
done

echo -e "  Services: ${GREEN}${active_services}${NC}/${total_services} active"
echo -e "  Containers: ${GREEN}${running_containers}${NC}/${total_containers} running"

if [[ -d /mnt/hot/downloads ]]; then
    pending_tv=$(count_files "/mnt/hot/downloads/tv" 1)
    pending_movies=$(count_files "/mnt/hot/downloads/movies" 1)
    pending_music=$(count_files "/mnt/hot/downloads/music" 1)
    echo -e "  Pending Downloads: ${YELLOW}${pending_tv}${NC} TV, ${YELLOW}${pending_movies}${NC} movies, ${YELLOW}${pending_music}${NC} music"
fi

if [[ -d /mnt/media ]]; then
    lib_tv=$(count_files "/mnt/media/tv" 1)
    lib_movies=$(count_files "/mnt/media/movies" 1)
    lib_music=$(count_files "/mnt/media/music" 1)
    echo -e "  Media Library: ${GREEN}${lib_tv}${NC} TV shows, ${GREEN}${lib_movies}${NC} movies, ${GREEN}${lib_music}${NC} albums"
fi

echo -e "\n${BOLD}Quick Actions:${NC}"
echo -e "  - View logs: ${CYAN}journalctl -u media-orchestrator -f${NC}"
echo -e "  - Restart containers: ${CYAN}sudo systemctl restart podman-sonarr podman-radarr podman-lidarr${NC}"
echo -e "  - Check Sonarr UI: ${CYAN}http://localhost:8989${NC}"
echo -e "  - Check Radarr UI: ${CYAN}http://localhost:7878${NC}"
echo -e "  - Check Lidarr UI: ${CYAN}http://localhost:8686${NC}"

echo -e "\n${BOLD}${GREEN}Status check complete!${NC}\n"
