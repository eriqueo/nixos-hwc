# Raspberry Pi 5 RetroPie Debian Optimization Guide

**Status**: Active Production System
**Date**: 2026-02-24
**Device**: Raspberry Pi 5 Model B Rev 1.1 (8GB RAM)
**OS**: Debian 13 (trixie/testing) + RetroPie 4.8.11

---

## Current State Assessment

### What's Working Well
- RetroPie 4.8.11 stable installation
- EmulationStation 2.11.2rp frontend
- Mupen64Plus-next (lr-mupen64plus-next) for N64
- OutFox 0.5.0-pre043 for rhythm games
- Tailscale VPN integration
- ZRAM already configured (50% of RAM)
- Basic system boots and runs games

### Identified Issues & Risks

| Issue | Severity | Current State | Impact |
|-------|----------|---------------|--------|
| CPU governor | Medium | `ondemand` | Frame drops during load ramp-up |
| No overclock | Medium | 2.4GHz default | Leaving performance on table |
| SD card wear | High | No monitoring | Sudden failure risk |
| Audio latency | Medium | Default ALSA | Input lag on rhythm games |
| Controller polling | Low | Default 125Hz | Suboptimal input response |
| EmulationStation bloat | Low | Full install | Slow menu navigation |
| No backup strategy | High | None | ROM/save data loss risk |
| Testing branch risks | Medium | Debian trixie | Potential breakage on updates |

---

## Phase 1: Critical Safety & Stability

### 1.1 SD Card Health Monitoring

**Problem**: SD cards fail without warning. No monitoring = surprise data loss.

```bash
# Install monitoring tools
sudo apt install smartmontools f3

# Check SD card health (if supported)
sudo smartctl -a /dev/mmcblk0

# Create health check script
sudo tee /usr/local/bin/sdcard-health <<'EOF'
#!/bin/bash
# SD Card Health Monitor for RetroPie

LOG="/var/log/sdcard-health.log"
ALERT_THRESHOLD=90

# Check filesystem usage
USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$USAGE" -gt "$ALERT_THRESHOLD" ]; then
    echo "$(date): WARNING - Root filesystem at ${USAGE}%" >> "$LOG"
fi

# Check for filesystem errors (read-only check)
if ! touch /tmp/.sdcard-test 2>/dev/null; then
    echo "$(date): CRITICAL - Filesystem may be read-only!" >> "$LOG"
fi
rm -f /tmp/.sdcard-test

# Log SMART data if available
smartctl -a /dev/mmcblk0 2>/dev/null | grep -E "Wear|Life|Error" >> "$LOG"

echo "$(date): Health check completed" >> "$LOG"
EOF
chmod +x /usr/local/bin/sdcard-health

# Add to cron (daily)
echo "0 6 * * * root /usr/local/bin/sdcard-health" | sudo tee /etc/cron.d/sdcard-health
```

### 1.2 Backup Strategy

**Problem**: No backups = catastrophic on SD failure.

```bash
# Create backup script
sudo tee /usr/local/bin/retropie-backup <<'EOF'
#!/bin/bash
# RetroPie Backup Script - backs up saves and configs

set -euo pipefail

BACKUP_DIR="/home/pi/backups"
DATE=$(date +%Y%m%d)
REMOTE="eric@hwc-server:/mnt/hot/backups/retropie"

mkdir -p "$BACKUP_DIR"

echo "Starting RetroPie backup..."

# Backup RetroArch saves and states
tar czf "$BACKUP_DIR/retroarch-saves-$DATE.tar.gz" \
    /opt/retropie/configs/all/retroarch/saves \
    /opt/retropie/configs/all/retroarch/states \
    2>/dev/null || true

# Backup EmulationStation configs and gamelists
tar czf "$BACKUP_DIR/es-configs-$DATE.tar.gz" \
    /opt/retropie/configs/all/emulationstation \
    /home/pi/.emulationstation \
    2>/dev/null || true

# Backup RetroPie configs
tar czf "$BACKUP_DIR/retropie-configs-$DATE.tar.gz" \
    /opt/retropie/configs \
    2>/dev/null || true

# Backup OutFox data
tar czf "$BACKUP_DIR/outfox-data-$DATE.tar.gz" \
    /home/pi/.project-outfox \
    2>/dev/null || true

# Sync to server via Tailscale
if command -v rsync &>/dev/null && tailscale status &>/dev/null; then
    rsync -avz --delete "$BACKUP_DIR/" "$REMOTE/" || echo "Remote sync failed (non-fatal)"
fi

# Cleanup old local backups (keep 7 days)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR"
EOF
chmod +x /usr/local/bin/retropie-backup

# Weekly backup cron
echo "0 3 * * 0 pi /usr/local/bin/retropie-backup" | sudo tee /etc/cron.d/retropie-backup
```

### 1.3 Pin Critical Packages (Debian Testing Safety)

**Problem**: Debian testing can break things unexpectedly.

```bash
# Pin retropie-related packages to prevent surprise updates
sudo tee /etc/apt/preferences.d/retropie-stability <<'EOF'
# Hold RetroPie packages at current versions
# Manually update with: apt-mark unhold <package> && apt upgrade <package>

Package: retroarch*
Pin: version *
Pin-Priority: 100

Package: libretro*
Pin: version *
Pin-Priority: 100
EOF

# Hold critical packages
sudo apt-mark hold retroarch libretro-*
```

---

## Phase 2: Performance Optimization

### 2.1 CPU Governor & Frequency

**Problem**: `ondemand` governor has latency ramping up to max frequency.

```bash
# Check current governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Set performance governor permanently
sudo tee /etc/systemd/system/cpu-performance.service <<'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now cpu-performance.service
```

### 2.2 Safe Overclock Configuration

**Problem**: Pi 5 runs at 2.4GHz by default; 2.8GHz+ is stable with adequate cooling.

```bash
# Check current frequency
vcgencmd measure_clock arm

# Edit boot config (BACKUP FIRST!)
sudo cp /boot/firmware/config.txt /boot/firmware/config.txt.bak

# Add conservative overclock
sudo tee -a /boot/firmware/config.txt <<'EOF'

# RetroPie Performance Overclock (conservative, requires cooling)
# Remove if system becomes unstable
[pi5]
arm_freq=2800
gpu_freq=950
over_voltage_delta=50000

# Force turbo (no dynamic scaling - gaming use case)
force_turbo=1
EOF

# IMPORTANT: Only apply with adequate cooling (active fan recommended)
# Test with: stress-ng --cpu 4 --timeout 300s
# Monitor with: vcgencmd measure_temp
```

### 2.3 GPU Memory Optimization

```bash
# Increase GPU memory for better emulator performance
sudo tee -a /boot/firmware/config.txt <<'EOF'

# GPU memory allocation
gpu_mem=256
EOF
```

### 2.4 ZRAM Tuning (Already Present - Verify Optimal)

```bash
# Check current ZRAM config
zramctl

# Verify compression algorithm (zstd is best)
cat /sys/block/zram0/comp_algorithm

# If not zstd, reconfigure
sudo tee /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram * 0.5
compression-algorithm = zstd
EOF
```

---

## Phase 3: Input Latency Optimization

### 3.1 Controller Polling Rate

**Problem**: Default USB polling is 125Hz (8ms). Gaming wants 1000Hz (1ms).

```bash
# Check current polling rate
cat /sys/module/usbhid/parameters/mousepoll

# Set 1000Hz polling for USB HID devices
sudo tee /etc/modprobe.d/usbhid.conf <<'EOF'
options usbhid mousepoll=1
EOF

# Apply without reboot
echo 1 | sudo tee /sys/module/usbhid/parameters/mousepoll
```

### 3.2 RetroArch Latency Settings

```bash
# Edit RetroArch config
RETROARCH_CFG="/opt/retropie/configs/all/retroarch.cfg"

# Backup
cp "$RETROARCH_CFG" "$RETROARCH_CFG.bak"

# Apply latency optimizations
cat >> "$RETROARCH_CFG" <<'EOF'

# === LATENCY OPTIMIZATIONS ===
# Frame delay (reduces latency at cost of some CPU overhead)
video_frame_delay = 4
video_frame_delay_auto = true

# Run-ahead (experimental - can reduce latency dramatically but CPU intensive)
# run_ahead_enabled = true
# run_ahead_frames = 1

# VSync settings
video_vsync = true
video_max_swapchain_images = 2

# Threaded video (reduces CPU load, slight latency increase)
video_threaded = false

# Audio sync
audio_sync = true
audio_latency = 64
EOF
```

### 3.3 Audio Latency (Critical for Rhythm Games)

**Problem**: Default ALSA buffer sizes add latency.

```bash
# Create ALSA optimization
sudo tee /etc/asound.conf <<'EOF'
# Low-latency audio configuration for gaming

pcm.!default {
    type plug
    slave.pcm "dmixer"
}

pcm.dmixer {
    type dmix
    ipc_key 1024
    slave {
        pcm "hw:0,0"
        period_time 0
        period_size 256
        buffer_size 1024
        rate 48000
    }
    bindings {
        0 0
        1 1
    }
}

ctl.!default {
    type hw
    card 0
}
EOF

# For OutFox specifically - edit preferences
# ~/.project-outfox/Save/Preferences.ini
# SoundDevice=default
# SoundWriteAhead=512
```

---

## Phase 4: EmulationStation Optimization

### 4.1 Reduce Menu Lag

**Problem**: ES can be slow with large ROM collections and heavy themes.

```bash
# Use a lightweight theme
# Carbon is fast; avoid themes with videos/animations

# Disable video previews if enabled
ES_SETTINGS="/home/pi/.emulationstation/es_settings.cfg"

# Reduce scraper image sizes
# In es_settings.cfg, ensure:
# <int name="ScraperResizeMaxWidth" value="400" />
# <int name="ScraperResizeMaxHeight" value="400" />
```

### 4.2 Gamelist Optimization

```bash
# Clean up gamelists - remove entries for missing ROMs
# This prevents ES from searching for nonexistent files

# Script to validate gamelists
sudo tee /usr/local/bin/es-gamelist-clean <<'EOF'
#!/bin/bash
# Removes gamelist entries for missing ROM files

ROMS_DIR="/home/pi/RetroPie/roms"

for gamelist in "$ROMS_DIR"/*/gamelist.xml; do
    if [ -f "$gamelist" ]; then
        echo "Checking: $gamelist"
        # Use xmllint to validate and clean
        # (Implement actual cleaning logic based on needs)
    fi
done
EOF
chmod +x /usr/local/bin/es-gamelist-clean
```

---

## Phase 5: System Services Optimization

### 5.1 Disable Unnecessary Services

```bash
# List enabled services
systemctl list-unit-files --state=enabled

# Disable services not needed for gaming console use
sudo systemctl disable --now \
    bluetooth.service \          # If not using BT controllers
    cups.service \               # Printing (if installed)
    avahi-daemon.service \       # mDNS (keep if needed for discovery)
    ModemManager.service \       # Modem management
    wpa_supplicant.service       # Only if using ethernet
```

### 5.2 Boot Optimization

```bash
# Analyze boot time
systemd-analyze blame

# Create drop-in to speed up EmulationStation start
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I $TERM
EOF
```

---

## Phase 6: Monitoring & Maintenance

### 6.1 Temperature Monitoring

```bash
# Create temp monitoring script
sudo tee /usr/local/bin/pi-temp-monitor <<'EOF'
#!/bin/bash
# Log temperature, alert if too hot

TEMP=$(vcgencmd measure_temp | grep -oP '\d+\.\d+')
THRESHOLD=80.0

if (( $(echo "$TEMP > $THRESHOLD" | bc -l) )); then
    echo "$(date): WARNING - Temperature ${TEMP}°C exceeds threshold!" >> /var/log/pi-temp.log
fi
EOF
chmod +x /usr/local/bin/pi-temp-monitor

# Run every 5 minutes
echo "*/5 * * * * root /usr/local/bin/pi-temp-monitor" | sudo tee /etc/cron.d/pi-temp
```

### 6.2 Consolidated Status Script

```bash
sudo tee /usr/local/bin/retropie-status <<'EOF'
#!/bin/bash
# RetroPie System Status

echo "=== RetroPie System Status ==="
echo ""

echo "CPU:"
echo "  Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo "  Frequency: $(vcgencmd measure_clock arm | cut -d= -f2 | awk '{printf "%.0f MHz", $1/1000000}')"
echo "  Temperature: $(vcgencmd measure_temp | cut -d= -f2)"
echo ""

echo "Memory:"
free -h | grep -E "^(Mem|Swap)"
echo "  ZRAM: $(zramctl --output NAME,DISKSIZE,DATA,COMPR --noheadings 2>/dev/null || echo 'not configured')"
echo ""

echo "Storage:"
df -h / | tail -1 | awk '{print "  Root: " $3 " used / " $2 " total (" $5 " full)"}'
echo ""

echo "Network:"
echo "  Tailscale: $(tailscale status --json 2>/dev/null | jq -r '.Self.Online // "not running"')"
echo "  IP: $(hostname -I | awk '{print $1}')"
echo ""

echo "Services:"
systemctl is-active emulationstation --quiet && echo "  EmulationStation: running" || echo "  EmulationStation: stopped"
systemctl is-active tailscaled --quiet && echo "  Tailscale: running" || echo "  Tailscale: stopped"
EOF
chmod +x /usr/local/bin/retropie-status
```

---

## Implementation Order

### Immediate (Do Now)
1. **Backup script** - Protect your data first
2. **SD card monitoring** - Early warning of failure
3. **CPU governor** - Free performance, no risk

### Short-term (This Week)
4. **Package pinning** - Prevent surprise breakage
5. **Controller polling** - Better input response
6. **RetroArch latency settings** - Measurable improvement

### Medium-term (When Comfortable)
7. **Audio latency tuning** - Important for OutFox
8. **Overclock** - Only with proper cooling verified
9. **Service optimization** - Marginal gains

### Optional/Advanced
10. **EmulationStation cleanup** - If experiencing menu lag
11. **Boot optimization** - If boot time bothers you

---

## Rollback Procedures

### CPU Governor
```bash
sudo systemctl disable cpu-performance.service
sudo rm /etc/systemd/system/cpu-performance.service
# Reboot to restore default
```

### Overclock
```bash
sudo cp /boot/firmware/config.txt.bak /boot/firmware/config.txt
# Reboot
```

### RetroArch Settings
```bash
cp /opt/retropie/configs/all/retroarch.cfg.bak /opt/retropie/configs/all/retroarch.cfg
```

### Controller Polling
```bash
sudo rm /etc/modprobe.d/usbhid.conf
# Reboot
```

---

## Testing & Validation

### Verify CPU Performance Mode
```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# Should all say "performance"
```

### Verify Overclock Stable
```bash
# Run CPU stress test
stress-ng --cpu 4 --timeout 300s &
watch -n 1 'vcgencmd measure_temp; vcgencmd measure_clock arm'
# Temperature should stay under 80°C with active cooling
```

### Test Input Latency
```bash
# In RetroArch, use the latency test feature:
# Settings > Latency > Run Latency Test
```

### Verify Audio Latency
```bash
# Use OutFox's built-in offset calibration
# Should feel tighter after ALSA optimization
```

---

## Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| Backup verification | Weekly | Check `/home/pi/backups/` |
| Temperature log review | Weekly | `tail /var/log/pi-temp.log` |
| SD card health check | Monthly | `/usr/local/bin/sdcard-health` |
| System updates | Monthly | `sudo apt update && apt list --upgradable` |
| Full system status | As needed | `/usr/local/bin/retropie-status` |

---

## Known Issues & Workarounds

### Issue: Random freezes after overclock
**Cause**: Insufficient cooling or unstable overclock
**Fix**: Reduce `arm_freq` to 2600, verify active cooling working

### Issue: Controller disconnects
**Cause**: USB power management
**Fix**: `echo 'on' | sudo tee /sys/bus/usb/devices/*/power/control`

### Issue: Audio crackle/pops
**Cause**: Buffer underrun
**Fix**: Increase `buffer_size` in `/etc/asound.conf` to 2048

### Issue: EmulationStation crashes on launch
**Cause**: Corrupted gamelist or theme
**Fix**: Rename `~/.emulationstation` and restart; restore configs one by one

---

## Future Considerations

1. **USB SSD Boot** - When SD card shows wear, migrate to USB SSD
2. **NFS ROM Storage** - Stream ROMs from hwc-server to save local space
3. **Netboot** - PXE boot from server for ultimate reliability
4. **NixOS Migration** - Revisit when Pi 5 support matures (see `retropie-nixos-migration.md`)

---

## Quick Reference Commands

```bash
# System status
retropie-status

# Manual backup
retropie-backup

# Check temperature
vcgencmd measure_temp

# Check CPU frequency
vcgencmd measure_clock arm

# Check throttling
vcgencmd get_throttled
# 0x0 = no throttling, good

# Restart EmulationStation
sudo systemctl restart emulationstation

# SSH from hwc (via Tailscale)
ssh pi@retropie
```
