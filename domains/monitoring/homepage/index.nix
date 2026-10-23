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
  identity = config.hwc.system.core.identity;
  installConfig = source: name: ''
    ${pkgs.coreutils}/bin/install -m 0644 -o ${identity.user} -g ${identity.group} ${source} ${cfg.dataDir}/${name}.yaml
  '';

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
      # Homepage 2.7.0 supplies the October 2026 Node security fixes.
      default = "ghcr.io/gethomepage/homepage@sha256:f1c9e802a0b9de6f64ef8d3e3d3aac4283f250e0a8ff5ebd170d791811431c99";
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
    # HWC-EXCEPTION(Law 5): infra container, not a media app
    # Justification: dashboard serving config from nix-generated files; no media mounts, PUID/PGID, or VPN netns
    # Plan: permanent by design (revisit if an infra-shaped helper grows to fit)
    # Revocable: yes
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
        PUID = toString identity.puid;
        PGID = toString identity.pgid;
      };

      extraOptions = [
        "--memory=512m"
        "--cpus=0.5"
        "--security-opt=label=disable"   # Required for Podman socket access
      ];
    };

    # Ensure data directory exists and deploy config files
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${identity.user} ${identity.group} -"
    ];

    # Deploy YAML config files to data directory
    system.activationScripts.homepageConfig = ''
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${identity.user} -g ${identity.group} ${cfg.dataDir}
      ${installConfig settingsYaml "settings"}
      ${installConfig servicesYaml "services"}
      ${installConfig widgetsYaml "widgets"}
      ${installConfig dockerYaml "docker"}
      ${installConfig bookmarksYaml "bookmarks"}
    '';

    # Caddy reverse proxy route
    hwc.networking.shared.routes = [
      {
        name = "homepage";
        mode = "vhost";
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
