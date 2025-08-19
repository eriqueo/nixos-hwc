{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.containerNetworking;
in {
  options.hwc.containerNetworking = {
    networks = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "Container networks";
      example = {
        media = {
          subnet = "172.20.0.0/16";
          gateway = "172.20.0.1";
        };
      };
    };

    defaultNetwork = lib.mkOption {
      type = lib.types.str;
      default = "bridge";
      description = "Default container network";
    };

    enableIpv6 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable IPv6 in containers";
    };
  };

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
