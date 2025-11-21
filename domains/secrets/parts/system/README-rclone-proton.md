# Rclone Proton Drive Configuration Secret

## Overview
This secret contains the rclone configuration for backing up to Proton Drive.

## Setup Instructions

### 1. Install rclone and configure Proton Drive

```bash
# Install rclone
nix-shell -p rclone

# Configure rclone for Proton Drive interactively
rclone config

# Choose:
# - n) New remote
# - Name: proton
# - Storage: protondrive
# - Follow the prompts to authenticate with Proton
```

### 2. Export the rclone configuration

```bash
# Export the configuration (look for the [proton] section)
cat ~/.config/rclone/rclone.conf

# It should look something like:
# [proton]
# type = protondrive
# username = your-email@proton.me
# password = <encrypted>
# ...
```

### 3. Encrypt the configuration as a secret

```bash
cd /home/eric/.nixos/domains/secrets/parts/system/

# Encrypt the entire rclone config file
age -R /etc/age/keys.txt.pub < ~/.config/rclone/rclone.conf > rclone-proton-config.age

# Verify it was created
ls -la rclone-proton-config.age
```

### 4. Enable backups in your machine configuration

The laptop configuration already has the backup service enabled:

```nix
hwc.system.services.backup = {
  enable = true;
  protonDrive.enable = true;  # Now you can enable this
  monitoring.enable = true;
};
```

### 5. Rebuild and test

```bash
# Rebuild your system
sudo nixos-rebuild switch --flake .#hwc-laptop

# Test the rclone connection
rclone --config /etc/rclone-proton.conf lsd proton:

# Run a test backup
rclone --config /etc/rclone-proton.conf copy /home/eric/Documents proton:backups/documents --progress
```

## Creating Automated Backup Scripts

After enabling the backup service, you can create scripts in `/home/eric/scripts/backup/` for automated backups.

Example daily backup script:

```bash
#!/usr/bin/env bash
# Daily incremental backup to Proton Drive

RCLONE_CONFIG="/etc/rclone-proton.conf"
SOURCE_DIRS=(
  "/home/eric/Documents"
  "/home/eric/Pictures"
  "/home/eric/.config"
  "/home/eric/.nixos"
)

for dir in "${SOURCE_DIRS[@]}"; do
  dirname=$(basename "$dir")
  echo "Backing up $dir to proton:backups/$dirname"
  rclone --config "$RCLONE_CONFIG" sync "$dir" "proton:backups/$dirname" \
    --log-file /var/log/rclone.log \
    --progress \
    --exclude ".cache/**" \
    --exclude "node_modules/**"
done
```

## Troubleshooting

### Permission denied errors
```bash
# Check that the secret was decrypted properly
sudo ls -la /etc/rclone-proton.conf
```

### Connection errors
```bash
# Test the connection
rclone --config /etc/rclone-proton.conf about proton:
```

### Secret doesn't exist
```bash
# Make sure age keys are set up
sudo ls -la /etc/age/keys.txt
```
