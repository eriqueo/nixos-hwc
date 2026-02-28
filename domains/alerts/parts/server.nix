# domains/alerts/parts/server.nix
#
# ntfy notification server container
#
# NAMESPACE: hwc.alerts.server.*
#
# DEPENDENCIES:
#   - hwc.paths (for dataDir)
#
# USED BY:
#   - Alert routing system (webhook receiver)
#   - Mobile push notifications
#   - Cross-machine alerting

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.alerts.server;
in
{
  config = lib.mkIf cfg.enable {
    # Container configuration
    virtualisation.oci-containers.containers.ntfy = {
      image = cfg.image;
      cmd = [ "serve" ];  # CRITICAL: Tell ntfy to run the server
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
