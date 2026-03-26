#!/usr/bin/env bash
# One-time migration to fix historical PGID=1000 files
# Run after Phase 1+2 changes are deployed
#
# Part of comprehensive permission fix plan (2025-12-11)
# See: /home/eric/.claude/plans/structured-dazzling-backus.md

set -euo pipefail

echo "=== Permission Migration - nixos-hwc ==="
echo "This script fixes files created with incorrect PGID=1000"
echo "After this runs, containers will maintain correct permissions automatically"
echo ""

# Safety check
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Must run as root (use sudo)"
   exit 1
fi

# Confirmation
read -p "Continue with permission migration? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Starting migration..."
echo ""

# Fix /mnt/hot (downloads, processing, events)
if [[ -d /mnt/hot ]]; then
    echo "Fixing /mnt/hot ownership..."
    BEFORE=$(find /mnt/hot -group 1000 2>/dev/null | wc -l)
    echo "  Found $BEFORE files with GID=1000"

    if [[ $BEFORE -gt 0 ]]; then
        find /mnt/hot -group 1000 -exec chown eric:users {} + 2>/dev/null || true
        echo "  ✓ Fixed"
    else
        echo "  ✓ Already correct"
    fi
else
    echo "⚠️  /mnt/hot doesn't exist, skipping"
fi

echo ""

# Fix /mnt/media (media library)
if [[ -d /mnt/media ]]; then
    echo "Fixing /mnt/media ownership..."
    BEFORE=$(find /mnt/media -group 1000 2>/dev/null | wc -l)
    echo "  Found $BEFORE files with GID=1000"

    if [[ $BEFORE -gt 0 ]]; then
        find /mnt/media -group 1000 -exec chown eric:users {} + 2>/dev/null || true
        echo "  ✓ Fixed"
    else
        echo "  ✓ Already correct"
    fi
else
    echo "⚠️  /mnt/media doesn't exist, skipping"
fi

echo ""

# Fix /opt/downloads (container configs)
if [[ -d /opt/downloads ]]; then
    echo "Fixing /opt/downloads ownership..."
    BEFORE=$(find /opt/downloads -group 1000 2>/dev/null | wc -l)
    echo "  Found $BEFORE files with GID=1000"

    if [[ $BEFORE -gt 0 ]]; then
        find /opt/downloads -group 1000 -exec chown eric:users {} + 2>/dev/null || true
        echo "  ✓ Fixed"
    else
        echo "  ✓ Already correct"
    fi
else
    echo "⚠️  /opt/downloads doesn't exist, skipping"
fi

# Verify
echo ""
echo "========================================"
echo "Verification"
echo "========================================"
echo ""

REMAINING_HOT=0
REMAINING_MEDIA=0
REMAINING_OPT=0

if [[ -d /mnt/hot ]]; then
    REMAINING_HOT=$(find /mnt/hot -group 1000 2>/dev/null | wc -l)
fi

if [[ -d /mnt/media ]]; then
    REMAINING_MEDIA=$(find /mnt/media -group 1000 2>/dev/null | wc -l)
fi

if [[ -d /opt/downloads ]]; then
    REMAINING_OPT=$(find /opt/downloads -group 1000 2>/dev/null | wc -l)
fi

TOTAL_REMAINING=$((REMAINING_HOT + REMAINING_MEDIA + REMAINING_OPT))

echo "Remaining GID=1000 files:"
echo "  /mnt/hot:       $REMAINING_HOT"
echo "  /mnt/media:     $REMAINING_MEDIA"
echo "  /opt/downloads: $REMAINING_OPT"
echo "  TOTAL:          $TOTAL_REMAINING"
echo ""

if [[ $TOTAL_REMAINING -eq 0 ]]; then
    echo "✅ SUCCESS: All files migrated to correct GID (100 - users)"
    echo ""
    echo "Next steps:"
    echo "  1. Restart containers: sudo systemctl restart podman-*.service"
    echo "  2. Verify PGID: sudo podman inspect <container> | jq '.[0].Config.Env'"
    echo "  3. Monitor for new GID=1000 files (should be none)"
else
    echo "⚠️  WARNING: $TOTAL_REMAINING files still have GID=1000"
    echo ""
    echo "This may indicate:"
    echo "  - Files created during migration"
    echo "  - Permission issues that need manual review"
    echo "  - Containers not yet restarted"
    echo ""
    echo "To investigate:"
    echo "  find /mnt/hot /mnt/media /opt/downloads -group 1000 2>/dev/null | head -20"
fi

echo ""
echo "Migration complete!"
