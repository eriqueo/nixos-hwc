# domains/monitoring/alerts/index.nix
#
# Alert Sources — what to watch, failure hooks, systemd triggers.
#
# NAMESPACE: hwc.monitoring.alerts.*
#
# DEPENDENCIES:
#   - hwc.notifications (delivery infrastructure)
#
# USED BY:
#   - profiles/monitoring.nix (enables alert sources)
#   - machines/home/config.nix (configures thresholds)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.alerts;

  notifInternal = config.hwc.notifications._internal;

  # Reading systemd.services here recurses. Gate units on their owning
  # module instead: an OnFailure-only unit has no ExecStart and reports no failure.
  on = path: lib.attrByPath path false config;
  containers = config.virtualisation.oci-containers.containers;
  podman = name: lib.optional (containers ? ${name}) "podman-${name}";

  # hwc-notify cannot report its own death; do not add it to this list.
  autoDetectedServices =
    lib.optional (on [ "services" "caddy" "enable" ]) "caddy"
    ++ lib.optional (on [ "services" "postgresql" "enable" ]) "postgresql"
    ++ lib.optional (on [ "services" "jellyfin" "enable" ]) "jellyfin"
    ++ lib.concatMap podman [
      "n8n" "navidrome" "gluetun" "mousehole" "qbittorrent" "sonarr" "radarr" "prowlarr"
      "refinery" "umami"
    ]
    ++ lib.optional (on [ "hwc" "business" "crm" "enable" ]) "hwc-crm"
    ++ lib.optional (on [ "hwc" "system" "mcp" "enable" ]) "hwc-sys-mcp"
    ++ lib.optional (on [ "hwc" "server" "services" "radicale" "enable" ]) "radicale"
    ++ lib.optional (on [ "hwc" "server" "ai" "leadScout" "enable" ]) "lead-scout"
    ++ lib.optional (on [ "hwc" "networking" "cloudflared" "enable" ])
         "cloudflared-tunnel-${config.hwc.networking.cloudflared.tunnelId}"
    ++ lib.optional (on [ "hwc" "server" "ai" "brainvec" "enable" ]) "brainvec-ingest"
    ++ lib.optional (on [ "hwc" "business" "crm" "enable" ]) "hwc-crm-tick"
    ++ lib.optional (on [ "hwc" "data" "storage" "enable" ] && on [ "hwc" "data" "storage" "monitoring" "enable" ]) "storage-monitor"
    ++ lib.optional (on [ "hwc" "automation" "inboxJanitor" "enable" ]) "inbox-janitor"
    ++ lib.optional (on [ "hwc" "business" "morningBriefing" "enable" ]) "morning-briefing"
    ++ lib.optional (on [ "hwc" "automation" "nightlyBuilds" "enable" ]) "nightly-builds"
    ++ lib.optional (on [ "hwc" "server" "ai" "llamaCpp" "embed" "enable" ]) "llama-embed"
    ++ lib.optionals (on [ "hwc" "server" "ai" "homeScout" "enable" ]) [
      "home-scout-schools"
      "home-scout-overlays"
    ] ++ lib.optional (on [ "hwc" "media" "recyclarr" "enable" ]) "recyclarr-sync"
    ++ lib.optional
    (on [ "hwc" "server" "services" "radicale" "enable" ]
      && (lib.attrByPath [ "hwc" "server" "services" "radicale" "mirrors" ] { } config) != { })
    "radicale-mirror";

  monitoredServices =
    if cfg.sources.serviceFailures.services != []
    then cfg.sources.serviceFailures.services
    else if cfg.sources.serviceFailures.autoDetect
    then autoDetectedServices
    else [];

in
{
  # OPTIONS
  options.hwc.monitoring.alerts = {
    enable = lib.mkEnableOption "Alert sources — detection, failure hooks";
    # ALERT SOURCES
    sources = {
      smartd = {
        enable = lib.mkEnableOption "SMART disk monitoring alerts";
      };

      backup = {
        enable = lib.mkEnableOption "Backup completion/failure alerts";

        onSuccess = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Send alert on successful backup";
        };

        onFailure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Send alert on backup failure";
        };
      };

      # NOTE: Disk-space monitoring is owned by Prometheus alerts
      # (domains/monitoring/prometheus/parts/alerts.nix: Moderate/Elevated/High
      # DiskUsage → Alertmanager → hwc-notify). The legacy script-based
      # hwc-disk-space-check source was retired 2026-06-04 (n8n webhook path).

      serviceFailures = {
        enable = lib.mkEnableOption "Service failure monitoring alerts";

        services = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            List of services to monitor for failures.
            Empty list = auto-detect critical services.
          '';
          example = [ "podman-immich" "jellyfin" "backup" ];
        };

        autoDetect = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Auto-detect critical services to monitor";
        };
      };
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    # SMARTD NOTIFICATIONS
    services.smartd = lib.mkIf cfg.sources.smartd.enable {
      notifications = {
        mail = {
          enable = lib.mkForce true;
          sender = "smartd@${config.networking.hostName}";
          recipient = "root";  # Required but unused - our script ignores it
          mailer = "${notifInternal.smartdNotify}/bin/hwc-smartd-notify";
        };
        x11.enable = lib.mkForce false;
        wall.enable = lib.mkForce false;
        test = lib.mkForce false;
      };
    };
    # SYSTEMD SERVICES
    systemd.services = lib.mkMerge [
      # Callers insert literal unit names, so %i preserves their hyphens.
      (lib.mkIf cfg.sources.serviceFailures.enable {
        "hwc-service-failure-notifier@" = {
          description = "HWC service failure notifier for %i";

          serviceConfig = {
            Type = "oneshot";
            # %I would turn hwc-crm-tick into the unrelated hwc/crm/tick.
            ExecStart = "${notifInternal.serviceFailureNotify}/bin/hwc-service-failure-notify %i";
            User = "root";

            SuccessExitStatus = [ 0 1 ];
          };

          unitConfig = {
            DefaultDependencies = false;
            RefuseManualStart = false;
          };
        };
      })

      (lib.mkIf (cfg.sources.serviceFailures.enable && monitoredServices != []) (
        lib.listToAttrs (map (serviceName: {
          name = serviceName;
          value = {
            unitConfig.OnFailure = lib.mkDefault "hwc-service-failure-notifier@${serviceName}.service";
          };
        }) monitoredServices)
      ))
    ];

    # The same producer/sender in the user manager. No root log directory or
    # second delivery channel; failures remain visible in this unit's journal.
    systemd.user.services."hwc-service-failure-notifier@" = lib.mkIf cfg.sources.serviceFailures.enable {
      description = "HWC user service terminal failure notifier for %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${notifInternal.serviceFailureNotify}/bin/hwc-service-failure-notify --user %i";
        TimeoutStartSec = 30;
      };
    };
    # VALIDATION
    assertions = [
      {
        assertion = !cfg.enable || (config.hwc.notifications.enable or false);
        message = ''
          hwc.monitoring.alerts requires notifications to be enabled for delivery.
          Enable notifications with: hwc.notifications.enable = true
        '';
      }
      {
        assertion = !cfg.sources.smartd.enable || (config.services.smartd.enable or false);
        message = "hwc.monitoring.alerts.sources.smartd requires services.smartd.enable = true";
      }
    ];
    # WARNINGS
    warnings = lib.optional (cfg.sources.serviceFailures.enable && monitoredServices == []) ''
      hwc.monitoring.alerts.sources.serviceFailures is enabled but no services are being monitored.
      Either:
        1. Set hwc.monitoring.alerts.sources.serviceFailures.services = [ "service1" "service2" ]
        2. Or ensure auto-detected services are enabled (jellyfin, n8n, etc.)
    '';
  };
}
