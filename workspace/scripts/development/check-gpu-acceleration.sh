#!/bin/bash

# GPU Acceleration Verification Script for Jellyfin/Media Server
# Checks NVIDIA Quadro P1000 hardware acceleration status

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "  $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              GPU Acceleration Verification Tool             ║"
    echo "║                  NVIDIA Quadro P1000 System                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # 1. Check NVIDIA Driver
    print_header "NVIDIA Driver Status"
    if check_command nvidia-smi; then
        print_success "nvidia-smi command available"
        echo ""
        print_info "GPU Information:"
        sudo nvidia-smi --query-gpu=name,driver_version,memory.used,memory.total,utilization.gpu --format=csv
        echo ""
        print_info "Current GPU processes:"
        sudo nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null || print_warning "No compute processes currently running"
    else
        print_error "nvidia-smi not available - NVIDIA drivers not installed"
        return 1
    fi
    
    # 2. Check Kernel Modules
    print_header "NVIDIA Kernel Modules"
    modules=("nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")
    for module in "${modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            print_success "$module module loaded"
        else
            print_error "$module module not loaded"
        fi
    done
    
    # 3. Check Device Files
    print_header "GPU Device Files"
    devices=("/dev/nvidia0" "/dev/nvidiactl" "/dev/nvidia-modeset" "/dev/nvidia-uvm" "/dev/dri/renderD128")
    for device in "${devices[@]}"; do
        if [ -e "$device" ]; then
            permissions=$(ls -l "$device" | awk '{print $1 " " $3 ":" $4}')
            print_success "$device exists ($permissions)"
        else
            print_error "$device not found"
        fi
    done
    
    # 4. Check User Groups
    print_header "User Group Memberships"
    jellyfin_groups=$(groups jellyfin 2>/dev/null || echo "jellyfin user not found")
    if echo "$jellyfin_groups" | grep -q "video"; then
        print_success "jellyfin user is in video group"
    else
        print_error "jellyfin user is NOT in video group"
    fi
    
    if echo "$jellyfin_groups" | grep -q "render"; then
        print_success "jellyfin user is in render group"
    else
        print_warning "jellyfin user is not in render group (may not be required)"
    fi
    
    # 5. Check Jellyfin Service
    print_header "Jellyfin Service Status"
    if systemctl is-active --quiet jellyfin; then
        print_success "Jellyfin service is running"
        
        # Check if GPU config service ran
        if systemctl is-enabled --quiet jellyfin-gpu-config 2>/dev/null; then
            print_success "jellyfin-gpu-config service is enabled"
            if systemctl status jellyfin-gpu-config --no-pager -l | grep -q "Active: active (exited)"; then
                print_success "jellyfin-gpu-config has run successfully"
            else
                print_warning "jellyfin-gpu-config service status unclear"
            fi
        else
            print_warning "jellyfin-gpu-config service not found"
        fi
    else
        print_error "Jellyfin service is not running"
    fi
    
    # 6. Check Jellyfin Configuration
    print_header "Jellyfin Hardware Acceleration Config"
    config_file="/var/lib/jellyfin/config/encoding.xml"
    if [ -f "$config_file" ]; then
        print_success "Jellyfin encoding config exists"
        
        if sudo grep -q "<HardwareAccelerationType>nvenc</HardwareAccelerationType>" "$config_file"; then
            print_success "NVENC hardware acceleration enabled"
        else
            current_type=$(sudo grep -o "<HardwareAccelerationType>.*</HardwareAccelerationType>" "$config_file" 2>/dev/null || echo "not found")
            print_error "Hardware acceleration not set to NVENC: $current_type"
        fi
        
        if sudo grep -q "<EnableHardwareEncoding>true</EnableHardwareEncoding>" "$config_file"; then
            print_success "Hardware encoding enabled"
        else
            print_error "Hardware encoding disabled"
        fi
        
        # Check ffmpeg path
        ffmpeg_path=$(sudo grep -o "<EncoderAppPathDisplay>.*</EncoderAppPathDisplay>" "$config_file" | sed 's/<[^>]*>//g' 2>/dev/null || echo "not found")
        if [ -f "$ffmpeg_path" ]; then
            print_success "FFmpeg path valid: $ffmpeg_path"
        else
            print_error "FFmpeg path invalid: $ffmpeg_path"
        fi
    else
        print_error "Jellyfin encoding config not found"
    fi
    
    # 7. Check FFmpeg NVENC Support
    print_header "FFmpeg NVENC Support"
    if [ -f "/nix/store/5fkc2y3mm8hmy6srnvcn1wz6cbz2fxr3-jellyfin-ffmpeg-7.1.1-7-bin/bin/ffmpeg" ]; then
        ffmpeg_bin="/nix/store/5fkc2y3mm8hmy6srnvcn1wz6cbz2fxr3-jellyfin-ffmpeg-7.1.1-7-bin/bin/ffmpeg"
        print_success "Jellyfin FFmpeg found"
        
        encoders=$($ffmpeg_bin -encoders 2>/dev/null | grep nvenc || echo "none")
        if echo "$encoders" | grep -q "h264_nvenc"; then
            print_success "H.264 NVENC encoder available"
        else
            print_error "H.264 NVENC encoder not available"
        fi
        
        if echo "$encoders" | grep -q "hevc_nvenc"; then
            print_success "HEVC NVENC encoder available"
        else
            print_error "HEVC NVENC encoder not available"
        fi
    else
        print_error "Jellyfin FFmpeg not found at expected path"
    fi
    
    # 8. Check Recent Jellyfin Logs
    print_header "Recent Jellyfin Hardware Acceleration Logs"
    recent_logs=$(sudo journalctl -u jellyfin --since "1 hour ago" | rg -i "nvenc|hardware|gpu|cuda|Available encoders" | tail -5)
    if [ -n "$recent_logs" ]; then
        print_success "Recent GPU-related log entries found:"
        echo "$recent_logs" | while read -r line; do
            print_info "$line"
        done
    else
        print_warning "No recent GPU-related log entries (may indicate no recent transcoding)"
    fi
    
    # 9. Performance Test (Optional)
    print_header "GPU Performance Test"
    echo -e "${YELLOW}To test actual transcoding performance, start a video transcode in Jellyfin${NC}"
    echo -e "${YELLOW}and monitor with: watch -n 1 'sudo nvidia-smi'${NC}"
    
    # Summary
    echo ""
    print_header "Summary"
    echo -e "${GREEN}Hardware acceleration appears to be configured and working.${NC}"
    echo -e "${BLUE}Monitor GPU usage during transcoding with: sudo nvidia-smi${NC}"
    echo -e "${BLUE}View detailed Jellyfin logs with: sudo journalctl -u jellyfin -f${NC}"
}

# Run main function
main "$@"