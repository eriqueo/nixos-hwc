# HWC Charter Module/domains/services/business/dashboard.nix
#
# BUSINESS DASHBOARD - Streamlit analytics dashboard service
# Provides web-based business intelligence and analytics visualization
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.services.business.monitoring.networking (networking config)
#
# USED BY (Downstream):
#   - profiles/server.nix (enables via hwc.services.business.dashboard.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../domains/services/business/dashboard.nix
#
# USAGE:
#   hwc.services.business.dashboard.enable = true;
#   hwc.services.business.dashboard.port = 8501;

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hwc.services.business.dashboard;
  paths = config.hwc.paths;
in {

  #============================================================================
  # OPTIONS - Service Configuration Interface
  #============================================================================

  options.hwc.services.business.dashboard = {
    enable = mkEnableOption "business analytics dashboard (Streamlit)";

    port = mkOption {
      type = types.port;
      default = 8501;
      description = "Port for the business dashboard";
    };

    image = mkOption {
      type = types.str;
      default = "python:3.11-slim";
      description = "Docker image for business dashboard";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Auto-start business dashboard container";
    };

    networking = {
      useMediaNetwork = mkOption {
        type = types.bool;
        default = config.hwc.services.business.monitoring.networking.useMediaNetwork or false;
        description = "Use media network for dashboard";
      };
      
      networkName = mkOption {
        type = types.str;
        default = config.hwc.services.business.monitoring.networking.networkName or "hwc-media";
        description = "Network name for dashboard";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION - Service Definition
  #============================================================================

  config = mkIf cfg.enable {

    # Business dashboard container
    virtualisation.oci-containers.containers.business-dashboard = {
      image = cfg.image;
      autoStart = cfg.autoStart;
      extraOptions = mkIf cfg.networking.useMediaNetwork [ "--network=${cfg.networking.networkName}" ];
      ports = [ "${toString cfg.port}:8501" ];
      volumes = [
        "${paths.cache}/monitoring/business:/app"
        "${paths.business}:/business:ro"
        "${paths.media.root}:/media:ro"
        "/etc/localtime:/etc/localtime:ro"
      ];
      cmd = [ "sh" "-c" "cd /app && pip install streamlit pandas plotly requests prometheus_client && streamlit run dashboard.py --server.port=8501 --server.address=0.0.0.0" ];
    };

    # Firewall configuration
    hwc.networking.firewall.extraTcpPorts = mkIf config.hwc.networking.enable [
      cfg.port
    ];

    # Allow dashboard access on Tailscale
    networking.firewall.interfaces."tailscale0" = mkIf config.hwc.networking.tailscale.enable {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}