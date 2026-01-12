# domains/infrastructure/virtualization/index.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.virtualization;
  t = lib.types;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

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
