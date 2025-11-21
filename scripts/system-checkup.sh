#!/usr/bin/env bash
#
# HWC System Checkup Script
# Comprehensive health check for hwc-server
#
# Usage: checkup
#

# Remove -e so we don't exit on errors
set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters for summary
ERRORS=0
WARNINGS=0
CHECKS_PASSED=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((CHECKS_PASSED++))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((ERRORS++))
}

print_info() {
    echo -e "${CYAN}   $1${NC}"
}

suggest_fix() {
    echo -e "${YELLOW}   💡 FIX: $1${NC}"
}

# Main checkup functions

check_failed_services() {
    print_header "Failed Services Check"

    local failed_services
    failed_services=$(systemctl --failed --no-pager --no-legend 2>/dev/null || true)
    local failed_count=$(echo "$failed_services" | grep -c "loaded" || echo "0")

    if [[ $failed_count -eq 0 ]]; then
        print_success "No failed services"
    else
        print_error "$failed_count service(s) in failed state:"
        echo ""
        # Show each failed service with details
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                service_name=$(echo "$line" | awk '{print $2}')
                print_info "❌ $line"
                echo ""
                suggest_fix "Check logs: journalctl -u $service_name --since '1 hour ago' -n 30"
                suggest_fix "Try restart: systemctl restart $service_name"
                suggest_fix "Or disable: systemctl disable $service_name"
                echo ""
            fi
        done <<< "$failed_services"
    fi
}

check_critical_services() {
    print_header "Critical Services"

    local services=("caddy.service" "couchdb.service" "transcript-api.service")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            local uptime=$(systemctl show -p ActiveEnterTimestamp "$service" | cut -d= -f2)
            print_success "${service%%.*}: Running (since $uptime)"
        else
            print_error "${service%%.*}: NOT RUNNING"
            suggest_fix "Start: systemctl start $service"
            suggest_fix "Logs: journalctl -u $service -n 50"
            suggest_fix "Status: systemctl status $service"
        fi
    done
}

check_media_services() {
    print_header "Media Services"

    local services=("immich-server.service" "jellyfin.service")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_success "${service%%.*}: Running"
        else
            print_warning "${service%%.*}: Not running (may be disabled)"
            print_info "Enable with: systemctl enable --now $service"
        fi
    done
}

check_containers() {
    print_header "Container Services"

    local running_containers
    running_containers=$(systemctl list-units "podman-*.service" --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l)

    local expected_containers=15

    if [[ $running_containers -ge $expected_containers ]]; then
        print_success "$running_containers containers running"
        # Show running containers in a compact format
        local container_list=$(systemctl list-units 'podman-*.service' --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print $1}' | sed 's/podman-//;s/.service//' | tr '\n' ', ' | sed 's/,$//')
        print_info "Running: $container_list"
    else
        print_warning "$running_containers/$expected_containers containers running"

        # List stopped containers
        local all_containers="gluetun sonarr radarr lidarr prowlarr qbittorrent sabnzbd jellyseerr frigate slskd beets organizr tdarr soularr ollama navidrome"
        echo ""
        print_info "Expected containers not running:"
        for container in $all_containers; do
            if ! systemctl is-active --quiet "podman-$container.service" 2>/dev/null; then
                print_info "  ❌ $container"
                suggest_fix "Start: systemctl start podman-$container.service"
                suggest_fix "Logs: podman logs $container --tail 30"
            fi
        done
    fi
}

check_recent_errors() {
    print_header "Recent Errors (last 10 minutes)"

    local errors
    errors=$(journalctl --since "10 minutes ago" -p err --no-pager --no-hostname 2>/dev/null | grep -v "beets.*error: unknown command 'web'" | grep -v "frigate.*s6-rc" || true)

    if [[ -z "$errors" ]]; then
        print_success "No concerning errors in last 10 minutes"
    else
        local error_count=$(echo "$errors" | wc -l)
        print_warning "Found $error_count error(s) in last 10 minutes"
        echo ""
        print_info "First 10 errors:"
        echo "$errors" | head -10
        echo ""
        if [[ $(echo "$errors" | wc -l) -gt 10 ]]; then
            print_info "... (showing 10 of $error_count total)"
        fi
        suggest_fix "Full logs: journalctl --since '10 minutes ago' -p err | less"
        suggest_fix "Specific service: journalctl -u <service> --since '10 minutes ago'"
    fi
}

check_disk_space() {
    print_header "Disk Space"

    # Check root partition
    local root_usage
    root_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

    if [[ $root_usage -lt 90 ]]; then
        print_success "Root: ${root_usage}% used"
    elif [[ $root_usage -lt 95 ]]; then
        print_warning "Root: ${root_usage}% used (getting full)"
        suggest_fix "Free space: nix-collect-garbage -d"
        suggest_fix "Check Docker: docker system df"
        suggest_fix "Find large: du -sh /* 2>/dev/null | sort -h | tail -10"
    else
        print_error "Root: ${root_usage}% used (CRITICAL!)"
        suggest_fix "URGENT: nix-collect-garbage -d"
        suggest_fix "Remove old generations: nix-env --delete-generations old"
        suggest_fix "Check: du -sh /* 2>/dev/null | sort -h"
    fi

    # Check /mnt/media if exists
    if mountpoint -q /mnt/media 2>/dev/null; then
        local media_usage
        media_usage=$(df -h /mnt/media 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

        if [[ $media_usage -lt 85 ]]; then
            print_success "Media: ${media_usage}% used"
        elif [[ $media_usage -lt 95 ]]; then
            print_warning "Media: ${media_usage}% used (getting full)"
            suggest_fix "Review: du -sh /mnt/media/* 2>/dev/null | sort -h"
        else
            print_error "Media: ${media_usage}% used (CRITICAL!)"
            suggest_fix "Clean media or expand storage"
        fi
    fi

    # Check /mnt/hot if exists
    if mountpoint -q /mnt/hot 2>/dev/null; then
        local hot_usage
        hot_usage=$(df -h /mnt/hot 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

        if [[ $hot_usage -lt 85 ]]; then
            print_success "Hot storage: ${hot_usage}% used"
        else
            print_warning "Hot storage: ${hot_usage}% used"
            suggest_fix "Clean downloads: rm -rf /mnt/hot/downloads/incomplete/*"
        fi
    fi
}

check_memory() {
    print_header "Memory Usage"

    local available_gb
    available_gb=$(free -g 2>/dev/null | awk 'NR==2 {print $7}')
    local total_gb
    total_gb=$(free -g 2>/dev/null | awk 'NR==2 {print $2}')
    local used_gb
    used_gb=$(free -g 2>/dev/null | awk 'NR==2 {print $3}')

    if [[ $available_gb -gt 5 ]]; then
        print_success "Memory: ${used_gb}GB used / ${total_gb}GB total (${available_gb}GB free)"
    elif [[ $available_gb -gt 2 ]]; then
        print_warning "Memory: ${used_gb}GB used / ${total_gb}GB total (${available_gb}GB free - running low)"
        suggest_fix "Top consumers: ps aux --sort=-%mem | head -10"
        suggest_fix "Consider restarting heavy services"
    else
        print_error "Memory: ${used_gb}GB used / ${total_gb}GB total (${available_gb}GB free - CRITICAL!)"
        suggest_fix "URGENT: ps aux --sort=-%mem | head -20"
        suggest_fix "Restart services: systemctl restart immich-server jellyfin"
        suggest_fix "Check for leaks: journalctl -b | grep -i 'out of memory'"
    fi
}

print_summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}           SYSTEM CHECKUP SUMMARY${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "  Checks Passed: ${GREEN}${CHECKS_PASSED}${NC}"
    echo -e "  Warnings:      ${YELLOW}${WARNINGS}${NC}"
    echo -e "  Errors:        ${RED}${ERRORS}${NC}"
    echo ""

    if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "  ${GREEN}OVERALL STATUS: ✅ HEALTHY${NC}"
        echo -e "  No action required."
    elif [[ $ERRORS -eq 0 ]]; then
        echo -e "  ${YELLOW}OVERALL STATUS: ⚠️  MINOR ISSUES${NC}"
        echo -e "  Review warnings above and apply suggested fixes."
    else
        echo -e "  ${RED}OVERALL STATUS: ❌ NEEDS ATTENTION${NC}"
        echo -e "  Address errors above immediately."
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      HWC SYSTEM CHECKUP v1.0                 ║${NC}"
    echo -e "${BLUE}║      $(date '+%Y-%m-%d %H:%M:%S %Z')                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"

    check_failed_services
    check_critical_services
    check_media_services
    check_containers
    check_recent_errors
    check_disk_space
    check_memory

    print_summary

    # Exit code based on errors (but we complete all checks first)
    if [[ $ERRORS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
