# domains/server/monitoring/prometheus/parts/alerts.nix
#
# Prometheus Alert Rules - Organized by Severity
# P5 = Critical, P4 = Warning, P3 = Info

{ lib, ... }:

{
  groups = [
    #========================================================================
    # P5 - CRITICAL ALERTS
    #========================================================================
    {
      name = "critical_alerts";
      rules = [
        # System - Critical CPU usage
        {
          alert = "HighCPUUsage";
          expr = ''
            100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
          '';
          for = "10m";
          labels = {
            severity = "P5";
            category = "system";
          };
          annotations = {
            summary = "Critical CPU usage on {{ $labels.instance }}";
            description = "CPU usage is {{ $value | humanize }}% (threshold: 90%)";
          };
        }

        # System - Critical memory usage
        {
          alert = "HighMemoryUsage";
          expr = ''
            (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 95
          '';
          for = "10m";
          labels = {
            severity = "P5";
            category = "system";
          };
          annotations = {
            summary = "Critical memory usage on {{ $labels.instance }}";
            description = "Memory usage is {{ $value | humanize }}% (threshold: 95%)";
          };
        }

        # System - Critical disk space
        {
          alert = "HighDiskUsage";
          expr = ''
            100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"}) > 95
          '';
          for = "15m";
          labels = {
            severity = "P5";
            category = "system";
          };
          annotations = {
            summary = "Critical disk usage on {{ $labels.instance }}";
            description = "Disk usage is {{ $value | humanize }}% (threshold: 95%)";
          };
        }

        # Services - Service down
        {
          alert = "ServiceDown";
          expr = "up == 0";
          for = "5m";
          labels = {
            severity = "P5";
            category = "service";
          };
          annotations = {
            summary = "Service {{ $labels.job }} is down";
            description = "{{ $labels.job }} on {{ $labels.instance }} has been down for more than 5 minutes";
          };
        }

        # Frigate - Camera offline
        {
          alert = "FrigateCameraOffline";
          expr = "frigate_camera_fps < 1";
          for = "5m";
          labels = {
            severity = "P5";
            category = "frigate";
          };
          annotations = {
            summary = "Frigate camera {{ $labels.camera }} is offline";
            description = "Camera {{ $labels.camera }} FPS is {{ $value | humanize }} (threshold: < 1)";
          };
        }

        # Immich - High API error rate
        {
          alert = "ImmichHighErrorRate";
          expr = ''
            rate(immich_api_errors_total[5m]) > 10
          '';
          for = "10m";
          labels = {
            severity = "P5";
            category = "immich";
          };
          annotations = {
            summary = "Immich high API error rate";
            description = "API error rate is {{ $value | humanize }} errors/sec (threshold: > 10)";
          };
        }
      ];
    }

    #========================================================================
    # P4 - WARNING ALERTS
    #========================================================================
    {
      name = "warning_alerts";
      rules = [
        # System - Elevated CPU usage
        {
          alert = "ElevatedCPUUsage";
          expr = ''
            100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 70
          '';
          for = "15m";
          labels = {
            severity = "P4";
            category = "system";
          };
          annotations = {
            summary = "Elevated CPU usage on {{ $labels.instance }}";
            description = "CPU usage is {{ $value | humanize }}% (threshold: 70%)";
          };
        }

        # System - Elevated memory usage
        {
          alert = "ElevatedMemoryUsage";
          expr = ''
            (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
          '';
          for = "15m";
          labels = {
            severity = "P4";
            category = "system";
          };
          annotations = {
            summary = "Elevated memory usage on {{ $labels.instance }}";
            description = "Memory usage is {{ $value | humanize }}% (threshold: 80%)";
          };
        }

        # System - Elevated disk usage
        {
          alert = "ElevatedDiskUsage";
          expr = ''
            100 - ((node_filesystem_avail_bytes{mountpoint=~"/|/mnt/.*"} * 100) / node_filesystem_size_bytes{mountpoint=~"/|/mnt/.*"}) > 85
          '';
          for = "30m";
          labels = {
            severity = "P4";
            category = "system";
          };
          annotations = {
            summary = "Elevated disk usage on {{ $labels.instance }}:{{ $labels.mountpoint }}";
            description = "Disk usage is {{ $value | humanize }}% (threshold: 85%)";
          };
        }

        # Frigate - Low camera FPS
        {
          alert = "FrigateLowFPS";
          expr = "frigate_camera_fps < 10";
          for = "10m";
          labels = {
            severity = "P4";
            category = "frigate";
          };
          annotations = {
            summary = "Frigate camera {{ $labels.camera }} has low FPS";
            description = "Camera {{ $labels.camera }} FPS is {{ $value | humanize }} (threshold: < 10)";
          };
        }

        # Frigate - High CPU usage
        {
          alert = "FrigateHighCPU";
          expr = "frigate_cpu_usage_percent > 80";
          for = "15m";
          labels = {
            severity = "P4";
            category = "frigate";
          };
          annotations = {
            summary = "Frigate high CPU usage";
            description = "Frigate CPU usage is {{ $value | humanize }}% (threshold: 80%)";
          };
        }

        # Immich - Large worker queue
        {
          alert = "ImmichLargeQueue";
          expr = "immich_worker_queue_size > 100";
          for = "30m";
          labels = {
            severity = "P4";
            category = "immich";
          };
          annotations = {
            summary = "Immich worker queue {{ $labels.queue }} is large";
            description = "Queue size is {{ $value | humanize }} (threshold: > 100)";
          };
        }

        # Containers - High memory usage
        {
          alert = "ContainerHighMemory";
          expr = "container_memory_usage_bytes{name!=\"\"} > 2000000000";
          for = "20m";
          labels = {
            severity = "P4";
            category = "containers";
          };
          annotations = {
            summary = "Container {{ $labels.name }} using high memory";
            description = "Container memory usage is {{ $value | humanize }} bytes (threshold: > 2GB)";
          };
        }
      ];
    }

    #========================================================================
    # P3 - INFO ALERTS
    #========================================================================
    {
      name = "info_alerts";
      rules = [
        # System - Moderate disk usage
        {
          alert = "ModerateDiskUsage";
          expr = ''
            100 - ((node_filesystem_avail_bytes{mountpoint=~"/|/mnt/.*"} * 100) / node_filesystem_size_bytes{mountpoint=~"/|/mnt/.*"}) > 75
          '';
          for = "1h";
          labels = {
            severity = "P3";
            category = "system";
          };
          annotations = {
            summary = "Moderate disk usage on {{ $labels.instance }}:{{ $labels.mountpoint }}";
            description = "Disk usage is {{ $value | humanize }}% (threshold: 75%)";
          };
        }

        # Frigate - Detection event spike
        {
          alert = "FrigateDetectionSpike";
          expr = "increase(frigate_events_total[1h]) > 50";
          for = "15m";
          labels = {
            severity = "P3";
            category = "frigate";
          };
          annotations = {
            summary = "Frigate detection spike for {{ $labels.camera }}";
            description = "{{ $value | humanize }} events in last hour (threshold: > 50)";
          };
        }

        # Immich - Slow API responses
        {
          alert = "ImmichSlowAPI";
          expr = "histogram_quantile(0.95, rate(immich_api_duration_bucket[5m])) > 2000";
          for = "20m";
          labels = {
            severity = "P3";
            category = "immich";
          };
          annotations = {
            summary = "Immich API p95 latency elevated";
            description = "p95 latency is {{ $value | humanize }}ms (threshold: > 2000ms)";
          };
        }

        # System - High network traffic
        {
          alert = "HighNetworkTraffic";
          expr = ''
            rate(node_network_receive_bytes_total{device!~"lo|veth.*"}[5m]) > 100000000
          '';
          for = "30m";
          labels = {
            severity = "P3";
            category = "system";
          };
          annotations = {
            summary = "High network traffic on {{ $labels.instance }}:{{ $labels.device }}";
            description = "Network RX rate is {{ $value | humanize }} bytes/s (threshold: > 100MB/s)";
          };
        }
      ];
    }
  ];
}
