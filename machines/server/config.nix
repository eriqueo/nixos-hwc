{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../profiles/security.nix
    ../../profiles/ai.nix
  ];

  # System identity
  networking.hostName = "hwc-server";
  networking.hostId = "8425e349";

  # Charter v3 path configuration (matching production)
  hwc.paths = {
    hot = "/mnt/hot";      # SSD hot storage
    media = "/mnt/media";  # HDD media storage
    cold = "/mnt/media";   # Cold storage same as media for now
    # Additional paths from production
    business.root = "/opt/business";
    cache = "/opt/cache";
  };

  # Production storage mounts (from production config)
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-label/media";
    fsType = "ext4";
  };

  # Time zone (from production)
  time.timeZone = "America/Denver";

  # Production system settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # allowUnfree set in flake.nix

  # AI services configuration
  hwc.server.ai.ollama = {
    enable = true;
    models = [ "llama3:8b" "codellama:13b" ];
  };

  # Enhanced SSH configuration for server
  services.openssh.settings = {
    X11Forwarding = true;
    PasswordAuthentication = lib.mkForce true;  # Temporary - for SSH key update
  };

  # Enable X11 services for forwarding
  services.xserver.enable = true;

  # Server-specific packages moved to modules/system/server-packages.nix
  hwc.system.packages.server.enable = true;

  # Production I/O scheduler optimization
  services.udev.extraRules = ''
    # Use mq-deadline for SSDs (better for mixed workloads)
    ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd*", ENV{ID_BUS}=="ata", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

    # Use CFQ for HDDs (better for sequential workloads)
    ACTION=="add|change", KERNEL=="sd*", ENV{ID_BUS}=="ata", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="cfq"
  '';

  # Enhanced logging for production server
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    RuntimeMaxUse=100M
  '';

  system.stateVersion = "24.05";
}
