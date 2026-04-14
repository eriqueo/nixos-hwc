#!/usr/bin/env bash
#
# GPU Setup Script for Arch Linux
# Detects GPU, installs drivers, configures Docker runtime
#
# Usage:
#   ./setup-gpu.sh [--dry-run]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

log() {
    echo -e "${GREEN}[setup-gpu]${NC} $1"
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

log "GPU Setup for Arch Linux"
[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN MODE"

# Detect GPU
log "Detecting GPU..."

GPU_INFO=$(lspci | grep -i 'vga\|3d\|display' || true)

if [[ -z "$GPU_INFO" ]]; then
    error "No GPU detected"
fi

echo "$GPU_INFO"

# Determine GPU vendor
NVIDIA_DETECTED=false
AMD_DETECTED=false
INTEL_DETECTED=false

if echo "$GPU_INFO" | grep -iq 'nvidia'; then
    NVIDIA_DETECTED=true
    log "NVIDIA GPU detected"
fi

if echo "$GPU_INFO" | grep -iq 'amd\|radeon'; then
    AMD_DETECTED=true
    log "AMD GPU detected"
fi

if echo "$GPU_INFO" | grep -iq 'intel'; then
    INTEL_DETECTED=true
    log "Intel GPU detected"
fi

# NVIDIA Setup
if [[ "$NVIDIA_DETECTED" == "true" ]]; then
    log "Setting up NVIDIA drivers..."

    # Detect NVIDIA GPU generation
    NVIDIA_MODEL=$(lspci | grep -i nvidia | grep -i vga | head -1)
    echo "  Model: $NVIDIA_MODEL"

    # Determine driver version based on GPU generation
    # Reference: https://wiki.archlinux.org/title/NVIDIA
    DRIVER_PACKAGE="nvidia"

    if echo "$NVIDIA_MODEL" | grep -iq 'GeForce GTX 9\|GeForce GTX 10\|Quadro P\|Tesla P'; then
        warn "Pascal generation GPU detected - may need legacy driver"
        warn "For Quadro P1000 (Pascal), nvidia package should work"
        warn "If issues occur, try: nvidia-470xx-dkms from AUR"
    fi

    # Install NVIDIA driver
    info "Installing NVIDIA driver package: $DRIVER_PACKAGE"
    exec_or_print sudo pacman -S --needed --noconfirm "$DRIVER_PACKAGE" nvidia-utils nvidia-settings

    # Install container runtime support
    info "Installing NVIDIA container toolkit..."
    if command -v yay &>/dev/null; then
        exec_or_print yay -S --needed --noconfirm nvidia-container-toolkit
    else
        warn "yay not found, nvidia-container-toolkit must be installed from AUR manually"
        echo "  Install with: git clone https://aur.archlinux.org/nvidia-container-toolkit.git && cd nvidia-container-toolkit && makepkg -si"
    fi

    # Configure Docker runtime
    if command -v nvidia-ctk &>/dev/null || [[ "$DRY_RUN" == "true" ]]; then
        info "Configuring Docker runtime for NVIDIA..."
        exec_or_print sudo nvidia-ctk runtime configure --runtime=docker
        exec_or_print sudo systemctl restart docker
    else
        warn "nvidia-ctk not found, skipping Docker runtime configuration"
    fi

    # Load kernel modules
    info "Loading NVIDIA kernel modules..."
    exec_or_print sudo modprobe nvidia
    exec_or_print sudo modprobe nvidia_uvm

    # Make kernel modules load on boot
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "nvidia" | sudo tee /etc/modules-load.d/nvidia.conf >/dev/null
        echo "nvidia_uvm" | sudo tee -a /etc/modules-load.d/nvidia.conf >/dev/null
    fi

fi

# AMD Setup
if [[ "$AMD_DETECTED" == "true" ]]; then
    log "Setting up AMD drivers..."

    # AMD drivers are built into Linux kernel (amdgpu)
    info "AMD GPU uses open-source amdgpu driver (already in kernel)"

    # Install Vulkan and OpenCL support
    info "Installing AMD GPU libraries..."
    exec_or_print sudo pacman -S --needed --noconfirm mesa vulkan-radeon libva-mesa-driver

    # ROCm for compute workloads (optional but useful for AI/transcoding)
    warn "For GPU compute (AI, transcoding), consider installing ROCm from AUR:"
    echo "  yay -S rocm-opencl-runtime"

fi

# Intel Setup
if [[ "$INTEL_DETECTED" == "true" ]]; then
    log "Setting up Intel drivers..."

    # Intel integrated graphics (already in kernel)
    info "Intel GPU uses open-source i915 driver (already in kernel)"

    # Install Vulkan and VA-API support
    info "Installing Intel GPU libraries..."
    exec_or_print sudo pacman -S --needed --noconfirm mesa vulkan-intel intel-media-driver

fi

# User group setup (all GPU types)
log "Configuring user groups for GPU access..."

CURRENT_USER=$(whoami)

# Add user to video and render groups
info "Adding $CURRENT_USER to video and render groups..."
exec_or_print sudo usermod -aG video "$CURRENT_USER"
exec_or_print sudo usermod -aG render "$CURRENT_USER"

# Check if docker group exists and add user
if getent group docker >/dev/null; then
    info "Adding $CURRENT_USER to docker group..."
    exec_or_print sudo usermod -aG docker "$CURRENT_USER"
else
    warn "docker group not found - Docker may not be installed"
fi

# Verification commands
log "GPU setup complete!"
echo ""
echo "========================================="
echo "VERIFICATION COMMANDS"
echo "========================================="
echo ""

if [[ "$NVIDIA_DETECTED" == "true" ]]; then
    echo "1. Verify NVIDIA driver:"
    echo "   nvidia-smi"
    echo ""
    echo "2. Test GPU in Docker:"
    echo "   docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi"
    echo ""
    echo "3. Check kernel modules:"
    echo "   lsmod | grep nvidia"
    echo ""
fi

if [[ "$AMD_DETECTED" == "true" ]]; then
    echo "1. Verify AMD GPU:"
    echo "   lspci -k | grep -EA3 'VGA|3D|Display'"
    echo ""
    echo "2. Check DRI devices:"
    echo "   ls -la /dev/dri/"
    echo ""
    echo "3. Test VA-API:"
    echo "   vainfo"
    echo ""
fi

if [[ "$INTEL_DETECTED" == "true" ]]; then
    echo "1. Verify Intel GPU:"
    echo "   lspci -k | grep -EA3 'VGA|3D|Display'"
    echo ""
    echo "2. Check DRI devices:"
    echo "   ls -la /dev/dri/"
    echo ""
    echo "3. Test VA-API:"
    echo "   vainfo"
    echo ""
fi

echo "4. Test Docker GPU access (all types):"
echo "   docker run --rm --device=/dev/dri:/dev/dri ubuntu ls -la /dev/dri"
echo ""
echo "5. Verify user groups:"
echo "   groups $CURRENT_USER"
echo ""

echo "========================================="
echo "IMPORTANT NOTES"
echo "========================================="
echo ""
warn "You must LOG OUT and LOG BACK IN for group changes to take effect!"
echo ""

if [[ "$NVIDIA_DETECTED" == "true" ]]; then
    echo "NVIDIA-specific notes:"
    echo "  - Reboot recommended after driver installation"
    echo "  - For GPU compute in containers, use: --gpus all"
    echo "  - For specific GPU, use: --gpus device=0"
    echo ""
fi

echo "For containers needing GPU access:"
echo "  - Add to docker-compose.yml:"
echo "    devices:"
echo "      - /dev/dri:/dev/dri  # For Intel/AMD"
echo "    # OR for NVIDIA:"
echo "    deploy:"
echo "      resources:"
echo "        reservations:"
echo "          devices:"
echo "            - driver: nvidia"
echo "              count: all"
echo "              capabilities: [gpu]"
echo ""

log "Setup complete. Run verification commands above to test."
