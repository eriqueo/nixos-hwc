# domains/monitoring/uptime-kuma/index.nix
#
# Uptime Kuma - Self-hosted uptime monitoring with gotify notifications
#
# NAMESPACE: hwc.monitoring.uptime-kuma.*
#
# DEPENDENCIES:
#   - hwc.networking.shared.routes (for Caddy reverse proxy)
#   - gotify (for push notifications, configured manually post-deploy)
#
# PORTS:
#   - Internal: 3010 (container HTTP)
#   - External: 13543 (Caddy TLS termination)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.uptime-kuma;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.uptime-kuma = {
    enable = lib.mkEnableOption "Uptime Kuma - uptime monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Host port for Uptime Kuma web UI";
    };

    caddyPort = lib.mkOption {
      type = lib.types.port;
      default = 13543;
      description = "Caddy TLS port for Uptime Kuma";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "louislam/uptime-kuma:1";
      description = "Uptime Kuma container image";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/uptime-kuma";
      description = "Data directory for Uptime Kuma";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Uptime Kuma container
    virtualisation.oci-containers.containers.uptime-kuma = {
      image = cfg.image;
      autoStart = true;

      volumes = [
        "${cfg.dataDir}:/app/data"
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
      ];

      environment = {
        TZ = "America/Denver";
        UPTIME_KUMA_PORT = toString cfg.port;
      };

      extraOptions = [
        "--network=host"
        "--memory=512m"
        "--cpus=0.5"
      ];
    };

    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    # Caddy reverse proxy route
    hwc.networking.shared.routes = [
      {
        name = "uptime-kuma";
        mode = "port";
        port = cfg.caddyPort;
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.port > 0 && cfg.port < 65536;
        message = "Uptime Kuma port must be between 1 and 65535";
      }
    ];
  };
}
