# HWC Charter Module/domains/infrastructure/container-networking.nix
#
# CONTAINER NETWORKING - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.infrastructure.container-networking.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/container-networking.nix
#
# USAGE:
#   hwc.infrastructure.container-networking.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.mesh.container;
in {
  #============================================================================
  # IMPLEMENTATION - Container networking
  #============================================================================
  config = {
    # Create docker networks
    systemd.services = lib.mapAttrs' (name: network:
      lib.nameValuePair "docker-network-${name}" {
        description = "Docker network ${name}";
        after = [ "docker.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.docker}/bin/docker network create " +
            "--subnet=${network.subnet} " +
            "--gateway=${network.gateway} " +
            (lib.optionalString cfg.enableIpv6 "--ipv6 ") +
            name;
          ExecStop = "${pkgs.docker}/bin/docker network rm ${name}";
        };
      }
    ) cfg.networks;

    # Configure docker daemon
    virtualisation.docker.daemon.settings = {
      default-address-pools = [
        { base = "172.16.0.0/12"; size = 24; }
      ];
      ipv6 = cfg.enableIpv6;
      fixed-cidr-v6 = lib.mkIf cfg.enableIpv6 "2001:db8::/64";
    };
  };
}
