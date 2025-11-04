# nixos-hwc/machines/server/config.nix
#
# MACHINE: HWC-SERVER
# Declares machine identity and composes profiles; states hardware reality.

{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/system.nix
    ../../profiles/home.nix
    ../../profiles/server.nix
    ../../profiles/security.nix
    ../../profiles/ai.nix
    ../../domains/server/routes.nix
    # ../../profiles/media.nix         # TODO: Fix sops/agenix conflict in orchestrator
    # ../../profiles/business.nix      # TODO: Enable when business services are implemented
    # ../../profiles/monitoring.nix   # TODO: Enable when monitoring services are fixed
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
    firewall.extraTcpPorts = [ 8096 7359 2283 4533 ];  # Jellyfin, Immich, Navidrome
    firewall.extraUdpPorts = [ 7359 ];  # Jellyfin discovery
  };

  # Machine-specific GPU override for Quadro P1000 (legacy driver required)
  hwc.infrastructure.hardware.gpu = {
    enable = lib.mkForce true;
    type = "nvidia";
    nvidia = {
      driver = "stable";  # Use stable as base, override package below
      containerRuntime = true;
      enableMonitoring = true;
    };
  };

  # P1000 requires legacy driver - override the NVIDIA package and disable modern features
  hardware.nvidia = {
    package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.legacy_470;
    open = lib.mkForce false;  # Legacy driver doesn't support open-source modules
    gsp.enable = lib.mkForce false;  # Legacy driver doesn't support GSP firmware
  };

  # NVIDIA license acceptance handled in flake.nix

  # Enable GPU acceleration for Immich ML (P1000)
  systemd.services.immich-machine-learning = {
    serviceConfig = {
      # Grant GPU device access for ML processing
      DeviceAllow = [
        "/dev/nvidia0 rw"
        "/dev/nvidiactl rw"
        "/dev/nvidia-modeset rw"
        "/dev/nvidia-uvm rw"
        "/dev/nvidia-uvm-tools rw"
        "/dev/dri/card0 rw"
        "/dev/dri/renderD128 rw"
      ];
      SupplementaryGroups = [ "video" "render" ];
    };
    environment = {
      # NVIDIA GPU acceleration for ML workloads
      NVIDIA_VISIBLE_DEVICES = "all";
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      # Critical: Add library path for NVIDIA CUDA libraries
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
      # PyTorch CUDA configuration for P1000 (Pascal, compute capability 6.1)
      CUDA_VISIBLE_DEVICES = "0";
      TORCH_CUDA_ARCH_LIST = "6.1";
      # Fix cache directory permissions
      MPLCONFIGDIR = "/var/cache/immich-machine-learning";
      TRANSFORMERS_CACHE = "/var/cache/immich-machine-learning";
    };
  };

  # AI services configuration
  hwc.server.ai.ollama = {
    enable = false;
    models = [ "llama3:8b" "codellama:13b" ];
  };

  # CouchDB for Obsidian LiveSync
  hwc.server.couchdb = {
    enable = true;
    settings = {
      port = 5984;
      bindAddress = "127.0.0.1";  # Localhost only for security
    };
    monitoring.enableHealthCheck = true;
    reverseProxy = {
      enable = true;  # Expose via Caddy for remote access
      path = "/sync";  # Match Obsidian's expected path
    };
  };

  # Frigate NVR for camera surveillance
  # Access: http://server-ip:5000 (direct port, no reverse proxy)
  # Frigate doesn't support subpaths due to WebSocket/asset serving requirements
  hwc.server.frigate = {
    enable = true;

    gpu = {
      enable = true;
      detector = "cpu";  # Changed from tensorrt - no longer supported on amd64
      useFP16 = false;  # Pascal GPU (P1000) requires FP16 disabled
    };

    mqtt.enable = true;

    monitoring = {
      watchdog.enable = true;
      prometheus.enable = true;
    };

    storage = {
      maxSizeGB = 2000;
      pruneSchedule = "hourly";
    };

    firewall.tailscaleOnly = true;
  };

  # Native Media Services now handled by Charter-compliant domain modules
  # - hwc.server.jellyfin via server profile
  # - hwc.server.immich via server profile
  # - hwc.server.navidrome via server profile

  # Navidrome configuration handled by server profile native service

  # Reverse proxy domain handled by server profile

  # Feature enablement (disabled for initial stability)
  # hwc.features = {
  #   media.enable = true;        # TODO: Fix sops/agenix conflict
  #   business.enable = true;     # TODO: Enable when business containers are implemented
  #   monitoring.enable = true;   # TODO: Enable when monitoring services are fixed
  # };

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

  # Emergency access via security domain (safer than machine-level overrides)
  # hwc.secrets.emergency.enable is handled by security profile

  # Override home profile for headless server - only CLI/shell tools
  home-manager.users.eric = {
    # Disable all GUI applications for headless server
    hwc.home.apps = {
      # Desktop Environment (disable all)
      hyprland.enable = lib.mkForce false;
      waybar.enable = lib.mkForce false;
      swaync.enable = lib.mkForce false;
      kitty.enable = lib.mkForce false;

      # File Management (disable GUI, keep CLI)
      thunar.enable = lib.mkForce false;
      # yazi.enable remains true (CLI tool)

      # Web Browsers (disable all)
      chromium.enable = lib.mkForce false;
      librewolf.enable = lib.mkForce false;

      # Mail Clients (keep CLI, disable GUI)
      # aerc.enable remains true (CLI tool)
      # neomutt.enable remains true (CLI tool)
      betterbird.enable = lib.mkForce false;
      protonMail.enable = lib.mkForce false;
      thunderbird.enable = lib.mkForce false;

      # Security (keep CLI tools)
      # gpg.enable remains true

      # Proton Suite (disable GUI)
      protonAuthenticator.enable = lib.mkForce false;
      protonPass.enable = lib.mkForce false;

      # Productivity & Office (disable all)
      obsidian.enable = lib.mkForce false;
      onlyofficeDesktopeditors.enable = lib.mkForce false;

      # Development & Automation (keep CLI)
      n8n.enable = lib.mkForce false;
      # geminiCli.enable remains true (CLI tool)

      # Utilities (disable GUI)
      wasistlos.enable = lib.mkForce false;
      bottlesUnwrapped.enable = lib.mkForce false;
      localsend.enable = lib.mkForce false;
    };

    # Keep shell/CLI configuration enabled
    hwc.home.shell.enable = true;
    hwc.home.development.enable = true;

    # Disable mail for server (no GUI mail needed)
    hwc.home.mail.enable = lib.mkForce false;

    # Disable desktop features for headless server
    hwc.home.fonts.enable = lib.mkForce false;

    # Disable desktop services that try to use dconf
    targets.genericLinux.enable = false;
    dconf.enable = lib.mkForce false;
  };

  system.stateVersion = "24.05";
}
