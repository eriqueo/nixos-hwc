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
  shared = config.hwc.networking.shared;
  hosts = config.hwc.networking.hosts;
  mcp = config.hwc.system.mcp;
  services = import ./parts/services.nix {
    inherit (shared) vhostDomain;
    prometheusHost = shared.tailscaleDomain;
    prometheusPort = config.hwc.monitoring.prometheus.port;
    mcpPort = mcp.port;
    mcpHealthUrl = hosts.url { server = mcp.serverAlias; port = mcp.tailnetPort; path = "/health"; };
    n8nUrl = config.hwc.automation.n8n.publicUrl;
  };
  installConfig = source: name: ''
    ${pkgs.coreutils}/bin/install -m 0644 -o ${identity.user} -g ${identity.group} ${source} ${cfg.dataDir}/${name}.yaml
  '';

  configFiles = lib.genAttrs [ "settings" "widgets" "docker" "bookmarks" ]
    (name: pkgs.writeText "homepage-${name}.yaml" (builtins.readFile (./parts + "/${name}.yaml")))
    // { services = (pkgs.formats.yaml {}).generate "homepage-services.yaml" services; };
in
{
  # OPTIONS
  options.hwc.monitoring.homepage = {
    enable = lib.mkEnableOption "Homepage - service dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3080;
      description = "Host port for Homepage web UI";
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
  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
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

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${identity.user} ${identity.group} -"
    ];

    system.activationScripts.homepageConfig = ''
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${identity.user} -g ${identity.group} ${cfg.dataDir}
      ${lib.concatStrings (lib.mapAttrsToList (name: source: installConfig source name) configFiles)}
    '';

    hwc.networking.shared.routes = [
      {
        name = "homepage";
        mode = "vhost";
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];
    # VALIDATION
    assertions = [
      {
        assertion = cfg.port > 0 && cfg.port < 65536;
        message = "Homepage port must be between 1 and 65535";
      }
    ];
  };
}
