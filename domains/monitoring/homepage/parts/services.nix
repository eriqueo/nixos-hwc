# Explicit deployment bindings keep dashboard links and widget endpoints in sync.
{ vhostDomain, prometheusHost, prometheusPort, mcpPort, mcpHealthUrl, n8nUrl }:
[
  {
    "Fleet" = [
      {
        "hwc-home" = {
          "icon" = "mdi-server";
          "description" = "Media + storage host";
          "widget" = {
            "type" = "prometheusmetric";
            "url" = "http://host.containers.internal:${toString prometheusPort}";
            "refreshInterval" = 60000;
            "metrics" = [
              {
                "label" = "Root";
                "query" = "100 - 100 * node_filesystem_avail_bytes{host=\"hwc-home\",mountpoint=\"/\"} / node_filesystem_size_bytes{host=\"hwc-home\",mountpoint=\"/\"}";
                "format" = {
                  "type" = "percent";
                };
              }
              {
                "label" = "Hot";
                "query" = "100 - 100 * node_filesystem_avail_bytes{host=\"hwc-home\",mountpoint=\"/mnt/hot\"} / node_filesystem_size_bytes{host=\"hwc-home\",mountpoint=\"/mnt/hot\"}";
                "format" = {
                  "type" = "percent";
                };
              }
              {
                "label" = "Media";
                "query" = "100 - 100 * node_filesystem_avail_bytes{host=\"hwc-home\",mountpoint=\"/mnt/media\"} / node_filesystem_size_bytes{host=\"hwc-home\",mountpoint=\"/mnt/media\"}";
                "format" = {
                  "type" = "percent";
                };
              }
              {
                "label" = "Backup";
                "query" = "100 - 100 * node_filesystem_avail_bytes{host=\"hwc-home\",mountpoint=\"/mnt/backup\"} / node_filesystem_size_bytes{host=\"hwc-home\",mountpoint=\"/mnt/backup\"}";
                "format" = {
                  "type" = "percent";
                };
              }
            ];
          };
        };
      }
      {
        "hwc-work" = {
          "icon" = "mdi-server-network";
          "description" = "Work + development host";
          "widget" = {
            "type" = "prometheusmetric";
            "url" = "http://host.containers.internal:${toString prometheusPort}";
            "refreshInterval" = 60000;
            "metrics" = [
              {
                "label" = "Root";
                "query" = "100 - 100 * node_filesystem_avail_bytes{host=\"hwc-work\",mountpoint=\"/\"} / node_filesystem_size_bytes{host=\"hwc-work\",mountpoint=\"/\"}";
                "format" = {
                  "type" = "percent";
                };
              }
            ];
          };
        };
      }
    ];
  }
  {
    "HWC" = [
      {
        "CRM" = {
          "icon" = "mdi-account-group";
          "href" = "https://crm.${vhostDomain}";
          "description" = "Front-of-funnel CRM (hwc-leads)";
        };
      }
      {
        "Estimator" = {
          "icon" = "mdi-calculator-variant";
          "href" = "https://estimator.${vhostDomain}";
          "description" = "Remodel pricing PWA";
        };
      }
      {
        "Bathroom Calculator" = {
          "icon" = "mdi-calculator";
          "href" = "https://calculator.${vhostDomain}";
          "description" = "Bathroom estimate widget";
        };
      }
      {
        "Heartwood CMS" = {
          "icon" = "mdi-pencil";
          "href" = "https://heartwood-cms.${vhostDomain}";
          "description" = "Content management";
        };
      }
      {
        "Lead Scout" = {
          "icon" = "mdi-radar";
          "href" = "https://lead-scout.${vhostDomain}";
          "description" = "Lead intelligence";
        };
      }
      {
        "Home Scout" = {
          "icon" = "mdi-home-search";
          "href" = "https://home-scout.${vhostDomain}";
          "description" = "Listings on the buying lens";
        };
      }
      {
        "Event Scout" = {
          "icon" = "mdi-calendar-star";
          "href" = "https://event-scout.${vhostDomain}";
          "description" = "Curated Bozeman events";
        };
      }
      {
        "Workbench" = {
          "icon" = "mdi-view-dashboard";
          "href" = "https://workbench.${vhostDomain}";
          "description" = "Area launcher";
        };
      }
      {
        "Morning Briefing" = {
          "icon" = "mdi-sunny";
          "href" = "https://briefing.${vhostDomain}";
          "description" = "Daily ops dashboard";
        };
      }
      {
        "n8n" = {
          "icon" = "n8n";
          "href" = n8nUrl;
          "description" = "Workflow automation";
          "siteMonitor" = n8nUrl;
        };
      }
      {
        "MCP Gateway" = {
          "icon" = "mdi-transit-connection-variant";
          "href" = mcpHealthUrl;
          "description" = "Unified system / JT / n8n / CRM MCP";
          "widget" = {
            "type" = "customapi";
            "url" = "http://host.containers.internal:${toString mcpPort}/health";
            "refreshInterval" = 30000;
            "mappings" = [
              {
                "field" = "status";
                "label" = "Status";
                "format" = "text";
              }
              {
                "field" = "tools";
                "label" = "Tools";
                "format" = "number";
              }
            ];
          };
        };
      }
      {
        "Paperless" = {
          "icon" = "paperless-ngx";
          "href" = "https://paperless.${vhostDomain}";
          "description" = "Document management";
          "siteMonitor" = "https://paperless.${vhostDomain}";
        };
      }
    ];
  }
  {
    "DataX" = [
      {
        "DataX Monitor" = {
          "icon" = "mdi-monitor-dashboard";
          "href" = "https://monitor.${vhostDomain}";
          "description" = "Agent-execution diagnostics";
        };
      }
      {
        "Refinery" = {
          "icon" = "mdi-factory";
          "href" = "https://refinery.${vhostDomain}";
          "description" = "Refinement engine board";
        };
      }
    ];
  }
  {
    "Home" = [
      {
        "Frigate" = {
          "icon" = "frigate";
          "href" = "https://frigate.${vhostDomain}";
          "description" = "NVR / cameras";
          "siteMonitor" = "https://frigate.${vhostDomain}";
        };
      }
      {
        "Immich" = {
          "icon" = "immich";
          "href" = "https://immich.${vhostDomain}";
          "description" = "Photos";
          "siteMonitor" = "https://immich.${vhostDomain}";
        };
      }
      {
        "Cameras" = {
          "icon" = "grafana";
          "href" = "https://grafana.${vhostDomain}/d/cameras";
          "description" = "Frigate FPS / detection / storage (Grafana)";
        };
      }
    ];
  }
  {
    "Media" = [
      {
        "Jellyfin" = {
          "icon" = "jellyfin";
          "href" = "https://jellyfin.${vhostDomain}";
          "description" = "Media server";
        };
      }
      {
        "Jellyseerr" = {
          "icon" = "jellyseerr";
          "href" = "https://jellyseerr.${vhostDomain}";
          "description" = "Media requests";
          "siteMonitor" = "https://jellyseerr.${vhostDomain}";
        };
      }
      {
        "Sonarr" = {
          "icon" = "sonarr";
          "href" = "https://sonarr.${vhostDomain}";
          "description" = "TV shows";
          "siteMonitor" = "https://sonarr.${vhostDomain}";
        };
      }
      {
        "Radarr" = {
          "icon" = "radarr";
          "href" = "https://radarr.${vhostDomain}";
          "description" = "Movies";
          "siteMonitor" = "https://radarr.${vhostDomain}";
        };
      }
      {
        "Lidarr" = {
          "icon" = "lidarr";
          "href" = "https://lidarr.${vhostDomain}";
          "description" = "Music";
          "siteMonitor" = "https://lidarr.${vhostDomain}";
        };
      }
      {
        "Readarr" = {
          "icon" = "readarr";
          "href" = "https://readarr.${vhostDomain}";
          "description" = "Books";
          "siteMonitor" = "https://readarr.${vhostDomain}";
        };
      }
      {
        "Prowlarr" = {
          "icon" = "prowlarr";
          "href" = "https://prowlarr.${vhostDomain}";
          "description" = "Indexers";
          "siteMonitor" = "https://prowlarr.${vhostDomain}";
        };
      }
      {
        "Navidrome" = {
          "icon" = "navidrome";
          "href" = "https://navidrome.${vhostDomain}";
          "description" = "Music streaming";
          "siteMonitor" = "https://navidrome.${vhostDomain}";
        };
      }
      {
        "Audiobookshelf" = {
          "icon" = "audiobookshelf";
          "href" = "https://audiobookshelf.${vhostDomain}";
          "description" = "Audiobooks";
          "siteMonitor" = "https://audiobookshelf.${vhostDomain}";
        };
      }
      {
        "Calibre" = {
          "icon" = "calibre";
          "href" = "https://calibre.${vhostDomain}";
          "description" = "E-book library";
        };
      }
      {
        "Pinchflat" = {
          "icon" = "mdi-youtube";
          "href" = "https://pinchflat.${vhostDomain}";
          "description" = "YouTube archiver";
          "siteMonitor" = "https://pinchflat.${vhostDomain}";
        };
      }
      {
        "slskd" = {
          "icon" = "mdi-download-network";
          "href" = "https://slskd.${vhostDomain}";
          "description" = "Soulseek client";
        };
      }
      {
        "Media Library" = {
          "icon" = "grafana";
          "href" = "https://grafana.${vhostDomain}/d/media-library";
          "description" = "Movies / series / music (Grafana)";
        };
      }
    ];
  }
  {
    "Utilities" = [
      {
        "Grafana" = {
          "icon" = "grafana";
          "href" = "https://grafana.${vhostDomain}";
          "description" = "Metrics dashboards";
        };
      }
      {
        "Service Health" = {
          "icon" = "grafana";
          "href" = "https://grafana.${vhostDomain}/d/service-health";
          "description" = "Service up/down (Grafana)";
        };
      }
      {
        "Server Overview" = {
          "icon" = "grafana";
          "href" = "https://grafana.${vhostDomain}/d/server-overview";
          "description" = "CPU / RAM / disk / temp (Grafana)";
        };
      }
      {
        "Containers" = {
          "icon" = "grafana";
          "href" = "https://grafana.${vhostDomain}/d/containers";
          "description" = "Per-container CPU / RAM / net (Grafana)";
        };
      }
      {
        "Prometheus" = {
          "icon" = "prometheus";
          "href" = "http://${prometheusHost}:${toString prometheusPort}";
          "description" = "Metrics collection (fleet)";
          "siteMonitor" = "http://${prometheusHost}:${toString prometheusPort}/-/healthy";
        };
      }
      {
        "Vaultwarden" = {
          "icon" = "vaultwarden";
          "href" = "https://vaultwarden.${vhostDomain}";
          "description" = "Password manager";
          "siteMonitor" = "https://vaultwarden.${vhostDomain}";
        };
      }
      {
        "Firefly III" = {
          "icon" = "firefly-iii";
          "href" = "https://firefly.${vhostDomain}";
          "description" = "Finance";
          "siteMonitor" = "https://firefly.${vhostDomain}";
        };
      }
      {
        "Firefly Pico" = {
          "icon" = "firefly-iii";
          "href" = "https://firefly-pico.${vhostDomain}";
          "description" = "Mobile-friendly Firefly front end";
          "siteMonitor" = "https://firefly-pico.${vhostDomain}";
        };
      }
      {
        "Firefly Importer" = {
          "icon" = "firefly-iii";
          "href" = "https://firefly-import.${vhostDomain}";
          "description" = "Bank statement import";
        };
      }
      {
        "Caddy" = {
          "icon" = "caddy";
          "description" = "Reverse proxy";
          "ping" = "host.containers.internal:80";
        };
      }
      {
        "Tasks" = {
          "icon" = "mdi-calendar-check";
          "href" = "https://tasks.${vhostDomain}";
          "description" = "Radicale CalDAV / tasks";
        };
      }
      {
        "YT Transcripts" = {
          "icon" = "mdi-youtube";
          "href" = "https://transcripts.${vhostDomain}/docs";
          "description" = "Transcript API";
        };
      }
    ];
  }
]
