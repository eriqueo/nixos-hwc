# HWC Charter Module/domains/services/business/metrics.nix
#
# BUSINESS METRICS - Business metrics collection and export service
# Provides Prometheus-compatible metrics for business intelligence
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.services.business.monitoring.networking (networking config)
#
# USED BY (Downstream):
#   - profiles/server.nix (enables via hwc.services.business.metrics.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../domains/services/business/metrics.nix
#
# USAGE:
#   hwc.services.business.metrics.enable = true;
#   hwc.services.business.metrics.port = 9999;

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hwc.services.business.metrics;
  paths = config.hwc.paths;
in {

  #============================================================================
  # OPTIONS - Service Configuration Interface
  #============================================================================

  options.hwc.services.business.metrics = {
    enable = mkEnableOption "business metrics collection and export";

    port = mkOption {
      type = types.port;
      default = 9999;
      description = "Port for the business metrics exporter";
    };

    image = mkOption {
      type = types.str;
      default = "python:3.11-slim";
      description = "Docker image for business metrics";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Auto-start business metrics container";
    };

    networking = {
      useMediaNetwork = mkOption {
        type = types.bool;
        default = config.hwc.services.business.monitoring.networking.useMediaNetwork or false;
        description = "Use media network for metrics";
      };
      
      networkName = mkOption {
        type = types.str;
        default = config.hwc.services.business.monitoring.networking.networkName or "hwc-media";
        description = "Network name for metrics";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION - Service Definition
  #============================================================================

  config = mkIf cfg.enable {

    # Business metrics container
    virtualisation.oci-containers.containers.business-metrics = {
      image = cfg.image;
      autoStart = cfg.autoStart;
      extraOptions = mkIf cfg.networking.useMediaNetwork [ "--network=${cfg.networking.networkName}" ];
      ports = [ "${toString cfg.port}:9999" ];
      volumes = [
        "${paths.cache}/monitoring/business:/app"
        "${paths.business}:/business:ro"
        "/var/log:/logs:ro"
        "/etc/localtime:/etc/localtime:ro"
      ];
      cmd = [ "sh" "-c" "cd /app && pip install prometheus_client requests && python business_metrics.py" ];
    };

    # Firewall configuration
    hwc.networking.firewall.extraTcpPorts = mkIf config.hwc.networking.enable [
      cfg.port
    ];

    # Allow metrics access on Tailscale
    networking.firewall.interfaces."tailscale0" = mkIf config.hwc.networking.tailscale.enable {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}