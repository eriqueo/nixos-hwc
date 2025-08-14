#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/mnt/backup/nixos-configs"
DATE=$(date +%Y%m%d-%H%M%S)

echo "=== Backing up NixOS configuration ==="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create tarball
tar -czf "$BACKUP_DIR/nixos-config-$DATE.tar.gz" \
    --exclude=result \
    --exclude=.git \
    /etc/nixos

# Keep only last 30 backups
ls -t "$BACKUP_DIR"/nixos-config-*.tar.gz | tail -n +31 | xargs -r rm

echo "✅ Backup saved to $BACKUP_DIR/nixos-config-$DATE.tar.gz"
