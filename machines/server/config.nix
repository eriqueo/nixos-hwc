# nixos-hwc/machines/server/config.nix
#
# MACHINE: HWC-SERVER
# Declares machine identity and composes profiles; states hardware reality.

{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/system.nix
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

  # --- Networking Configuration (Server: DO wait for network) ---
  hwc.networking = {
    enable = true;
    networkManager.enable = true;

    # Safest: wait for any NetworkManager connection (no hard-coded iface names).
    waitOnline.mode = "all";
    waitOnline.timeoutSeconds = 90;

    ssh.enable = true;
    tailscale.enable = true;
    firewall.level = lib.mkForce "server";
  };

  # AI services configuration
  hwc.server.ai.ollama = {
    enable = true;
    models = [ "llama3:8b" "codellama:13b" ];
  };

  # Enhanced SSH configuration for server
  services.openssh.settings = {
    X11Forwarding = lib.mkForce true;
    PasswordAuthentication = lib.mkForce true;  # Temporary - for SSH key update
  };
  services.tailscale.permitCertUid = lib.mkIf config.services.caddy.enable "caddy";
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

  # BULLETPROOF: Override user secrets for server reliability
  hwc.system.users.user = {
    useSecrets = lib.mkForce false;
    fallbackPassword = lib.mkForce "il0wwlm?";
    ssh.useSecrets = lib.mkForce false;  # Force fallback SSH key
  };

  # BULLETPROOF: Ensure emergency root access works
  hwc.secrets.emergency = {
    enable = lib.mkForce true;
    password = lib.mkForce "il0wwlm?";
  };

  system.stateVersion = "24.05";
}
