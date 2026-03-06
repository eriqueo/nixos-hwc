# domains/system/virtualization/index.nix
#
# QEMU/KVM Virtualization with libvirtd
# Provides VM management, container networking, and SPICE support.
#
# USAGE:
#   hwc.system.virtualization.enable = true;
#   hwc.system.virtualization.spiceSupport = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.virtualization;
  t = lib.types;

  dir   = builtins.readDir ./.;
  files = lib.filterAttrs (n: ty: ty == "regular" && lib.hasSuffix ".nix" n && n != "index.nix" && n != "options.nix") dir;
  subds = lib.filterAttrs (_: ty: ty == "directory") dir;

  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
  subIndex  =
    lib.pipe (lib.attrNames subds) [
      (ns: lib.filter (n: builtins.pathExists (./. + "/${n}/index.nix")) ns)
      (ns: lib.map (n: ./. + "/${n}/index.nix") ns)
    ];
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.virtualization = {
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

  imports = filePaths ++ subIndex;

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = (config.boot.kernelModules or []) != [] || builtins.pathExists "/dev/kvm";
        message = "Virtualization requires KVM (load kvm-intel or kvm-amd).";
      }
    ];

    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = false;
          swtpm.enable = true;
          # OVMF images are now available by default
          vhostUserPackages = with pkgs; [ virtiofsd ];
        };
      };

      spiceUSBRedirection.enable = cfg.spiceSupport;

      docker.enable = lib.mkForce false;

      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };

      oci-containers.backend = lib.mkForce "podman";
    };

    environment.systemPackages = with pkgs; [
      virt-manager
      virt-viewer
      spice
      spice-gtk
      spice-protocol
      virtiofsd
      virtio-win
      win-spice
      freerdp
      xdg-utils
    ];

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
            (lib.optionalString cfg.containerNetworking.enableIpv6 "--ipv6 ") +
            name;
          ExecStop = "${pkgs.docker}/bin/docker network rm ${name}";
        };
      }
    ) cfg.containerNetworking.networks;

    virtualisation.docker.daemon.settings = {
      default-address-pools = [
        { base = "172.16.0.0/12"; size = 24; }
      ];
      ipv6 = cfg.containerNetworking.enableIpv6;
      fixed-cidr-v6 = lib.mkIf cfg.containerNetworking.enableIpv6 "2001:db8::/64";
    };
  };

}
