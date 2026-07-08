# domains/monitoring/prometheus/parts/alerts.nix
#
# Prometheus Alert Rules - Organized by Severity
# P5 = Critical, P4 = Warning, P3 = Info

{ lib, ... }:

{
  groups = [
    #========================================================================
    # WEBSITE + LEAD PIPELINE (blackbox probes — see prometheus/index.nix)
    #========================================================================
    {
      name = "website_alerts";
      rules = [
        {
          alert = "WebsitePageDown";
          expr = ''probe_success{job="probe-website"} == 0'';
          for = "5m";
          labels = { severity = "P5"; category = "website"; };
          annotations = {
            summary = "Website page down: {{ $labels.instance }}";
            description = "Blackbox probe has failed for 5+ minutes. iheartwoodcraft.com (or this page/asset) is unreachable or not returning 200.";
          };
        }
        {
          alert = "WebhookIngressDown";
          expr = ''probe_success{job="probe-webhook-ingress"} == 0'';
          for = "5m";
          labels = { severity = "P5"; category = "leads"; };
          annotations = {
            summary = "Calculator webhook ingress down: {{ $labels.instance }}";
            description = "CORS preflight through Cloudflare → tunnel → n8n has failed for 5+ minutes. Calculator submissions from site visitors are being LOST right now. Check cloudflared-tunnel and podman-n8n services.";
          };
        }
        {
          alert = "LeadsServiceDown";
          expr = ''probe_success{job="probe-leads-service"} == 0'';
          for = "5m";
          labels = { severity = "P5"; category = "leads"; };
          annotations = {
            summary = "hwc-leads service down or HMAC misbehaving";
            description = "Unsigned POST to 127.0.0.1:11650/leads is not returning 401. Leads reaching n8n cannot be persisted/pushed to JobTread. Check hwc-leads.service.";
          };
        }
        {
          alert = "N8nEngineDown";
          expr = ''probe_success{job="probe-n8n"} == 0'';
          for = "5m";
          labels = { severity = "P5"; category = "leads"; };
          annotations = {
            summary = "n8n engine down";
            description = "n8n /healthz has failed for 5+ minutes — all webhook workflows (calculator leads/appointments and everything else) are dead. Check podman-n8n.service.";
          };
        }
        {
          alert = "CmsApiDown";
          expr = ''probe_success{job="probe-cms"} == 0'';
          for = "10m";
          labels = { severity = "P4"; category = "website"; };
          annotations = {
            summary = "Heartwood CMS API down";
            description = "CMS on :8095 unreachable for 10+ minutes. Site stays up (static on Hostinger) but edits/deploys are blocked. Check heartwood-cms.service.";
          };
        }
        {
          alert = "UmamiDown";
          expr = ''probe_success{job="probe-umami"} == 0'';
          for = "10m";
          labels = { severity = "P4"; category = "website"; };
          annotations = {
            summary = "Umami analytics down: {{ $labels.instance }}";
            description = "Analytics collection is failing — visitor data is being lost (site itself unaffected). Check podman-umami and the stats.iheartwoodcraft.com tunnel route.";
          };
        }
        {
          alert = "WebsiteSSLCertExpiringSoon";
          expr = ''(probe_ssl_earliest_cert_expiry{job=~"probe-website|probe-webhook-ingress"} - time()) < 14 * 86400'';
          for = "1h";
          labels = { severity = "P4"; category = "website"; };
          annotations = {
            summary = "TLS cert expiring soon: {{ $labels.instance }}";
            description = "Certificate expires in {{ $value | humanizeDuration }}.";
          };
        }
        {
          alert = "WebsiteSlowResponse";
          expr = ''avg_over_time(probe_duration_seconds{job="probe-website"}[15m]) > 3'';
          for = "15m";
          labels = { severity = "P3"; category = "website"; };
          annotations = {
            summary = "Website slow: {{ $labels.instance }}";
            description = "Average probe duration over 15m is {{ $value | humanize }}s (threshold 3s).";
          };
        }
      ];
    }

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
        # Covers root AND data volumes (/mnt/*). A full /mnt/media or /mnt/hot
        # is genuinely critical (media + downloads break), so the P5 tier uses
        # the same regex as Moderate/Elevated rather than root-only. (Salvaged
        # from the retired hwc-disk-space-check script, which alerted critical
        # at 95% on every monitored filesystem.)
        {
          alert = "HighDiskUsage";
          expr = ''
            100 - ((node_filesystem_avail_bytes{mountpoint=~"/|/mnt/.*"} * 100) / node_filesystem_size_bytes{mountpoint=~"/|/mnt/.*"}) > 95
          '';
          for = "15m";
          labels = {
            severity = "P5";
            category = "system";
          };
          annotations = {
            summary = "Critical disk usage on {{ $labels.instance }}:{{ $labels.mountpoint }}";
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
        # Threshold is 82%, NOT 75%: root (/) baselines ~77% (its normal used
        # state), so a 75% threshold fired permanently and re-sent to Discord
        # every repeat_interval (4h) with no actionable signal. 82% sits above
        # the baseline and below the Elevated (85%) tier.
        {
          alert = "ModerateDiskUsage";
          expr = ''
            100 - ((node_filesystem_avail_bytes{mountpoint=~"/|/mnt/.*"} * 100) / node_filesystem_size_bytes{mountpoint=~"/|/mnt/.*"}) > 82
          '';
          for = "1h";
          labels = {
            severity = "P3";
            category = "system";
          };
          annotations = {
            summary = "Moderate disk usage on {{ $labels.instance }}:{{ $labels.mountpoint }}";
            description = "Disk usage is {{ $value | humanize }}% (threshold: 82%)";
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

        # persona-daemon - vault reindex hasn't succeeded in over 7 hours
        # Indexer failures silently degrade RAG; this surfaces them.
        # Threshold MUST exceed the daemon's slow-reconcile backstop interval
        # (OnUnitActiveSec = 6h in persona-daemon/index.nix). A quiet vault only
        # reindexes on that backstop, so anything <6h is a guaranteed false
        # positive. 7h = 6h backstop + 1h margin.
        {
          alert = "PersonaDaemonReindexStale";
          expr = ''
            time() - persona_daemon_reindex_last_success_timestamp > 25200
            and persona_daemon_reindex_last_success_timestamp > 0
          '';
          for = "10m";
          labels = {
            severity = "P4";
            category = "persona-daemon";
          };
          annotations = {
            summary = "persona-daemon reindex hasn't succeeded in over 7 hours";
            description = "Last successful reindex was {{ $value | humanizeDuration }} ago (expected ≤6h via the backstop reconcile). RAG over /home/eric/900_vaults/brain may be returning stale chunks.";
          };
        }

        # persona-daemon - chat/embed backend down
        {
          alert = "PersonaDaemonBackendDown";
          expr = "persona_daemon_backend_up == 0";
          for = "5m";
          labels = {
            severity = "P4";
            category = "persona-daemon";
          };
          annotations = {
            summary = "persona-daemon backend {{ $labels.backend }} is down";
            description = "llama-{{ $labels.backend }} hasn't responded to /health probes for 5+ minutes.";
          };
        }
      ];
    }
  ];
}
