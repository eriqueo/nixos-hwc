#!/usr/bin/env bash
# ZFS Pre-Switch Snapshot Guard
# CHARTER v9.0 - Create snapshots before nixos-rebuild switch
#
# Usage: ./workspace/utilities/zfs-pre-switch-snapshot.sh
# Creates dated snapshots of critical ZFS datasets before system changes

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_PREFIX="pre-switch-${TIMESTAMP}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ZFS Pre-Switch Snapshot Guard${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if ZFS is available
if ! command -v zfs &> /dev/null; then
    echo -e "${YELLOW}[SKIP]${NC} ZFS not installed"
    exit 0
fi

# Check if any ZFS pools exist
if ! zpool list &> /dev/null || [[ $(zpool list -H | wc -l) -eq 0 ]]; then
    echo -e "${YELLOW}[SKIP]${NC} No ZFS pools configured"
    exit 0
fi

echo -e "${BLUE}[INFO]${NC} Creating pre-switch snapshots: $SNAPSHOT_PREFIX"
echo ""

# Define critical datasets (adjust based on your setup)
CRITICAL_DATASETS=(
    # Add your critical ZFS datasets here
    # Examples:
    # "backup/postgresql"
    # "backup/vaults"
    # "vmstore/vms"
)

# Auto-detect backup pools if they exist
for pool in $(zpool list -H -o name 2>/dev/null); do
    if [[ "$pool" == "backup" ]] || [[ "$pool" == "vmstore" ]]; then
        # Get all datasets in this pool
        while IFS= read -r dataset; do
            CRITICAL_DATASETS+=("$dataset")
        done < <(zfs list -H -o name -r "$pool" | tail -n +2)  # Skip pool itself
    fi
done

if [[ ${#CRITICAL_DATASETS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}[SKIP]${NC} No critical datasets defined"
    echo "      Edit this script to add datasets, or ZFS is only used for backup pools"
    exit 0
fi

SNAPSHOT_COUNT=0
FAILED_COUNT=0

for dataset in "${CRITICAL_DATASETS[@]}"; do
    SNAPSHOT_NAME="${dataset}@${SNAPSHOT_PREFIX}"

    if zfs list -t snapshot "$SNAPSHOT_NAME" &> /dev/null; then
        echo -e "${YELLOW}[SKIP]${NC} $SNAPSHOT_NAME (already exists)"
        continue
    fi

    if zfs snapshot "$SNAPSHOT_NAME" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Created: $SNAPSHOT_NAME"
        ((SNAPSHOT_COUNT++))
    else
        echo -e "${RED}[FAIL]${NC} Failed to create: $SNAPSHOT_NAME"
        ((FAILED_COUNT++))
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Snapshot Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Created: $SNAPSHOT_COUNT snapshots${NC}"

if [[ $FAILED_COUNT -gt 0 ]]; then
    echo -e "${RED}Failed: $FAILED_COUNT snapshots${NC}"
fi

echo ""
echo "Rollback instructions (if needed):"
echo "  zfs rollback <dataset>@${SNAPSHOT_PREFIX}"
echo ""
echo "Cleanup old snapshots:"
echo "  zfs list -t snapshot | grep pre-switch"
echo "  zfs destroy <dataset>@<snapshot-name>"
echo ""

# List recent pre-switch snapshots for reference
echo "Recent pre-switch snapshots:"
zfs list -t snapshot -o name,creation | grep "pre-switch" | tail -10 || true
echo ""

if [[ $FAILED_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All snapshots created successfully!${NC}"
    echo "Safe to proceed with: nixos-rebuild switch --flake .#hwc-server"
    exit 0
else
    echo -e "${RED}Some snapshots failed! Review errors before proceeding.${NC}"
    exit 1
fi
