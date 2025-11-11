#!/bin/bash
# setup-monitoring.sh
# Setup and deploy monitoring infrastructure

set -e

echo "🔧 Setting up Heartwood Craft monitoring infrastructure..."

# Create monitoring directories
echo "📁 Creating monitoring directories..."
sudo mkdir -p /opt/monitoring/{prometheus,grafana,alertmanager,blackbox,media-monitor,business}
sudo mkdir -p /var/lib/node_exporter/textfile_collector

# Build custom monitoring containers
echo "🐳 Building custom monitoring containers..."

# Build media monitor container
cd /opt/monitoring/media-monitor
sudo podman build -t media-pipeline-monitor:latest .

# Build business dashboard container  
cd /opt/monitoring/business
sudo podman build -t business-dashboard:latest .

# Set proper permissions
echo "🔑 Setting permissions..."
sudo chown -R eric:users /opt/monitoring/
sudo chmod +x /opt/monitoring/media-monitor/media_monitor.py
sudo chmod +x /opt/monitoring/business/dashboard.py
sudo chmod +x /opt/monitoring/business/business_metrics.py

# Create systemd service for monitoring setup
echo "⚙️ Creating monitoring services..."

cat > /tmp/monitoring-health-check.service << 'EOF'
[Unit]
Description=Monitoring Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for i in {1..30}; do curl -s http://localhost:9090/-/healthy && curl -s http://localhost:3000/api/health && exit 0; sleep 10; done; exit 1'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/monitoring-health-check.service /etc/systemd/system/
sudo systemctl daemon-reload

echo "📊 Monitoring infrastructure setup complete!"
echo ""
echo "Next steps:"
echo "1. Run 'sudo nixos-rebuild switch' to deploy the monitoring stack"
echo "2. Access Grafana at http://localhost:3000 (admin/admin123)"
echo "3. Access Prometheus at http://localhost:9090"
echo "4. Access Business Dashboard at http://localhost:8501"
echo ""
echo "Services being monitored:"
echo "- 12 media containers (Sonarr, Radarr, Lidarr, etc.)"
echo "- System metrics (CPU, Memory, Disk, Network)"
echo "- GPU utilization and temperature"
echo "- Storage tiers (hot/cold)"
echo "- Business intelligence metrics"
echo "- Custom media pipeline health"
echo ""
echo "Mobile access: All dashboards are mobile-optimized"
echo "Alerts: Configured for storage, performance, and service issues"