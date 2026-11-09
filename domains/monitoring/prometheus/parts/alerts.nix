# domains/monitoring/prometheus/parts/alerts.nix
#
# Prometheus Alert Rules - Organized by Severity
# P5 = Critical, P4 = Warning, P3 = Info
#
# Alertmanager inhibition would hide duplicate deliveries while leaving overlapping
# alerts firing. Tier exclusivity belongs in the expressions instead.

{ lib, ... }:

let
  usageRules = { metric, summaryName, descriptionName, target ? "{{ $labels.instance }}", tiers }:
    lib.listToAttrs (lib.imap0 (index: tier: {
      name = tier.name;
      value = {
        alert = tier.name;
        expr = "${metric} > ${toString tier.threshold}"
          + lib.optionalString (index > 0) " <= ${toString (builtins.elemAt tiers (index - 1)).threshold}"
          + "\n";
        for = tier.duration;
        labels = { severity = tier.severity; category = "system"; };
        annotations = {
          summary = "${tier.label} ${summaryName} usage on ${target}";
          description = "${descriptionName} usage is {{ $value | humanize }}% (threshold: ${toString tier.threshold}%)";
        };
      };
    }) tiers);
  cpu = usageRules {
    metric = ''100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
    summaryName = "CPU"; descriptionName = "CPU";
    tiers = [
      { name = "HighCPUUsage"; threshold = 90; duration = "10m"; severity = "P5"; label = "Critical"; }
      { name = "ElevatedCPUUsage"; threshold = 70; duration = "15m"; severity = "P4"; label = "Elevated"; }
    ];
  };
  memory = usageRules {
    metric = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100";
    summaryName = "memory"; descriptionName = "Memory";
    tiers = [
      { name = "HighMemoryUsage"; threshold = 95; duration = "10m"; severity = "P5"; label = "Critical"; }
      { name = "ElevatedMemoryUsage"; threshold = 80; duration = "15m"; severity = "P4"; label = "Elevated"; }
    ];
  };
  disk = usageRules {
    metric = ''100 - ((node_filesystem_avail_bytes{mountpoint=~"/|/mnt/.*"} * 100) / node_filesystem_size_bytes{mountpoint=~"/|/mnt/.*"})'';
    summaryName = "disk"; descriptionName = "Disk";
    target = "{{ $labels.instance }}:{{ $labels.mountpoint }}";
    # Root normally uses about 77%; 82% avoids permanent informational alerts.
    tiers = [
      { name = "HighDiskUsage"; threshold = 95; duration = "15m"; severity = "P5"; label = "Critical"; }
      { name = "ElevatedDiskUsage"; threshold = 85; duration = "30m"; severity = "P4"; label = "Elevated"; }
      { name = "ModerateDiskUsage"; threshold = 82; duration = "1h"; severity = "P3"; label = "Moderate"; }
    ];
  };
in
{
  groups = [
    # WEBSITE + LEAD PIPELINE (blackbox probes — see prometheus/index.nix)
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
          alert = "WebsiteSecurityCheckFailed";
          expr = ''probe_success{job=~"probe-website-security|probe-website-https|probe-report-privacy"} == 0'';
          for = "5m";
          labels = { severity = "P4"; category = "website"; };
          annotations = {
            summary = "Website security check failed: {{ $labels.instance }}";
            description = "A public HTTPS, browser-policy or report-privacy check failed for five minutes. Inspect the probe in Prometheus, then the website Caddy configuration and hwc-crm service on hwc-work.";
          };
        }
        {
          alert = "CrmIntakeDown";
          expr = ''probe_success{job="probe-crm-intake"} == 0'';
          for = "5m";
          labels = { severity = "P5"; category = "leads"; };
          annotations = {
            summary = "CRM lead intake down: {{ $labels.instance }}";
            description = "Public calculator or contact intake has failed its preflight check for five minutes. New submissions may fail. Inspect this probe in Prometheus, then the cloudflared tunnel and hwc-crm services on hwc-work.";
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
          expr = ''(probe_ssl_earliest_cert_expiry{job=~"probe-website|probe-crm-intake"} - time()) < 14 * 86400'';
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
    # P5 - CRITICAL ALERTS
    {
      name = "critical_alerts";
      rules = [
        cpu.HighCPUUsage

        memory.HighMemoryUsage

        # System - Critical disk space
        # Covers root AND data volumes (/mnt/*). A full /mnt/media or /mnt/hot
        # is genuinely critical (media + downloads break), so the P5 tier uses
        # the same regex as Moderate/Elevated rather than root-only. (Salvaged
        # from the retired hwc-disk-space-check script, which alerted critical
        # at 95% on every monitored filesystem.)
        disk.HighDiskUsage

        {
          alert = "ServiceDown";
          expr = ''up{job!="frigate"} == 0'';
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

        # Configured expectations, not recent success, determine which cameras
        # should be online. Long outages must never become false recoveries.
        {
          alert = "FrigateMetricsUnavailable";
          expr = ''up{job="frigate"} == 0 or absent(up{job="frigate"}) or (time() - frigate_service_last_updated_timestamp > 120)'';
          for = "5m";
          keep_firing_for = "5m";
          labels = { severity = "P4"; category = "frigate"; };
          annotations = {
            summary = "Frigate monitoring is unavailable";
            description = "Camera health cannot be checked. Inspect podman-frigate.service and the frigate Prometheus target.";
          };
        }
        {
          alert = "FrigateCameraOffline";
          expr = "(frigate_camera_fps < 1) and on(camera_name) (frigate_camera_expected_fps > 0)";
          for = "5m";
          keep_firing_for = "5m";
          labels = {
            severity = "P4";
            category = "frigate";
          };
          annotations = {
            summary = "Frigate camera {{ $labels.camera_name }} is offline";
            description = "Camera {{ $labels.camera_name }} is not receiving video. Check its power and cable, then inspect Frigate at https://frigate.hwc.iheartwoodcraft.com.";
          };
        }
        {
          alert = "FrigateCameraMetricsMissing";
          expr = ''(frigate_camera_expected_fps > 0 unless on(camera_name) frigate_camera_fps) and on() (up{job="frigate"} == 1)'';
          for = "5m";
          keep_firing_for = "5m";
          labels = { severity = "P4"; category = "frigate"; };
          annotations = {
            summary = "Frigate camera {{ $labels.camera_name }} has no metrics";
            description = "Frigate responds but this configured camera is missing. Inspect its configuration and logs at https://frigate.hwc.iheartwoodcraft.com.";
          };
        }

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
    # P4 - WARNING ALERTS
    {
      name = "warning_alerts";
      rules = [
        cpu.ElevatedCPUUsage

        memory.ElevatedMemoryUsage

        disk.ElevatedDiskUsage

        # Compare with the configured rate; a degraded daily average is not
        # a healthy baseline. Zero frames belong to the offline alert above.
        {
          alert = "FrigateLowFPS";
          expr = "(frigate_camera_fps < on(camera_name) (0.5 * frigate_camera_expected_fps)) and (frigate_camera_fps >= 1)";
          for = "10m";
          labels = {
            severity = "P3";
            category = "frigate";
          };
          annotations = {
            summary = "Frigate camera {{ $labels.camera_name }} has degraded FPS";
            description = "Camera {{ $labels.camera_name }} FPS is {{ $value | humanize }}, below half its configured rate. Inspect the stream and network in Frigate.";
          };
        }

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
    # P3 - INFO ALERTS
    {
      name = "info_alerts";
      rules = [
        disk.ModerateDiskUsage

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
