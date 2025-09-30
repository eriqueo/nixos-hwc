# domains/infrastructure/mesh/options.nix
#
# Consolidated options for infrastructure mesh subdomain
# Charter-compliant: ALL mesh options defined here, implementations in parts/

{ lib, ... }:

{
  options.hwc.infrastructure.mesh = {

    #==========================================================================
    # CONTAINER - Container networking
    #==========================================================================
    container = {
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
  };
}