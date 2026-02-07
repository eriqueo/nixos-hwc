# HWC-XPS Deployment Guide

**Machine**: Dell XPS 2018
**Target Configuration**: hwc-xps (remote backup server with desktop environment)
**Last Updated**: 2026-01-21
**Prerequisites**: Machine already running NixOS with git repo access

---

## Overview

This guide walks through transitioning an existing NixOS installation on the Dell XPS to use the new `hwc-xps` flake configuration. The hwc-xps configuration provides:

- **Hybrid laptop/server functionality**: Desktop environment for local use, server services for remote operation
- **Active-active redundancy**: Same services as hwc-server for geographic failover
- **Conservative thermal profile**: Optimized for 24/7 laptop operation

---

## Pre-Deployment Checklist

Before starting, verify:

- [ ] You're on the Dell XPS 2018 machine
- [ ] NixOS is already installed and running
- [ ] Git repo is cloned at `~/.nixos` (or known location)
- [ ] You have `sudo` access
- [ ] Current configuration is backed up
- [ ] You have network access (for nix build downloads)

---

## Phase 1: Safety & Backup

### 1.1 Check Current System State

```bash
# Check hostname
hostname

# Check current NixOS generation
nixos-rebuild list-generations | tail -5

# Check disk layout
lsblk -f

# Check current mounts
df -h

# Save current configuration location
readlink -f /etc/nixos/configuration.nix
```

**Record these values** - you'll need them if you need to roll back.

### 1.2 Backup Current Configuration

```bash
# Create backup directory
mkdir -p ~/nixos-backup-$(date +%Y%m%d)

# Backup current system configuration
sudo cp -r /etc/nixos ~/nixos-backup-$(date +%Y%m%d)/

# Backup current generation
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system > ~/nixos-backup-$(date +%Y%m%d)/generations.txt

# Note current generation number
ls -la /nix/var/nix/profiles/system | grep "system-.*-link"
```

**Write down the current generation number** - you can rollback with:
```bash
sudo nixos-rebuild switch --rollback
# or
sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch
```

---

## Phase 2: Update Repository

### 2.1 Pull Latest Configuration

```bash
cd ~/.nixos  # Or wherever your repo is

# Check current branch and status
git status
git branch

# Pull latest changes (includes hwc-xps configuration at commit b09e4e3)
git pull origin main

# Verify hwc-xps configuration exists
ls -la machines/xps/
```

**Expected files**:
- `machines/xps/config.nix` - Main configuration
- `machines/xps/hardware.nix` - Hardware template (needs updating)
- `machines/xps/DEPLOYMENT.md` - This file

### 2.2 Verify Flake Recognizes hwc-xps

```bash
# List available configurations
nix flake show

# Should see hwc-xps in nixosConfigurations
```

---

## Phase 3: Hardware Configuration

### 3.1 Generate Actual Hardware Config

```bash
# Generate hardware configuration for this machine
sudo nixos-generate-config --show-hardware-config > /tmp/hardware-detected.nix

# Review the generated config
cat /tmp/hardware-detected.nix
```

**Key items to extract**:
- `boot.initrd.availableKernelModules` - Kernel modules needed
- `fileSystems."/"` - Root filesystem UUID
- `fileSystems."/boot"` - Boot partition UUID
- Any other detected filesystems

### 3.2 Get Current Disk UUIDs

```bash
# Show all disk UUIDs
lsblk -f

# Or more detailed:
sudo blkid
```

**Record these UUIDs**:
- Root filesystem (`/`): `_________________`
- Boot partition (`/boot`): `_________________`
- Hot storage (`/mnt/hot` if exists): `_________________`
- Media storage (`/mnt/media` if exists): `_________________`
- Backup storage (`/mnt/backup` if exists): `_________________`

### 3.3 Update machines/xps/hardware.nix

Open `machines/xps/hardware.nix` and update:

```nix
# Replace PLACEHOLDER-ROOT-UUID with actual root UUID
fileSystems."/" = {
  device = "/dev/disk/by-uuid/YOUR-ACTUAL-ROOT-UUID";
  fsType = "ext4";
};

# Replace PLACEHOLDER-BOOT-UUID with actual boot UUID
fileSystems."/boot" = {
  device = "/dev/disk/by-uuid/YOUR-ACTUAL-BOOT-UUID";
  fsType = "vfat";
  options = [ "fmask=0022" "dmask=0022" ];
};

# Update kernel modules from detected config
boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
```

**If you DON'T have /mnt/hot, /mnt/media, /mnt/backup set up yet**:
- Comment out or remove those filesystem definitions in `hardware.nix`
- Comment out the corresponding lines in `config.nix` (search for `/mnt/hot`, `/mnt/media`, `/mnt/backup`)
- You can set these up later after the initial switch

### 3.4 Update machines/xps/config.nix UUIDs

Search for `PLACEHOLDER` in `machines/xps/config.nix` and update:

```nix
# Line 56: Hot storage configuration
hwc.infrastructure.storage.hot = {
  enable = true;  # Set to false if you don't have /mnt/hot yet
  device = "/dev/disk/by-uuid/YOUR-HOT-UUID";  # Update if you have it
  fsType = "ext4";
};

# Lines 84-87: Media storage mount
# If you don't have this set up, comment out this entire block
fileSystems."/mnt/media" = {
  device = "/dev/disk/by-label/media";  # Or update with actual UUID
  fsType = "ext4";
};

# Lines 89-93: Backup storage mount
# If you don't have this set up, comment out this entire block
fileSystems."/mnt/backup" = {
  device = "/dev/disk/by-label/backup";  # Or update with actual UUID
  fsType = "ext4";
};
```

**Important**: If you don't have external DAS connected yet, disable these storage options for now. You can enable them later when you attach the drives.

---

## Phase 4: Secrets Management

### 4.1 Check for Existing Age Key

```bash
# Check if age key exists
sudo ls -la /etc/age/keys.txt
```

**If key exists**:
- You're good to go
- The key should already be in `domains/secrets/parts/secrets.nix`

**If key does NOT exist**:

```bash
# Generate new age key
sudo mkdir -p /etc/age
sudo age-keygen -o /etc/age/keys.txt
sudo chmod 600 /etc/age/keys.txt

# Get public key
sudo age-keygen -y /etc/age/keys.txt
```

**Copy the public key output**, then:

```bash
# On development machine (hwc-laptop), add the public key to secrets
# Edit domains/secrets/parts/secrets.nix and add hwc-xps public key to publicKeys list
# Re-encrypt secrets:
cd ~/.nixos
# ... update secrets.nix ...
git add domains/secrets/
git commit -m "secrets: add hwc-xps age public key"
git push

# Back on hwc-xps, pull the updated secrets:
git pull
```

---

## Phase 5: Pre-Flight Validation

### 5.1 Run Flake Check

```bash
cd ~/.nixos

# Validate the flake
nix flake check

# Should see hwc-xps pass validation
```

**Expected output**:
```
checking NixOS configuration 'nixosConfigurations.hwc-xps'...
evaluation warning: AI Model Router enabled...
evaluation warning: AI Profile: laptop (GPU: nvidia, RAM: 8GB)
```

**No errors should appear for hwc-xps**.

### 5.2 Test Build (Don't Switch Yet)

```bash
# Build the configuration without switching
sudo nixos-rebuild build --flake .#hwc-xps

# This will download packages and build the system
# Can take 10-30 minutes depending on what needs to be built
```

**If build fails**:
- Check error messages carefully
- Verify UUIDs are correct
- Ensure all placeholder values are replaced
- Check that storage paths you don't have are commented out

**If build succeeds**:
- A new system profile will be created at `/nix/var/nix/profiles/system-<N>-link`
- You're ready to switch!

---

## Phase 6: Switch to hwc-xps Configuration

### 6.1 Final Checks

Before switching, verify:

- [ ] Build succeeded (`nixos-rebuild build --flake .#hwc-xps`)
- [ ] UUIDs are correct (checked with `lsblk -f`)
- [ ] Age key exists (`sudo ls /etc/age/keys.txt`)
- [ ] Backup of current config exists (`ls ~/nixos-backup-*`)
- [ ] Current generation number recorded (for rollback if needed)

### 6.2 Switch to New Configuration

```bash
# Switch to hwc-xps configuration
sudo nixos-rebuild switch --flake .#hwc-xps
```

**What happens**:
1. System will rebuild (may take a few minutes since we already built)
2. Services will restart
3. Display manager (greetd) will start if not already running
4. System hostname will change to `hwc-xps`
5. You may need to log out/in to see desktop environment changes

### 6.3 Post-Switch Verification

```bash
# Check hostname
hostname
# Should show: hwc-xps

# Check active generation
nixos-rebuild list-generations | tail -3

# Check services are running
sudo systemctl status ollama
sudo systemctl status caddy
sudo systemctl status greetd

# Check desktop environment (if logged in locally)
echo $XDG_CURRENT_DESKTOP
# Should show: Hyprland

# Check Tailscale
sudo tailscale status
```

---

## Phase 7: Post-Deployment Configuration

### 7.1 Update Tailscale Hostname

```bash
# Reconnect Tailscale with new hostname
sudo tailscale up --hostname=hwc-xps

# Verify connection
sudo tailscale status
```

### 7.2 Verify Storage Mounts

```bash
# Check all expected mounts
df -h

# Should see (if configured):
# /           - Root filesystem
# /boot       - EFI boot
# /mnt/hot    - Hot storage (if DAS connected)
# /mnt/media  - Media storage (if DAS connected)
# /mnt/backup - Backup storage (if DAS connected)
```

**If storage is missing**:
- External DAS may not be connected yet
- Check `lsblk` to see if drives are detected
- Mount manually and update fstab/config if needed

### 7.3 Test Desktop Environment

**If working locally on the laptop**:

1. Log out (if logged in)
2. You should see greetd/tuigreet login screen
3. Login as `eric`
4. Type `Hyprland` to start desktop
5. Verify:
   - Waybar appears at top
   - SUPER+RETURN opens Kitty terminal
   - SUPER+2 opens Firefox

### 7.4 Test Server Services

```bash
# Check AI services
curl http://localhost:11434/api/tags  # Ollama
curl http://localhost:3001/  # Open WebUI

# Check media services
sudo systemctl status jellyfin
sudo systemctl status navidrome

# Check monitoring
curl http://localhost:9090/  # Prometheus
curl http://localhost:3000/  # Grafana

# Check reverse proxy
sudo systemctl status caddy
```

### 7.5 Test Backup

```bash
# Run manual backup test
sudo systemctl start backup.service

# Check logs
sudo journalctl -u backup.service -f
```

---

## Phase 8: Finalize Setup

### 8.1 Connect External Storage (If Not Already)

**If you have 2x3TB DAS**:

1. Connect DAS to XPS
2. Check detection: `lsblk`
3. Format if needed (DESTROY ALL DATA):
   ```bash
   # CAREFUL: This erases drives!
   sudo mkfs.ext4 -L media /dev/sdX1
   sudo mkfs.ext4 -L backup /dev/sdY1
   ```
4. Get UUIDs: `sudo blkid /dev/sdX1 /dev/sdY1`
5. Update `machines/xps/config.nix` with actual UUIDs
6. Rebuild: `sudo nixos-rebuild switch --flake .#hwc-xps`

### 8.2 Cross-Server Monitoring

**On hwc-server** (home server), add hwc-xps to Prometheus scrape targets:

Edit `domains/server/monitoring/prometheus/parts/config.nix`:
```nix
{
  job_name = "hwc-xps";
  static_configs = [{
    targets = [
      "hwc-xps.YOUR-TAILNET.ts.net:9090"
      "hwc-xps.YOUR-TAILNET.ts.net:9100"
      "hwc-xps.YOUR-TAILNET.ts.net:8080"
    ];
  }];
}
```

**On hwc-xps**, verify it can reach hwc-server:
```bash
ping hwc-server.YOUR-TAILNET.ts.net
curl http://hwc-server.YOUR-TAILNET.ts.net:9090/
```

### 8.3 Test Cross-Server Services

```bash
# From hwc-xps, test access to hwc-server services
curl https://hwc.ocelot-wahoo.ts.net:6443  # hwc-server Jellyfin
curl https://hwc.ocelot-wahoo.ts.net:4443  # hwc-server Grafana

# From hwc-server, test access to hwc-xps services (update domain)
curl https://hwc-xps.YOUR-TAILNET.ts.net:6443  # hwc-xps Jellyfin
curl https://hwc-xps.YOUR-TAILNET.ts.net:4443  # hwc-xps Grafana
```

### 8.4 Update Reverse Proxy Domains

**In `machines/xps/config.nix`**, search for `hwc.ocelot-wahoo.ts.net` and update to your actual Tailscale domain:

```bash
# Find all references
cd ~/.nixos
rg "hwc.ocelot-wahoo.ts.net" machines/xps/

# Update with your actual Tailscale domain
# Then rebuild:
sudo nixos-rebuild switch --flake .#hwc-xps
```

---

## Rollback Procedure

**If something goes wrong**, you can rollback:

### Method 1: Use Previous Generation

```bash
# List generations
nixos-rebuild list-generations

# Rollback to previous
sudo nixos-rebuild switch --rollback

# Or switch to specific generation number
sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch
```

### Method 2: Boot from Previous Generation

1. Reboot the machine
2. At greetd login, press ESC to get to systemd-boot menu
3. Select previous NixOS generation
4. Boot into that generation
5. Make it permanent: `sudo nixos-rebuild switch --rollback`

### Method 3: Restore from Backup

```bash
# Restore configuration from backup
sudo cp -r ~/nixos-backup-YYYYMMDD/nixos/* /etc/nixos/

# Rebuild from restored config
sudo nixos-rebuild switch
```

---

## Troubleshooting

### Issue: Build fails with "file not found" errors

**Cause**: Placeholders not replaced or missing UUIDs

**Fix**:
```bash
# Check for remaining placeholders
rg "PLACEHOLDER" machines/xps/

# Verify UUIDs match reality
lsblk -f
```

### Issue: Services fail to start

**Cause**: Missing secrets or incorrect permissions

**Fix**:
```bash
# Check secrets are decrypted
sudo ls -la /run/agenix/

# Check service logs
sudo journalctl -u <service-name> -n 50
```

### Issue: Desktop environment doesn't start

**Cause**: Display manager or Hyprland not configured

**Fix**:
```bash
# Check greetd status
sudo systemctl status greetd

# Check Hyprland package is installed
which Hyprland

# Try starting Hyprland manually
Hyprland
```

### Issue: Storage not mounting

**Cause**: UUID mismatch or drive not detected

**Fix**:
```bash
# Check actual UUIDs
sudo blkid

# Check hardware detection
lsblk -f

# Try manual mount
sudo mount /dev/sdX1 /mnt/media
```

### Issue: Can't connect to Tailscale

**Cause**: Hostname conflict or authentication needed

**Fix**:
```bash
# Re-authenticate
sudo tailscale up --hostname=hwc-xps

# Check status
sudo tailscale status

# If needed, logout and login again
sudo tailscale logout
sudo tailscale up --hostname=hwc-xps
```

---

## Success Criteria

Your hwc-xps deployment is successful when:

- [ ] System boots to greetd login screen
- [ ] Desktop environment (Hyprland) starts and is functional
- [ ] `hostname` shows `hwc-xps`
- [ ] Tailscale connected with hostname `hwc-xps`
- [ ] All expected storage is mounted (`df -h`)
- [ ] AI services running: `sudo systemctl status ollama`
- [ ] Media services running: `sudo systemctl status jellyfin navidrome`
- [ ] Monitoring accessible: `curl localhost:9090` (Prometheus)
- [ ] Reverse proxy working: `sudo systemctl status caddy`
- [ ] Backup service configured: `sudo systemctl status backup.timer`
- [ ] Can access services via Tailscale URLs
- [ ] SSH access works from remote machines
- [ ] Desktop apps work (Firefox, Kitty, Thunar)

---

## Next Steps After Deployment

1. **Sync Media Libraries** (if desired):
   ```bash
   # From hwc-server, sync to hwc-xps
   rsync -avz --progress /mnt/media/music/ hwc-xps:/mnt/media/music/
   rsync -avz --progress /mnt/media/movies/ hwc-xps:/mnt/media/movies/
   ```

2. **Configure Cross-Server Monitoring**:
   - Add hwc-xps to hwc-server Prometheus
   - Add hwc-server to hwc-xps Prometheus
   - Verify both Grafana dashboards show both servers

3. **Test Failover**:
   - Shut down hwc-server
   - Verify hwc-xps services still accessible
   - Verify hwc-xps can operate independently

4. **Update Documentation**:
   - Document actual hardware configuration
   - Note any deviations from plan
   - Update README with hwc-xps information

---

## Support & References

- **Plan**: `/home/eric/.claude/plans/sprightly-skipping-sprout.md`
- **Charter**: `CHARTER.md` (architecture rules)
- **Server Config**: `machines/server/config.nix` (reference)
- **Commit**: `b09e4e3` (hwc-xps initial configuration)

**For issues**: Check logs with `journalctl` and consult CHARTER.md for architectural guidance.

---

**Good luck with your deployment! 🚀**
