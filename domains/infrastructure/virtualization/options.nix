# domains/infrastructure/virtualization/options.nix
{ lib, ... }:

let
  t = lib.types;
in
{
  options.hwc.infrastructure.virtualization = {
    enable = lib.mkEnableOption "QEMU/KVM virtualization with libvirtd";
    enableGpu = lib.mkEnableOption "GPU passthrough support (placeholder toggles)";
    spiceSupport = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Enable SPICE USB redirection and tools";
    };

    userGroups = lib.mkOption {
      type = t.listOf t.str;
      default = [ "libvirtd" ];
      description = "Groups to add primary user to for VM management";
    };

    containerNetworking = {
      networks = lib.mkOption {
        type = t.attrsOf t.attrs;
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
        type = t.str;
        default = "bridge";
        description = "Default container network";
      };

      enableIpv6 = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable IPv6 in containers";
      };
    };
  };
}
