# profiles/gaming/sys.nix — gaming role, NixOS lane
#
# Retro gaming station: auto-login console UX, audio/bluetooth, fast boot.
# Base role is supplied by the machine's role list — this role does NOT
# import it (roles never import roles).
#
# REPLACES: profiles/gaming.nix
# USED BY: see the machines table in flake.nix

{ config, lib, pkgs, ... }:

{
  # Auto-login for console-like UX
  hwc.system.core.session = {
    enable = true;
    loginManager = {
      enable = lib.mkDefault true;
      autoLoginUser = lib.mkDefault "eric";
      defaultCommand = lib.mkDefault "Hyprland";
    };
  };

  # Audio support (critical for gaming)
  hwc.system.hardware = {
    enable = true;
    audio.enable = true;
    bluetooth.enable = true;  # For wireless controllers
  };

  # Network for ROM management
  hwc.system.networking = {
    enable = true;
    ssh.enable = lib.mkDefault true;
    tailscale.enable = lib.mkDefault true;
  };

  # Fast boot configuration
  boot.kernelParams = [ "quiet" "splash" "loglevel=3" ];
  systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;

  # nix-ld GUI libs (extends base role set for graphical machines)
  hwc.system.core.nixld.guiLibs.enable = true;

  # Performance tuning for gaming
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642;  # For emulators
    "vm.swappiness" = 10;
  };

  #==========================================================================
  # OPTIONAL FEATURES - Override per machine
  #==========================================================================

  # Samba for ROM transfer
  hwc.system.networking.samba = {
    enable = lib.mkDefault false;  # Enable per machine as needed
  };
}
