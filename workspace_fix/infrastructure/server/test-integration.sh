#!/usr/bin/env bash
# Soularr Configuration Setup Script

echo "🔧 Setting up Soularr configuration..."

# Create the config directory if it doesn't exist
sudo mkdir -p /opt/downloads/soularr

# Create the Soularr config file with correct authentication
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
# Check for new downloads every 5 minutes
check_interval = 300
# Move files after download completes
move_completed = true
# Log level (DEBUG, INFO, WARNING, ERROR)
log_level = INFO

[Logging]
file = /data/soularr.log
level = INFO
EOF

# Set proper ownership
sudo chown eric:users /opt/downloads/soularr/config.ini
sudo chmod 600 /opt/downloads/soularr/config.ini

echo "✅ Soularr config created at /opt/downloads/soularr/config.ini"
echo ""
echo "📋 Configuration Summary:"
echo "  Lidarr URL: http://lidarr:8686"
echo "  Lidarr API Key: 1811b879f56d4997a49a4a543cd7b987"
echo "  SLSKD URL: http://slskd:5030"
echo "  SLSKD Auth: eriqueok:il0wwlm? (session-based)"
echo "  Check Interval: 5 minutes"
echo ""
echo "🔄 Restart Soularr container to apply config:"
echo "  sudo systemctl restart podman-soularr.service"
echo ""
echo "🔍 Monitor Soularr logs:"
echo "  sudo podman logs -f soularr"
