#!/usr/bin/env bash
# Immich GPU Validation Script
# Checks if Immich ML is properly using CUDA acceleration
# Usage: ./immich-gpu-check.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "================================================================"
echo "           Immich GPU Configuration Validation"
echo "================================================================"
echo ""

# Check 1: NVIDIA driver and GPU availability
echo -e "${BLUE}[1/7] Checking NVIDIA driver and GPU...${NC}"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    echo -e "${GREEN}✓ NVIDIA driver loaded${NC}"
else
    echo -e "${RED}✗ nvidia-smi not found - NVIDIA driver may not be loaded${NC}"
    exit 1
fi
echo ""

# Check 2: NVIDIA kernel modules
echo -e "${BLUE}[2/7] Checking NVIDIA kernel modules...${NC}"
REQUIRED_MODULES=("nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")
for module in "${REQUIRED_MODULES[@]}"; do
    if lsmod | grep -q "^${module}"; then
        echo -e "${GREEN}✓ ${module} loaded${NC}"
    else
        echo -e "${RED}✗ ${module} NOT loaded${NC}"
    fi
done
echo ""

# Check 3: nvidia-container-toolkit CDI generator
echo -e "${BLUE}[3/7] Checking nvidia-container-toolkit-cdi-generator...${NC}"
if systemctl is-active --quiet nvidia-container-toolkit-cdi-generator.service; then
    echo -e "${GREEN}✓ nvidia-container-toolkit-cdi-generator.service is active${NC}"
else
    echo -e "${YELLOW}⚠ nvidia-container-toolkit-cdi-generator.service is NOT active${NC}"
    echo "  This may cause race conditions on service startup"
fi
echo ""

# Check 4: Immich services status
echo -e "${BLUE}[4/7] Checking Immich services status...${NC}"
for service in immich-server immich-machine-learning; do
    if systemctl is-active --quiet "${service}"; then
        echo -e "${GREEN}✓ ${service}.service is active${NC}"
    else
        echo -e "${RED}✗ ${service}.service is NOT active${NC}"
        systemctl status "${service}" --no-pager -l || true
    fi
done
echo ""

# Check 5: ONNX Runtime provider from logs
echo -e "${BLUE}[5/7] Checking ONNX Runtime CUDA provider in logs...${NC}"
if journalctl -u immich-machine-learning --no-pager -n 500 | grep -i "onnx\|provider\|cuda" | tail -10; then
    echo -e "${GREEN}✓ Found ONNX/CUDA references in ML service logs${NC}"
else
    echo -e "${YELLOW}⚠ No ONNX/CUDA references found in recent logs${NC}"
fi
echo ""

# Check 6: GPU usage by Immich processes
echo -e "${BLUE}[6/7] Checking GPU memory usage by Immich processes...${NC}"
GPU_PROCESSES=$(nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader 2>/dev/null || echo "")
if [ -n "$GPU_PROCESSES" ]; then
    echo "$GPU_PROCESSES" | while IFS=, read -r pid process memory; do
        if ps -p "$pid" -o comm= 2>/dev/null | grep -qi "immich\|python"; then
            echo -e "${GREEN}✓ Process $process (PID: $pid) using ${memory} GPU memory${NC}"
        fi
    done

    # If no Immich processes found, show all GPU processes
    if ! echo "$GPU_PROCESSES" | grep -qi "immich\|python"; then
        echo -e "${YELLOW}⚠ No Immich processes currently using GPU${NC}"
        echo "Active GPU processes:"
        echo "$GPU_PROCESSES"
    fi
else
    echo -e "${YELLOW}⚠ No GPU compute processes running${NC}"
fi
echo ""

# Check 7: Immich ML features configuration
echo -e "${BLUE}[7/7] Checking Immich ML features via API...${NC}"
ML_FEATURES=$(curl -s http://localhost:2283/api/server-info/features 2>/dev/null | jq -r '.machineLearning // "unavailable"' || echo "unavailable")
if [ "$ML_FEATURES" != "unavailable" ] && [ "$ML_FEATURES" != "null" ]; then
    echo -e "${GREEN}✓ Immich ML features: ${ML_FEATURES}${NC}"
else
    echo -e "${YELLOW}⚠ Unable to query Immich ML features (server may not be fully started)${NC}"
fi
echo ""

# Summary
echo "================================================================"
echo "                       Validation Summary"
echo "================================================================"
echo ""
echo "To monitor GPU usage in real-time, run:"
echo "  watch -n 1 nvidia-smi"
echo ""
echo "To check ML service logs:"
echo "  journalctl -u immich-machine-learning -f"
echo ""
echo "To verify ONNX Runtime is using CUDA:"
echo "  journalctl -u immich-machine-learning | grep -i 'provider\\|onnx\\|cuda'"
echo ""
echo "Expected performance improvement with CUDA:"
echo "  - Smart Search indexing: 2-5x faster"
echo "  - Facial recognition: 2-5x faster"
echo "  - Thumbnail generation: 1.5-3x faster (with hardware encoding)"
echo ""
