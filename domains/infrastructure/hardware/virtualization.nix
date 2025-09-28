# HWC Charter Module/domains/infrastructure/virtualization.nix
#
# VIRTUALIZATION - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.infrastructure.virtualization.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/virtualization.nix
#
# USAGE:
#   hwc.infrastructure.virtualization.enable = true;
#   # TODO: Add specific usage examples

# HWC Charter Module/domains/infrastructure/virtualization.nix
#
# Infrastructure: Virtualization & Containers (QEMU/KVM + Podman)
# Provides VM support (libvirtd, OVMF, SPICE) and a single container runtime (Podman).
#
# DEPENDENCIES:
#   Upstream: none
#
# USED BY:
#   Downstream: profiles/workstation.nix, machines/*/config.nix
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../domains/infrastructure/virtualization.nix
#
# USAGE:
#   hwc.infrastructure.virtualization.enable = true;
#   hwc.infrastructure.virtualization.enableGpu = true;   # optional passthrough helpers
#   hwc.infrastructure.virtualization.spiceSupport = true;
#
# CHARTER NOTES:
#   - Infra module owns host runtime choice. No runtime selection in profiles.
#   - Single source of truth: Podman everywhere; Docker explicitly disabled.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.virtualization;
  t   = lib.types;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.infrastructure.virtualization = {
    enable      = lib.mkEnableOption "QEMU/KVM virtualization with libvirtd";
    enableGpu   = lib.mkEnableOption "GPU passthrough support (placeholder toggles)";
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
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    # --- Sanity: host must support KVM ---------------------------------------
    assertions = [
      {
        assertion = (config.boot.kernelModules or []) != [] || builtins.pathExists "/dev/kvm";
        message   = "Virtualization requires KVM (load kvm-intel or kvm-amd).";
      }
    ];

    # --- Virtualisation stack -------------------------------------------------
    virtualisation = {
      # VMs: libvirt + QEMU/OVMF/TPM
      libvirtd = {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = false;
          swtpm.enable = true;
          ovmf.enable  = true;
          ovmf.packages = [ pkgs.OVMFFull.fd ];
          vhostUserPackages = with pkgs; [ virtiofsd ];
        };
      };

      # SPICE USB redirection
      spiceUSBRedirection.enable = cfg.spiceSupport;

      # Containers: one runtime only → Podman
      docker.enable = lib.mkForce false;

      podman = {
        enable = true;
        dockerCompat = true;                    # /run/podman/podman.sock for compat tools
        defaultNetwork.settings.dns_enabled = true;
      };

      # Force the backend so nothing else can flip it later.
      oci-containers.backend = lib.mkForce "podman";
    };

    # --- Tooling --------------------------------------------------------------
    environment.systemPackages = with pkgs; [
      # VM/virt tools
      virt-manager
      virt-viewer
      spice
      spice-gtk
      spice-protocol
      virtiofsd
      win-virtio
      win-spice
    ];

    # --- User access handled in user domain -----------------------
  };
}
