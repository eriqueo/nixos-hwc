# domains/monitoring/homepage/index.nix
#
# Homepage (gethomepage) - Service dashboard with status checks and API widgets
#
# NAMESPACE: hwc.monitoring.homepage.*
#
# DEPENDENCIES:
#   - hwc.paths (for dataDir)
#   - hwc.networking.shared.routes (for Caddy reverse proxy)
#
# PORTS:
#   - Internal: 3080 (container HTTP)
#   - External: 17443 (Caddy TLS termination)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.homepage;

  # YAML config files for Homepage
  settingsYaml = pkgs.writeText "homepage-settings.yaml" (builtins.readFile ./parts/settings.yaml);
  servicesYaml = pkgs.writeText "homepage-services.yaml" (builtins.readFile ./parts/services.yaml);
  widgetsYaml = pkgs.writeText "homepage-widgets.yaml" (builtins.readFile ./parts/widgets.yaml);
  dockerYaml = pkgs.writeText "homepage-docker.yaml" (builtins.readFile ./parts/docker.yaml);
  bookmarksYaml = pkgs.writeText "homepage-bookmarks.yaml" (builtins.readFile ./parts/bookmarks.yaml);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.homepage = {
    enable = lib.mkEnableOption "Homepage - service dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3080;
      description = "Host port for Homepage web UI";
    };

    caddyPort = lib.mkOption {
      type = lib.types.port;
      default = 17443;
      description = "Caddy TLS port for Homepage";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/gethomepage/homepage:latest";
      description = "Homepage container image";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/homepage";
      description = "Data directory for Homepage configuration";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Homepage container
    virtualisation.oci-containers.containers.homepage = {
      image = cfg.image;
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:3000"
      ];

      volumes = [
        "${cfg.dataDir}:/app/config"
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
      ];

      environment = {
        HOMEPAGE_ALLOWED_HOSTS = "*";
        PUID = "1000";
        PGID = "100";
      };

      extraOptions = [
        "--memory=512m"
        "--cpus=0.5"
      ];
    };

    # Ensure data directory exists and deploy config files
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    # Deploy YAML config files to data directory
    system.activationScripts.homepageConfig = ''
      mkdir -p ${cfg.dataDir}
      cp -f ${settingsYaml} ${cfg.dataDir}/settings.yaml
      cp -f ${servicesYaml} ${cfg.dataDir}/services.yaml
      cp -f ${widgetsYaml} ${cfg.dataDir}/widgets.yaml
      cp -f ${dockerYaml} ${cfg.dataDir}/docker.yaml
      cp -f ${bookmarksYaml} ${cfg.dataDir}/bookmarks.yaml
      chmod 0644 ${cfg.dataDir}/*.yaml
    '';

    # Caddy reverse proxy route
    hwc.networking.shared.routes = [
      {
        name = "homepage";
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
        message = "Homepage port must be between 1 and 65535";
      }
    ];
  };
}
