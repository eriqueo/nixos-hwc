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
    ../../profiles/monitoring.nix   # Monitoring enabled: Prometheus + Grafana
    # ../../profiles/media.nix         # TODO: Fix sops/agenix conflict in orchestrator
    # ../../profiles/business.nix      # TODO: Enable when business services are implemented
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
    waitOnline.timeoutSeconds = 30;  # Reduced from 90s for faster boot

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

  # P1000 (Pascal) with driver 580 - last full-support branch before legacy transition
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;  # 580.95.05
    open = lib.mkForce false;  # Pascal doesn't support open-source modules
    gsp.enable = lib.mkForce false;  # Pascal doesn't support GSP firmware
  };

  # NVIDIA license acceptance handled in flake.nix

  # GPU acceleration for Immich handled by hwc.server.immich.gpu.enable in server profile

  # AI services configuration
  hwc.server.ai.ollama = {
    enable = true;
    # Optimized models for 4GB VRAM GPU (Quadro P1000) - guaranteed to fit in VRAM
    models = [
      "qwen2.5-coder:3b"              # 1.9GB - Best coding model that fits in 4GB VRAM
      "phi3:3.8b-mini-instruct-4k"    # 2.3GB - General purpose, excellent quality
    ];
  };

  # MCP (Model Context Protocol) server for LLM access
  hwc.server.ai.mcp = {
    enable = true;

    # Filesystem MCP for ~/.nixos directory
    filesystem.nixos = {
      enable = true;
      # Defaults:
      # - allowedDirs: ["/home/eric/.nixos" "/home/eric/.nixos-mcp-drafts"]
      # - user: "eric"
    };

    # HTTP proxy for remote access
    proxy.enable = true;  # Listen on localhost:6001

    # Expose via Caddy at /mcp-nixos
    reverseProxy.enable = true;
  };

  # TODO: Re-enable Fabric when Go 1.25 / nixpkgs compatibility is resolved
  # # Fabric AI integration
  # hwc.system.apps.fabric = {
  #   enableApi = true;
  #   provider = "openai";
  #   model = "gpt-4o-mini";
  #   api = {
  #     listenAddress = "127.0.0.1";
  #     port = 8080;
  #     envFile = config.age.secrets.fabric-server-env.path;
  #     openFirewall = false;  # Only accessible via Tailscale reverse proxy
  #   };
  # };

  # Automated server backups (containers, databases, system)
  # Backups saved to /mnt/hot/backups with daily schedule
  hwc.server.backup.enable = true;

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
      detector = "onnx";  # ONNX with CUDA for GPU acceleration (TensorRT deprecated on amd64)
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

  # Feature enablement
  hwc.features = {
    monitoring.enable = true;     # Prometheus + Grafana monitoring stack
    # media.enable = true;        # TODO: Fix sops/agenix conflict
    # business.enable = true;     # TODO: Enable when business containers are implemented
  };

  # Enhanced SSH configuration for server
  services.openssh.settings = {
    X11Forwarding = lib.mkForce false;  # Disabled for security - use SSH tunneling instead
    PasswordAuthentication = lib.mkForce false;  # SSH keys only for security
  };
  services.tailscale.permitCertUid = lib.mkIf config.services.caddy.enable "caddy";

  # Server-specific packages moved to modules/system/server-packages.nix
  hwc.system.packages.server.enable = true;

  # I/O scheduler and journald configuration moved to profiles/server.nix to avoid duplication
  # This eliminates conflicts between machine and profile configurations

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
