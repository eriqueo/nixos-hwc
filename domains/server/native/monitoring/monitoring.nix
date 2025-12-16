# HWC Charter Module/domains/services/business/monitoring.nix
#
# MONITORING - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.monitoring.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/business/monitoring.nix
#
# USAGE:
#   hwc.services.monitoring.enable = true;
#   # TODO: Add specific usage examples

# modules/services/business/monitoring.nix
# Charter v3 Business Intelligence and Analytics Monitoring
# SOURCE: /etc/nixos/hosts/serv../domains/business-monitoring.nix (lines 1-536)
{ config, lib, pkgs, ... }:

with lib;

let 
  cfg = config.hwc.services.business.monitoring;
  paths = config.hwc.paths;
  networkName = config.hwc.services.media.networking.networkName;
in {
  
  ####################################################################
  # CHARTER V3 OPTIONS
  ####################################################################
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.services.business.monitoring = {
    enable = mkEnableOption "business intelligence and analytics monitoring";
    
    dashboard = {
      enable = mkEnableOption "business analytics dashboard (Streamlit)";
      port = mkOption {
        type = types.port;
        default = 8501;
        description = "Port for the business dashboard";
      };
      image = mkOption {
        type = types.str;
        default = "python:3.11-slim";
        description = "Docker image for the dashboard container";
      };
      autoStart = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to auto-start the dashboard";
      };
    };
    
    metrics = {
      enable = mkEnableOption "business metrics exporter (Prometheus)";
      port = mkOption {
        type = types.port;
        default = 9999;
        description = "Port for the business metrics exporter";
      };
      image = mkOption {
        type = types.str;
        default = "python:3.11-slim";
        description = "Docker image for the metrics container";
      };
      scrapeInterval = mkOption {
        type = types.int;
        default = 300;
        description = "Metrics collection interval in seconds";
      };
      autoStart = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to auto-start the metrics exporter";
      };
    };
    
    analytics = {
      enable = mkEnableOption "advanced business analytics and cost estimation";
      storageAnalysis = mkEnableOption "storage efficiency and cost analysis";
      processingAnalysis = mkEnableOption "processing pipeline efficiency analysis";
      costEstimation = mkEnableOption "infrastructure cost estimation";
    };
    
    networking = {
      useMediaNetwork = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to use the media container network for monitoring containers";
      };
      networkName = mkOption {
        type = types.str;
        default = "hwc-media-network";
        description = "Name of the container network to use";
      };
    };
  };

  ####################################################################
  # CHARTER V3 IMPLEMENTATION
  ####################################################################

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = mkIf cfg.enable {
    
    # Assertions

    #==========================================================================
    # VALIDATION - Assertions and checks
    #==========================================================================
    assertions = [
      {
        assertion = cfg.enable -> config.virtualisation.podman.enable;
        message = "Business monitoring requires Podman to be enabled (virtualisation.podman.enable = true)";
      }
      {
        assertion = (cfg.dashboard.enable || cfg.metrics.enable) -> cfg.networking.useMediaNetwork -> config.hwc.services.media.networking.enable;
        message = "Business monitoring with media network requires media networking to be enabled";
      }
    ];

    ####################################################################
    # MONITORING SETUP SERVICE
    ####################################################################
    systemd.services.business-monitoring-setup = mkIf (cfg.dashboard.enable || cfg.metrics.enable) {
      description = "Setup business monitoring and analytics";
      wantedBy = mkMerge [
        (mkIf cfg.dashboard.enable [ "podman-business-dashboard.service" ])
        (mkIf cfg.metrics.enable [ "podman-business-metrics.service" ])
      ];
      before = mkMerge [
        (mkIf cfg.dashboard.enable [ "podman-business-dashboard.service" ])
        (mkIf cfg.metrics.enable [ "podman-business-metrics.service" ])
      ];
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      script = ''
        # Create business monitoring directory
        mkdir -p ${paths.cache}/monitoring/business
        chown -R eric:users ${paths.cache}/monitoring/business
        
        # Create business metrics exporter
        cat > ${paths.cache}/monitoring/business/business_metrics.py << 'EOF'
#!/usr/bin/env python3
"""
Business Metrics Exporter
Collects business intelligence and analytics metrics
"""

import os
import time
import json
import sqlite3
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from prometheus_client import start_http_server, Gauge, Counter, Histogram, Info
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Business metrics
media_library_size = Gauge('media_library_total_size_bytes', 'Total media library size', ['type'])
media_library_count = Gauge('media_library_total_files', 'Total media files', ['type'])
storage_efficiency = Gauge('storage_efficiency_ratio', 'Storage efficiency ratio', ['tier'])
processing_efficiency = Gauge('processing_efficiency_percent', 'Processing efficiency percentage', ['stage'])

# Business intelligence metrics
data_processing_time = Histogram('data_processing_duration_seconds', 'Data processing duration', ['task'])
api_response_time = Histogram('business_api_response_seconds', 'Business API response time', ['endpoint'])
user_activity = Counter('user_activity_total', 'User activity counter', ['action', 'service'])

# Cost metrics
storage_cost_estimate = Gauge('storage_cost_estimate_monthly', 'Estimated monthly storage cost', ['tier'])
processing_cost_estimate = Gauge('processing_cost_estimate_monthly', 'Estimated monthly processing cost', ['type'])

class BusinessMonitor:
    def __init__(self):
        self.media_paths = {
            'movies': '${paths.media}/movies',
            'tv': '${paths.media}/tv', 
            'music': '${paths.media}/music'
        }
        
        self.hot_paths = {
            'downloads': '${paths.hot}/downloads',
            'cache': '${paths.hot}/cache',
            'processing': '${paths.hot}/processing'
        }
        
    def calculate_library_metrics(self):
        """Calculate media library metrics"""
        try:
            for media_type, path in self.media_paths.items():
                if not os.path.exists(path):
                    continue
                    
                total_size = 0
                total_files = 0
                
                for root, dirs, files in os.walk(path):
                    for file in files:
                        file_path = os.path.join(root, file)
                        try:
                            file_size = os.path.getsize(file_path)
                            total_size += file_size
                            total_files += 1
                        except OSError:
                            continue
                            
                media_library_size.labels(type=media_type).set(total_size)
                media_library_count.labels(type=media_type).set(total_files)
                
                logger.info(f"{media_type}: {total_files} files, {total_size / (1024**3):.2f} GB")
                
        except Exception as e:
            logger.error(f"Error calculating library metrics: {e}")
            
    def calculate_storage_efficiency(self):
        """Calculate storage efficiency metrics"""
        try:
            # Hot storage efficiency (how much is actively being used)
            hot_total = 0
            hot_active = 0
            
            for tier, path in self.hot_paths.items():
                if os.path.exists(path):
                    for root, dirs, files in os.walk(path):
                        for file in files:
                            file_path = os.path.join(root, file)
                            try:
                                file_size = os.path.getsize(file_path)
                                hot_total += file_size
                                
                                # Files modified in last 24 hours are considered "active"
                                mod_time = os.path.getmtime(file_path)
                                if time.time() - mod_time < 86400:  # 24 hours
                                    hot_active += file_size
                            except OSError:
                                continue
                                
            if hot_total > 0:
                efficiency = hot_active / hot_total
                storage_efficiency.labels(tier='hot').set(efficiency)
                
            # Cold storage efficiency (consistency ratio)
            cold_efficiency = 0.95  # Placeholder - could implement file integrity checks
            storage_efficiency.labels(tier='cold').set(cold_efficiency)
            
        except Exception as e:
            logger.error(f"Error calculating storage efficiency: {e}")
            
    def estimate_costs(self):
        """Estimate infrastructure costs"""
        try:
            # Storage cost estimates ($/GB/month)
            hot_storage_cost_per_gb = 0.10  # SSD
            cold_storage_cost_per_gb = 0.02  # HDD
            
            # Calculate hot storage cost
            hot_size_gb = sum(
                sum(os.path.getsize(os.path.join(root, file)) 
                    for root, _, files in os.walk(path) 
                    for file in files if os.path.exists(os.path.join(root, file))
                ) for path in self.hot_paths.values() if os.path.exists(path)
            ) / (1024**3)
            
            # Calculate cold storage cost  
            cold_size_gb = sum(
                sum(os.path.getsize(os.path.join(root, file))
                    for root, _, files in os.walk(path)
                    for file in files if os.path.exists(os.path.join(root, file))
                ) for path in self.media_paths.values() if os.path.exists(path)
            ) / (1024**3)
            
            storage_cost_estimate.labels(tier='hot').set(hot_size_gb * hot_storage_cost_per_gb)
            storage_cost_estimate.labels(tier='cold').set(cold_size_gb * cold_storage_cost_per_gb)
            
            # Processing cost estimates
            processing_cost_estimate.labels(type='transcoding').set(15.0)  # Estimated monthly
            processing_cost_estimate.labels(type='downloading').set(5.0)   # Estimated monthly
            
        except Exception as e:
            logger.error(f"Error estimating costs: {e}")
            
    def analyze_processing_efficiency(self):
        """Analyze processing pipeline efficiency"""
        try:
            # Calculate download-to-import efficiency
            downloads_path = Path('${paths.hot}/downloads')
            imported_count = 0
            total_downloads = 0
            
            if downloads_path.exists():
                # Count files in download folders vs imported files
                for media_type in ['movies', 'tv', 'music']:
                    download_type_path = downloads_path / media_type
                    if download_type_path.exists():
                        download_files = len(list(download_type_path.rglob('*')))
                        total_downloads += download_files
                        
                        # Rough estimate: files modified in media library in last 24h
                        media_path = Path(f'${paths.media}/{media_type}')
                        if media_path.exists():
                            recent_imports = sum(
                                1 for f in media_path.rglob('*') 
                                if f.is_file() and time.time() - f.stat().st_mtime < 86400
                            )
                            imported_count += recent_imports
                            
            if total_downloads > 0:
                efficiency = (imported_count / total_downloads) * 100
                processing_efficiency.labels(stage='import').set(min(efficiency, 100))
            else:
                processing_efficiency.labels(stage='import').set(100)
                
            # Manual processing efficiency (lower is better)
            manual_path = Path('${paths.hot}/manual')
            manual_files = len(list(manual_path.rglob('*'))) if manual_path.exists() else 0
            manual_efficiency = max(0, 100 - (manual_files * 5))  # Penalty for manual files
            processing_efficiency.labels(stage='manual').set(manual_efficiency)
            
        except Exception as e:
            logger.error(f"Error analyzing processing efficiency: {e}")
            
    def run_monitoring_cycle(self):
        """Run one complete business monitoring cycle"""
        logger.info("Running business monitoring cycle...")
        
        self.calculate_library_metrics()
        ${optionalString cfg.analytics.storageAnalysis "self.calculate_storage_efficiency()"}
        ${optionalString cfg.analytics.costEstimation "self.estimate_costs()"}
        ${optionalString cfg.analytics.processingAnalysis "self.analyze_processing_efficiency()"}
        
        logger.info("Business monitoring cycle completed")
        
def main():
    """Main business monitoring loop"""
    logger.info("Starting Business Metrics Monitor")
    
    # Start Prometheus metrics server
    start_http_server(${toString cfg.metrics.port})
    logger.info("Business metrics server started on port ${toString cfg.metrics.port}")
    
    monitor = BusinessMonitor()
    
    while True:
        try:
            monitor.run_monitoring_cycle()
            time.sleep(${toString cfg.metrics.scrapeInterval})
        except KeyboardInterrupt:
            logger.info("Shutting down business monitor...")
            break
        except Exception as e:
            logger.error(f"Business monitoring cycle failed: {e}")
            time.sleep(600)  # Wait longer on error

if __name__ == "__main__":
    main()
EOF

        # Create Streamlit dashboard
        cat > ${paths.cache}/monitoring/business/dashboard.py << 'EOF'
#!/usr/bin/env python3
"""
Business Intelligence Dashboard
Real-time analytics and metrics visualization
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import requests
import time
from datetime import datetime, timedelta

st.set_page_config(
    page_title="Heartwood Craft - Business Intelligence",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for mobile responsiveness
st.markdown("""
<style>
    .reportview-container .main .block-container {
        max-width: 100%;
        padding: 1rem;
    }
    .metric-container {
        background-color: #1e1e1e;
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 0.5rem 0;
    }
    @media (max-width: 768px) {
        .reportview-container .main .block-container {
            padding: 0.5rem;
        }
    }
</style>
""", unsafe_allow_html=True)

def get_prometheus_data(query):
    """Get data from Prometheus"""
    try:
        response = requests.get(
            "http://prometheus:9090/api/v1/query",
            params={"query": query},
            timeout=5
        )
        if response.status_code == 200:
            return response.json()
    except:
        pass
    return {"data": {"result": []}}

def main():
    st.title("🏠 Heartwood Craft - Business Intelligence")
    st.markdown("Real-time monitoring and analytics dashboard")
    
    # Sidebar
    st.sidebar.title("Navigation")
    page = st.sidebar.selectbox("Choose a view", [
        "System Overview", 
        "Media Pipeline", 
        "Storage Analytics", 
        "Performance Metrics",
        "Mobile Status"
    ])
    
    # Auto-refresh option
    auto_refresh = st.sidebar.checkbox("Auto-refresh (30s)")
    if auto_refresh:
        time.sleep(30)
        st.rerun()
    
    if page == "System Overview":
        show_system_overview()
    elif page == "Media Pipeline":
        show_media_pipeline()
    elif page == "Storage Analytics":
        show_storage_analytics()
    elif page == "Performance Metrics":
        show_performance_metrics()
    elif page == "Mobile Status":
        show_mobile_status()

def show_system_overview():
    st.header("System Overview")
    
    col1, col2, col3, col4 = st.columns(4)
    
    # System metrics with fallback values
    with col1:
        cpu_data = get_prometheus_data('100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)')
        cpu_value = float(cpu_data["data"]["result"][0]["value"][1]) if cpu_data["data"]["result"] else 25.0
        st.metric("CPU Usage", f"{cpu_value:.1f}%", delta=None)
        
    with col2:
        mem_data = get_prometheus_data('(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100')
        mem_value = float(mem_data["data"]["result"][0]["value"][1]) if mem_data["data"]["result"] else 45.0
        st.metric("Memory Usage", f"{mem_value:.1f}%", delta=None)
        
    with col3:
        services_data = get_prometheus_data('count(up == 1)')
        services_online = int(float(services_data["data"]["result"][0]["value"][1])) if services_data["data"]["result"] else 12
        st.metric("Services Online", services_online, delta=None)
        
    with col4:
        transcoding_data = get_prometheus_data('jellyfin_active_transcoding')
        transcoding_count = int(float(transcoding_data["data"]["result"][0]["value"][1])) if transcoding_data["data"]["result"] else 0
        st.metric("Active Transcoding", transcoding_count, delta=None)

def show_media_pipeline():
    st.header("Media Pipeline Status")
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.subheader("Download Queues")
        # Mock data for demonstration
        df_queue = pd.DataFrame({
            "Client": ["qBittorrent", "SABnzbd", "SLSKD"],
            "Status": ["Active", "Idle", "Active"],
            "Count": [3, 0, 1]
        })
        st.dataframe(df_queue, use_container_width=True)
    
    with col2:
        st.subheader("Import Rates")
        df_imports = pd.DataFrame({
            "Type": ["Movies", "TV", "Music"],
            "Rate": [2.3, 4.1, 1.8]
        })
        fig = px.bar(df_imports, x="Type", y="Rate", title="Imports per Hour")
        st.plotly_chart(fig, use_container_width=True)

def show_storage_analytics():
    st.header("Storage Analytics")
    
    # Mock storage data for demonstration
    df_storage = pd.DataFrame({
        "Mount": ["Hot Storage", "Cold Storage", "Cache"],
        "Used": [120, 2400, 45]
    })
    
    fig = px.pie(df_storage, values="Used", names="Mount", title="Storage Usage (GB)")
    st.plotly_chart(fig, use_container_width=True)

def show_performance_metrics():
    st.header("Performance Metrics")
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.subheader("GPU Utilization")
        gpu_util = 35.2  # Mock data
        st.metric("GPU Usage", f"{gpu_util:.1f}%", delta=None)
    
    with col2:
        st.subheader("Service Response Times")
        df_response = pd.DataFrame({
            "Service": ["API", "Dashboard", "Metrics"],
            "Response Time": [45, 120, 25]
        })
        fig = px.bar(df_response, x="Service", y="Response Time", title="Response Time (ms)")
        st.plotly_chart(fig, use_container_width=True)

def show_mobile_status():
    st.header("📱 Mobile Status")
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.subheader("System")
        cpu_value = 25.0  # Mock data
        
        if cpu_value < 70:
            st.success(f"CPU: {cpu_value:.1f}% ✅")
        elif cpu_value < 85:
            st.warning(f"CPU: {cpu_value:.1f}% ⚠️")
        else:
            st.error(f"CPU: {cpu_value:.1f}% ❌")
    
    with col2:
        st.subheader("Services")
        services_online = 12  # Mock data
        st.success(f"{services_online} services online ✅")

if __name__ == "__main__":
    main()
EOF

        # Create requirements files
        cat > ${paths.cache}/monitoring/business/requirements.txt << 'EOF'
streamlit==1.28.0
pandas==2.1.0
plotly==5.17.0
requests==2.31.0
prometheus_client==0.18.0
EOF

        # Set permissions
        chown -R eric:users ${paths.cache}/monitoring/business/
      '';
    };

    ####################################################################
    # BUSINESS ANALYTICS DASHBOARD CONTAINER
    ####################################################################
    # Business Dashboard moved to modules/services/business/dashboard.nix
    # hwc.services.business.dashboard.enable = true; # Enable in profiles/

    ####################################################################
    # BUSINESS METRICS EXPORTER CONTAINER
    ####################################################################
    # Business Metrics moved to modules/services/business/metrics.nix
    # hwc.services.business.metrics.enable = true; # Enable in profiles/

    ####################################################################
    # NETWORKING INTEGRATION
    ####################################################################
    # Register business monitoring ports with Charter v3 networking
    hwc.networking.firewall.extraTcpPorts = mkIf config.hwc.networking.enable (
      optional cfg.dashboard.enable cfg.dashboard.port ++
      optional cfg.metrics.enable cfg.metrics.port
    );

    # Allow business monitoring access on Tailscale interface
    networking.firewall.interfaces."tailscale0" = mkIf config.hwc.networking.tailscale.enable {
      allowedTCPPorts = 
        optional cfg.dashboard.enable cfg.dashboard.port ++
        optional cfg.metrics.enable cfg.metrics.port;
    };
  };
}
