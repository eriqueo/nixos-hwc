# NixOS Backup System

A comprehensive backup solution for NixOS that supports local backups (external drives, NAS, DAS) and cloud backups (Proton Drive) with automatic scheduling, rotation, and restoration.

## Features

- **Local Backups**: Incremental backups using rsync with hard-link snapshots
- **Cloud Backups**: Sync to Proton Drive or other rclone-supported providers
- **Automatic Scheduling**: Systemd timers with configurable frequency
- **Rotating Snapshots**: Daily, weekly, and monthly backup retention
- **Easy Restoration**: Simple CLI tools to restore files from any snapshot
- **Health Monitoring**: Automatic health checks and notifications
- **Space Management**: Automatic cleanup and space verification

## Quick Start

### 1. Enable the Backup System

The backup system is already enabled in `profiles/system.nix`. To activate it on your machine, edit your machine's config file:

**For Laptop** (`machines/laptop/config.nix`):
```nix
hwc.system.services.backup = {
  enable = true;
  local.enable = true;
  schedule.enable = true;
};
```

**For Server** (`machines/server/config.nix`):
```nix
hwc.system.services.backup = {
  enable = true;
  local.enable = true;
  schedule.enable = true;
};
```

### 2. Mount Your Backup Destination

Before backups can run, you need to mount your backup destination at the configured mount point (default: `/mnt/backup`).

#### For External Drive:
```bash
# Create mount point
sudo mkdir -p /mnt/backup

# Mount the drive (replace /dev/sdX1 with your drive)
sudo mount /dev/sdX1 /mnt/backup

# For automatic mounting, add to hardware.nix:
fileSystems."/mnt/backup" = {
  device = "/dev/disk/by-uuid/YOUR-UUID-HERE";
  fsType = "ext4";
  options = [ "nofail" ];  # Don't fail boot if drive isn't connected
};
```

#### For NAS (NFS):
```bash
# Mount NFS share
sudo mount -t nfs nas-server:/backups /mnt/backup

# For automatic mounting, add to hardware.nix:
fileSystems."/mnt/backup" = {
  device = "nas-server:/backups";
  fsType = "nfs";
  options = [ "nofail" "x-systemd.automount" ];
};
```

#### For NAS (SMB/CIFS):
```bash
# Mount SMB/CIFS share
sudo mount -t cifs //nas-server/backups /mnt/backup -o username=user,password=pass

# For automatic mounting, add to hardware.nix:
fileSystems."/mnt/backup" = {
  device = "//nas-server/backups";
  fsType = "cifs";
  options = [ "nofail" "x-systemd.automount" "credentials=/etc/nixos/smb-credentials" ];
};
```

### 3. Rebuild Your System
```bash
sudo nixos-rebuild switch
```

## Usage

### Manual Backup

Run a backup immediately:
```bash
sudo backup-now
```

### Check Backup Status

View backup system status and recent backups:
```bash
sudo backup-status
```

### Restore Files

List available backup snapshots:
```bash
sudo backup-restore --list
```

Restore a specific file from the latest backup:
```bash
sudo backup-restore latest /home/user/Documents/important.txt /tmp/restored.txt
```

Restore from a specific snapshot:
```bash
sudo backup-restore daily/2025-01-15_02-00-00 /home/user/.config /tmp/restored-config
```

### Verify Backup

Check the integrity of the latest backup:
```bash
sudo backup-verify
```

## Configuration

### Local Backup Options

```nix
hwc.system.services.backup.local = {
  enable = true;
  mountPoint = "/mnt/backup";  # Where your backup drive is mounted
  useRsync = true;             # Use incremental backups (recommended)

  # Retention policy
  keepDaily = 7;     # Keep 7 daily backups
  keepWeekly = 4;    # Keep 4 weekly backups (Sundays)
  keepMonthly = 6;   # Keep 6 monthly backups (1st of month)

  minSpaceGB = 10;   # Minimum free space required

  # What to backup
  sources = [
    "/home"
    "/etc/nixos"
  ];

  # What to exclude
  excludePatterns = [
    ".cache"
    "*.tmp"
    ".local/share/Trash"
    "node_modules"
    "__pycache__"
  ];
};
```

### Cloud Backup Options

```nix
hwc.system.services.backup.cloud = {
  enable = true;
  provider = "proton-drive";
  remotePath = "Backups";
  syncMode = "sync";  # sync, copy, or move
  bandwidthLimit = "10M";  # Optional bandwidth limit
};

hwc.system.services.backup.protonDrive = {
  enable = true;
  secretName = "rclone-proton-config";  # agenix secret
};
```

### Scheduling Options

```nix
hwc.system.services.backup.schedule = {
  enable = true;
  frequency = "daily";      # daily, weekly, or systemd calendar format
  timeOfDay = "02:00";      # When to run (HH:MM)
  randomDelay = "1h";       # Random delay to spread load
  onlyOnAC = true;          # Only run when on AC power (laptops)
};
```

### Notification Options

```nix
hwc.system.services.backup.notifications = {
  enable = true;
  onSuccess = false;  # Notify on successful backup
  onFailure = true;   # Notify on backup failure
};
```

## Backup Structure

Backups are organized by type and date:

```
/mnt/backup/
└── hostname/
    ├── daily/
    │   ├── 2025-01-15_02-00-00/
    │   ├── 2025-01-16_02-00-00/
    │   └── ...
    ├── weekly/
    │   ├── 2025-01-07_02-00-00/
    │   ├── 2025-01-14_02-00-00/
    │   └── ...
    ├── monthly/
    │   ├── 2025-01-01_02-00-00/
    │   └── ...
    └── latest -> daily/2025-01-16_02-00-00/
```

Each backup is a full snapshot, but uses hard links to save space (only changed files take up additional space).

## Logs

Backup logs are stored in `/var/log/backup/`:
- `backup-local.log` - Local backup operations
- `backup-cloud.log` - Cloud backup operations
- `backup-coordinator.log` - Overall backup coordination
- `backup-health.log` - Health check results

View recent logs:
```bash
sudo journalctl -u backup.service
sudo journalctl -u backup-local.service
sudo journalctl -u backup-cloud.service
```

## Systemd Services

The backup system consists of several systemd services:

- `backup.timer` - Main backup timer (coordinates all backups)
- `backup.service` - Backup coordinator
- `backup-local.service` - Local backup service
- `backup-cloud.service` - Cloud backup service
- `backup-health-check.timer` - Weekly health checks
- `backup-health-check.service` - Health check service

Check service status:
```bash
systemctl status backup.timer
systemctl status backup-local.service
systemctl list-timers backup*
```

## Troubleshooting

### Backup fails with "destination not mounted"

Make sure your backup destination is mounted at the configured mount point:
```bash
sudo mountpoint /mnt/backup
```

### Backup fails with "insufficient space"

Check available space on your backup destination:
```bash
df -h /mnt/backup
```

Adjust `minSpaceGB` or clean up old backups manually.

### Cloud backup fails with "connection failed"

Check your rclone configuration:
```bash
sudo rclone --config=/etc/rclone-proton.conf lsd proton:
```

### View detailed error logs

```bash
sudo journalctl -u backup-local.service -n 100 --no-pager
sudo tail -f /var/log/backup/backup-local.log
```

## Advanced Configuration

### Pre/Post Backup Scripts

Run custom scripts before or after backups:

```nix
hwc.system.services.backup = {
  preBackupScript = ''
    echo "Starting backup at $(date)"
    # Add your custom pre-backup tasks here
  '';

  postBackupScript = ''
    echo "Backup completed at $(date)"
    # Add your custom post-backup tasks here
  '';
};
```

### Custom Systemd Calendar Format

For more complex scheduling, use systemd calendar format:

```nix
hwc.system.services.backup.schedule = {
  frequency = "Mon,Wed,Fri";  # Monday, Wednesday, Friday
  # Or: "weekly"
  # Or: "2025-*-1/2"  # Every other day
  # See: man systemd.time
};
```

## Security Considerations

1. **Encryption**: Consider encrypting your backup drive
2. **Access Control**: Backup scripts run as root for full access
3. **Network Security**: Use encrypted protocols (NFS with Kerberos, or CIFS with encryption)
4. **Cloud Secrets**: Proton Drive credentials stored in agenix secrets

## Backup Best Practices

1. **3-2-1 Rule**: 3 copies, 2 different media, 1 offsite
   - Original data
   - Local backup (external drive/NAS)
   - Cloud backup (offsite)

2. **Test Restores**: Regularly test restoring files to verify backups work

3. **Monitor Health**: Check `backup-status` regularly

4. **Offsite Backups**: Enable cloud backup for critical data

5. **Verify Space**: Ensure sufficient space on backup destinations

## Example Configurations

### Laptop with External Drive
```nix
hwc.system.services.backup = {
  enable = true;
  local = {
    enable = true;
    mountPoint = "/mnt/backup";
    keepDaily = 7;
    keepWeekly = 4;
    keepMonthly = 3;
  };
  schedule = {
    enable = true;
    frequency = "daily";
    timeOfDay = "02:00";
    onlyOnAC = true;  # Only when plugged in
  };
};
```

### Server with NAS
```nix
hwc.system.services.backup = {
  enable = true;
  local = {
    enable = true;
    mountPoint = "/mnt/nas-backup";
    keepDaily = 14;
    keepWeekly = 8;
    keepMonthly = 12;
    sources = [
      "/home"
      "/etc/nixos"
      "/mnt/media"
      "/opt/business"
    ];
  };
  schedule = {
    enable = true;
    frequency = "weekly";
    timeOfDay = "03:00";
  };
};
```

### Dual Backup (Local + Cloud)
```nix
hwc.system.services.backup = {
  enable = true;

  local = {
    enable = true;
    mountPoint = "/mnt/backup";
    keepDaily = 7;
  };

  cloud = {
    enable = true;
    provider = "proton-drive";
  };

  protonDrive.enable = true;

  schedule = {
    enable = true;
    frequency = "daily";
    timeOfDay = "02:00";
  };
};
```

## Support

For issues or questions:
- Check logs: `/var/log/backup/`
- Run diagnostics: `backup-status`
- View systemd status: `systemctl status backup.service`
