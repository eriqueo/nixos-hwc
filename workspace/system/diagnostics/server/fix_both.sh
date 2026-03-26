#!/usr/bin/env bash
# Fix both Soularr and SLSKD configuration issues

echo "🔧 Fixing Soularr and SLSKD Configuration..."
echo "============================================"

# 1. Fix Soularr Configuration
echo "1. Creating Soularr config directory and file..."
sudo mkdir -p /opt/downloads/soularr

# Create Soularr config - note it needs to be in /data inside container
sudo tee /opt/downloads/soularr/config.ini > /dev/null << 'EOF'
[Lidarr]
url = http://lidarr:8686
api_key = 1811b879f56d4997a49a4a543cd7b987
download_dir = /downloads

[Slskd]
url = http://slskd:5030
username = eriqueok
password = il0wwlm?
download_dir = /downloads

[General]
check_interval = 300
move_completed = true
log_level = INFO

[Logging]
file = /data/soularr.log
level = INFO
EOF

sudo chown -R eric:users /opt/downloads/soularr/
sudo chmod 600 /opt/downloads/soularr/config.ini

echo "   ✅ Soularr config created at /opt/downloads/soularr/config.ini"

# 2. Check current volume mappings in Soularr container
echo ""
echo "2. Checking Soularr container volumes..."
sudo podman inspect soularr | grep -A 10 "Mounts" | grep -E "(Source|Destination)"

# 3. Fix SLSKD config by updating the existing file
echo ""
echo "3. Updating SLSKD configuration in container..."

# First, let's see what's in the current config
echo "   Current SLSKD config:"
sudo podman exec slskd cat /app/slskd.yml | head -30

echo ""
echo "   Creating corrected SLSKD config..."

# Create a new config file and copy it to the container
sudo tee /tmp/slskd-fixed.yml > /dev/null << 'EOF'
web:
  port: 5030
  authentication:
    disabled: false
    username: eriqueok
    password: il0wwlm?

soulseek:
  username: eriqueok
  password: il0wwlm?
  description: "Heartwood Craft Music Collection"
  listen_port: 50300

directories:
  downloads: /data/downloads

shares:
  directories:
    - "/data/music"

global:
  download:
    slots: 3
  upload:
    slots: 5
  limits:
    queued:
      files: 50
      megabytes: 5000

logging:
  level: Information
  file: /data/slskd.log

# Disable remote configuration
flags:
  no_logo: true
EOF

# Copy the fixed config to the container
sudo podman cp /tmp/slskd-fixed.yml slskd:/app/slskd.yml
sudo rm /tmp/slskd-fixed.yml

echo "   ✅ SLSKD config updated"

# 4. Show current status and next steps
echo ""
echo "4. Current status check..."

echo "   Soularr config location: /opt/downloads/soularr/config.ini"
echo "   SLSKD config updated in container"

echo ""
echo "🔄 Required restart sequence:"
echo "   1. Restart SLSKD:   sudo systemctl restart podman-slskd.service"
echo "   2. Wait 30 seconds"
echo "   3. Restart Soularr: sudo systemctl restart podman-soularr.service"
echo "   4. Wait 30 seconds"

echo ""
echo "🔍 Verification commands:"
echo "   Check SLSKD:   sudo podman logs slskd --tail 10"
echo "   Check Soularr: sudo podman logs soularr --tail 10"
echo "   Test SLSKD:    curl -I http://homeserver:5030"

echo ""
echo "🌐 Web interfaces:"
echo "   SLSKD:  http://homeserver:5030 (eriqueok:il0wwlm?)"
echo "   Lidarr: http://homeserver:8686"

echo ""
echo "⚠️  Note: If Soularr still can't find config, the volume mapping might need fixing in NixOS config"
echo "   The container expects /data to be mapped to /opt/downloads/soularr"
