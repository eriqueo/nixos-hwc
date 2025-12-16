# HWC Charter Module/domains/services/ntfy.nix
#
# NTFY - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.ntfy.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/ntfy.nix
#
# USAGE:
#   hwc.services.ntfy.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.ntfy;
  paths = config.hwc.paths;
in {
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Container configuration
    virtualisation.oci-containers.containers.ntfy = {
      image = "binwiederhier/ntfy:latest";
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
