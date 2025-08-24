# nixos-hwc/modules/infrastructure/virtualization.nix
#
# QEMU/KVM Virtualization Infrastructure
# Provides VM support with libvirtd, OVMF, and USB redirection
#
# DEPENDENCIES:
#   Upstream: None (standalone infrastructure)
#   Upstream: config.hwc.users.primary (for group membership)
#
# USED BY:
#   Downstream: profiles/workstation.nix (enables for desktop environments)
#   Downstream: machines/laptop/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/infrastructure/virtualization.nix
#
# USAGE:
#   hwc.infrastructure.virtualization.enable = true;
#   hwc.infrastructure.virtualization.enableGpu = true;  # GPU passthrough support
#   hwc.infrastructure.virtualization.spiceSupport = true;  # SPICE protocol
#
# VALIDATION:
#   - Requires KVM support in kernel
#   - User must be added to libvirtd group

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.virtualization;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.infrastructure.virtualization = {
    enable = lib.mkEnableOption "QEMU/KVM virtualization with libvirtd";
    
    # QEMU settings
    enableGpu = lib.mkEnableOption "GPU passthrough support";
    
    # SPICE protocol support
    spiceSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SPICE USB redirection and tools";
    };
    
    # User access
    userGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "libvirtd" ];
      description = "Groups to add primary user to for VM management";
    };
    
    # Container runtime (for comparison with existing base.nix)
    containers = lib.mkOption {
      type = lib.types.enum [ "podman" "docker" "none" ];
      default = "podman";
      description = "Container runtime to use alongside VMs";
    };
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation: Check KVM support
    assertions = [
      {
        assertion = config.boot.kernelModules or [] != [] || builtins.pathExists "/dev/kvm";
        message = "Virtualization requires KVM support - ensure kvm-intel or kvm-amd module is loaded";
      }
    ];
    
    # QEMU/KVM with libvirtd
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = false;
        swtpm.enable = true;           # TPM emulation
        ovmf.enable = true;            # UEFI firmware
        ovmf.packages = [ pkgs.OVMF.fd ];
        vhostUserPackages = with pkgs; [ virtiofsd ];  # Shared filesystem
      };
    };
    
    # SPICE USB redirection
    virtualisation.spiceUSBRedirection.enable = cfg.spiceSupport;
    
    # Container runtime (separate from VMs)
    virtualisation = lib.mkMerge [
      (lib.mkIf (cfg.containers == "podman") {
        podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true;
        };
        oci-containers.backend = "podman";
      })
      (lib.mkIf (cfg.containers == "docker") {
        docker.enable = true;
        oci-containers.backend = "docker";
      })
    ];
    
    # System packages for VM management
    environment.systemPackages = with pkgs; [
      # VM tools
      spice
      spice-gtk
      spice-protocol
      win-virtio        # Windows VirtIO drivers
      win-spice         # Windows SPICE tools
      virtiofsd         # Shared filesystem daemon
      
      # Management tools
      virt-manager      # GUI VM management
      virt-viewer       # VM console viewer
    ];
    
    # User groups for VM management
    users.users = lib.mkMerge [
      (lib.mkIf (config.users.users ? eric) {
        eric.extraGroups = cfg.userGroups;
      })
    ];
  };
}