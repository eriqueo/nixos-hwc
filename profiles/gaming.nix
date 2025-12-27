{ config, lib, pkgs, ... }:

{
  #==========================================================================
  # BASE - Critical for gaming functionality
  #==========================================================================

  # NOTE: Gaming app module imports (retroarch, 86box, mpv) will be added
  # once those modules are integrated from nixos-kids repo
  # imports = [
  #   ../domains/home/apps/retroarch
  #   ../domains/home/apps/86box
  #   ../domains/home/apps/mpv
  # ];

  # Auto-login for console-like UX
  hwc.system.services.session = {
    enable = true;
    loginManager = {
      enable = lib.mkDefault true;
      autoLoginUser = lib.mkDefault "eric";
      defaultCommand = lib.mkDefault "Hyprland";
    };
  };

  # Audio support (critical for gaming)
  hwc.system.services.hardware = {
    enable = true;
    audio.enable = true;
    bluetooth.enable = true;  # For wireless controllers
  };

  # Network for ROM management
  hwc.networking = {
    enable = true;
    ssh.enable = lib.mkDefault true;
    tailscale.enable = lib.mkDefault true;
  };

  # Fast boot configuration
  boot.kernelParams = [ "quiet" "splash" "loglevel=3" ];
  systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;

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
  hwc.networking.samba = {
    enable = lib.mkDefault false;  # Enable per machine as needed
  };
}
