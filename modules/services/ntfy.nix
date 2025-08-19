{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.ntfy;
  paths = config.hwc.paths;
in {
  options.hwc.services.ntfy = {
    enable = lib.mkEnableOption "ntfy notification service";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "ntfy web port";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/ntfy";
      description = "Data directory";
    };
  };

  config = lib.mkIf cfg.enable {
    # Container configuration
    virtualisation.oci-containers.containers.ntfy = {
      image = "binwiederhier/ntfy:latest";
      ports = [ "${toString cfg.port}:80" ];
      volumes = [
        "${cfg.dataDir}:/var/cache/ntfy"
        "${cfg.dataDir}/etc:/etc/ntfy"
      ];
      environment = {
        TZ = "America/Denver";
      };
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/etc 0750 root root -"
    ];

    # Open firewall
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
