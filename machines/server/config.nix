{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware/hwc-server.nix
    .../profiles/base.nix
    .../profiles/media.nix
    .../profiles/monitoring.nix
    .../profiles/ai.nix
    .../profiles/security.nix
  ];

  # System identity
  networking.hostName = "hwc-server";
  networking.hostId = "8425e349";  # Generate with: head -c 8 /etc/machine-id

  # Your domain
  networking.domain = "hwc.moe";

  # Storage configuration (update UUIDs from your hardware-configuration.nix)
  hwc.storage = {
    hot.device = "/dev/disk/by-uuid/YOUR-SSD-UUID";
    media.device = "/dev/disk/by-uuid/YOUR-HDD-UUID";
  };

  # GPU configuration
  hwc.gpu.nvidia = {
    enable = true;
    driver = "stable";
    containerRuntime = true;
  };

  # Boot configuration (from your current setup)
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Your specific overrides
  hwc.services = {
    # Specific ports if different from defaults
    jellyfin.port = 8096;
    frigate.port = 5000;
  };

  system.stateVersion = "24.05";
}
