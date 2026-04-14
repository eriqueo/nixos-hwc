# domains/data/cloudbeaver/index.nix
#
# CloudBeaver - Web-based database management tool
# Provides graphical PostgreSQL access from any device
#
# NAMESPACE: hwc.data.cloudbeaver.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#   - hwc.data.databases.postgresql (database server)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.data.cloudbeaver;
  paths = config.hwc.paths;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
in
{
  # OPTIONS
  options.hwc.data.cloudbeaver = {
    enable = lib.mkEnableOption "CloudBeaver web-based database manager";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/dbeaver/cloudbeaver:latest";
      description = "CloudBeaver container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8978;
      description = "CloudBeaver web interface port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/cloudbeaver";
      description = "Data directory for CloudBeaver workspace";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Container definition
    virtualisation.oci-containers.containers.cloudbeaver = {
      image = cfg.image;
      autoStart = true;
      pull = "missing";

      ports = [
        "127.0.0.1:${toString cfg.port}:8978"
      ];

      volumes = [
        "${cfg.dataDir}/workspace:/opt/cloudbeaver/workspace"
      ];

      environment = {
        TZ = config.time.timeZone or "UTC";
      };

      extraOptions = [
        "--network=media-network"
        "--memory=1g"
        "--cpus=0.5"
        "--memory-swap=2g"
      ];
    };

    # Pre-start: ensure directories exist with correct permissions
    systemd.services.podman-cloudbeaver.preStart = ''
      mkdir -p ${cfg.dataDir}/workspace
      chown -R 1000:100 ${cfg.dataDir}
    '';

    # Systemd dependencies
    systemd.services.podman-cloudbeaver = {
      after = [ "postgresql.service" "init-media-network.service" ];
      requires = [ "init-media-network.service" ];
    };

    # Firewall - localhost only (Caddy handles external access)
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = config.hwc.data.databases.postgresql.enable;
        message = "CloudBeaver requires PostgreSQL (hwc.data.databases.postgresql.enable = true)";
      }
    ];
  };
}
