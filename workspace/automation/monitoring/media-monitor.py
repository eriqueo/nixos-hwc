#!/usr/bin/env python3
"""
Media Pipeline Monitor
Collects custom metrics for the media processing pipeline
"""

import os
import sys
import time
import json
import psutil
import requests
from pathlib import Path
from datetime import datetime, timedelta
from prometheus_client import start_http_server, Gauge, Counter, Histogram, Info
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
# Storage metrics
hot_storage_usage = Gauge('hot_storage_usage_bytes', 'Hot storage usage in bytes', ['path'])
cold_storage_usage = Gauge('cold_storage_usage_bytes', 'Cold storage usage in bytes', ['path'])
download_queue_size = Gauge('download_queue_size', 'Number of files in download queue', ['client', 'status'])

# Media processing metrics
media_import_rate = Gauge('media_import_rate_per_hour', 'Media imports per hour', ['type'])
failed_imports = Counter('failed_imports_total', 'Total failed imports', ['type', 'reason'])
processing_time = Histogram('media_processing_seconds', 'Time spent processing media', ['type', 'stage'])

# Service health metrics
service_response_time = Gauge('service_response_time_seconds', 'Service response time', ['service'])
service_up = Gauge('service_up', 'Service availability', ['service'])
active_transcoding = Gauge('jellyfin_active_transcoding', 'Number of active transcoding sessions')

# Business metrics
api_requests = Counter('business_api_requests_total', 'Total API requests', ['endpoint', 'method'])
data_processing_jobs = Gauge('data_processing_jobs_active', 'Active data processing jobs', ['type'])

# System info
system_info = Info('system_info', 'System information')

class MediaMonitor:
    def __init__(self):
        self.services = {
            'sonarr': 'http://host.containers.internal:8989',
            'radarr': 'http://host.containers.internal:7878', 
            'lidarr': 'http://host.containers.internal:8686',
            'prowlarr': 'http://host.containers.internal:9696',
            'jellyfin': 'http://host.containers.internal:8096',
            'navidrome': 'http://host.containers.internal:4533',
            'frigate': 'http://host.containers.internal:5000',
            'home-assistant': 'http://host.containers.internal:8123'
        }
        
        self.storage_paths = {
            'hot_downloads': '/hot/downloads',
            'hot_cache': '/hot/cache',
            'hot_processing': '/hot/processing',
            'hot_manual': '/hot/manual',
            'hot_quarantine': '/hot/quarantine',
            'cold_media': '/media',
            'downloads_config': '/downloads'
        }
        
        # Initialize system info
        self.update_system_info()
        
    def update_system_info(self):
        """Update system information metrics"""
        info = {
            'hostname': os.uname().nodename,
            'system': os.uname().sysname,
            'release': os.uname().release,
            'python_version': f"{sys.version_info.major}.{sys.version_info.minor}",
            'psutil_version': '.'.join(map(str, psutil.version_info)),
            'monitor_version': '1.0.0'
        }
        system_info.info(info)
        
    def check_storage_usage(self):
        """Monitor storage usage across hot and cold tiers"""
        try:
            for name, path in self.storage_paths.items():
                if os.path.exists(path):
                    usage = psutil.disk_usage(path)
                    if 'hot' in name:
                        hot_storage_usage.labels(path=name).set(usage.used)
                    else:
                        cold_storage_usage.labels(path=name).set(usage.used)
                        
                    logger.debug(f"Storage {name}: {usage.used / (1024**3):.2f} GB used")
        except Exception as e:
            logger.error(f"Error checking storage usage: {e}")
            
    def count_download_queues(self):
        """Count files in download queues"""
        try:
            # Count torrent downloads
            torrent_path = Path('/hot/downloads/torrents')
            if torrent_path.exists():
                download_queue_size.labels(client='qbittorrent', status='downloading').set(
                    len(list(torrent_path.glob('**/*')))
                )
                
            # Count usenet downloads  
            usenet_path = Path('/hot/downloads/usenet')
            if usenet_path.exists():
                download_queue_size.labels(client='sabnzbd', status='downloading').set(
                    len(list(usenet_path.glob('**/*')))
                )
                
            # Count processing queues
            for media_type in ['music', 'movies', 'tv']:
                processing_path = Path(f'/hot/processing/{media_type}')
                if processing_path.exists():
                    download_queue_size.labels(client='arr', status=f'processing_{media_type}').set(
                        len(list(processing_path.glob('**/*')))
                    )
                    
                manual_path = Path(f'/hot/manual/{media_type}')
                if manual_path.exists():
                    download_queue_size.labels(client='arr', status=f'manual_{media_type}').set(
                        len(list(manual_path.glob('**/*')))
                    )
                    
                quarantine_path = Path(f'/hot/quarantine/{media_type}')
                if quarantine_path.exists():
                    download_queue_size.labels(client='arr', status=f'quarantine_{media_type}').set(
                        len(list(quarantine_path.glob('**/*')))
                    )
                    
        except Exception as e:
            logger.error(f"Error counting download queues: {e}")
            
    def check_service_health(self):
        """Check health of all services"""
        for service_name, base_url in self.services.items():
            try:
                start_time = time.time()
                
                # Different health check endpoints for different services
                if service_name in ['sonarr', 'radarr', 'lidarr']:
                    health_url = f"{base_url}/api/v3/system/status"
                elif service_name == 'prowlarr':
                    health_url = f"{base_url}/api/v1/system/status"
                elif service_name == 'jellyfin':
                    health_url = f"{base_url}/health"
                elif service_name == 'navidrome':
                    health_url = f"{base_url}/ping"
                elif service_name == 'frigate':
                    health_url = f"{base_url}/api/version"
                elif service_name == 'home-assistant':
                    health_url = f"{base_url}/api/"
                else:
                    health_url = base_url
                    
                response = requests.get(health_url, timeout=5)
                response_time = time.time() - start_time
                
                if response.status_code == 200:
                    service_up.labels(service=service_name).set(1)
                    service_response_time.labels(service=service_name).set(response_time)
                else:
                    service_up.labels(service=service_name).set(0)
                    
            except Exception as e:
                logger.warning(f"Service {service_name} health check failed: {e}")
                service_up.labels(service=service_name).set(0)
                service_response_time.labels(service=service_name).set(0)
                
    def analyze_media_imports(self):
        """Analyze media import patterns and rates"""
        try:
            # Check recent imports by looking at file modification times
            for media_type in ['music', 'movies', 'tv']:
                media_path = Path(f'/media/{media_type}')
                if not media_path.exists():
                    continue
                    
                # Count files modified in last hour
                one_hour_ago = datetime.now() - timedelta(hours=1)
                recent_imports = 0
                
                for file_path in media_path.rglob('*'):
                    if file_path.is_file():
                        mod_time = datetime.fromtimestamp(file_path.stat().st_mtime)
                        if mod_time > one_hour_ago:
                            recent_imports += 1
                            
                media_import_rate.labels(type=media_type).set(recent_imports)
                logger.debug(f"Recent {media_type} imports: {recent_imports}")
                
        except Exception as e:
            logger.error(f"Error analyzing media imports: {e}")
            
    def check_jellyfin_activity(self):
        """Check Jellyfin transcoding activity"""
        try:
            # Try to get session info from Jellyfin API
            sessions_url = f"{self.services['jellyfin']}/Sessions"
            response = requests.get(sessions_url, timeout=5)
            
            if response.status_code == 200:
                sessions = response.json()
                transcoding_count = sum(1 for session in sessions if session.get('TranscodingInfo'))
                active_transcoding.set(transcoding_count)
            else:
                active_transcoding.set(0)
                
        except Exception as e:
            logger.debug(f"Jellyfin activity check failed: {e}")
            active_transcoding.set(0)
            
    def monitor_business_services(self):
        """Monitor business intelligence services"""
        try:
            # Check if business API is running
            business_services = [
                ('streamlit', 'http://host.containers.internal:8501'),
            ]
            
            for service_name, url in business_services:
                try:
                    response = requests.get(url, timeout=3)
                    if response.status_code == 200:
                        service_up.labels(service=f'business_{service_name}').set(1)
                    else:
                        service_up.labels(service=f'business_{service_name}').set(0)
                except:
                    service_up.labels(service=f'business_{service_name}').set(0)
                    
        except Exception as e:
            logger.error(f"Error monitoring business services: {e}")
            
    def run_monitoring_cycle(self):
        """Run one complete monitoring cycle"""
        logger.info("Running monitoring cycle...")
        
        self.check_storage_usage()
        self.count_download_queues()
        self.check_service_health()
        self.analyze_media_imports()
        self.check_jellyfin_activity()
        self.monitor_business_services()
        
        logger.info("Monitoring cycle completed")
        
def main():
    """Main monitoring loop"""
    logger.info("Starting Media Pipeline Monitor")
    
    # Start Prometheus metrics server
    start_http_server(8888)
    logger.info("Prometheus metrics server started on port 8888")
    
    monitor = MediaMonitor()
    
    while True:
        try:
            monitor.run_monitoring_cycle()
            time.sleep(30)  # Run every 30 seconds
        except KeyboardInterrupt:
            logger.info("Shutting down monitor...")
            break
        except Exception as e:
            logger.error(f"Monitoring cycle failed: {e}")
            time.sleep(60)  # Wait longer on error

if __name__ == "__main__":
    main()