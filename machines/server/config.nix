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
    ../../domains/server/frigate/index.nix  # Config-first pattern NVR with GPU acceleration
    ../../profiles/monitoring.nix   # Monitoring enabled: Prometheus + Grafana
    # ../../profiles/media.nix         # TODO: Fix sops/agenix conflict in orchestrator
    # ../../profiles/business.nix      # TODO: Enable when business services are implemented
  ];

  # System identity
  networking.hostName = "hwc-server";
  networking.hostId = "8425e349";

  # ZFS support for backup drives
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # Charter v3 path configuration (matching production)
  hwc.paths = {
    hot = "/mnt/hot";      # SSD hot storage
    media = "/mnt/media";  # HDD media storage
    cold = "/mnt/media";   # Cold storage same as media for now
    # Additional paths from production
    business.root = "/opt/business";
    cache = "/opt/cache";
  };

  # Storage infrastructure configuration (Charter v6.0 compliant)
  hwc.infrastructure.storage = {
    hot = {
      enable = true;
      device = "/dev/disk/by-uuid/fd7a9820-a3e2-45cb-9c97-9fd904ee459a";
      fsType = "ext4";
    };
    media.enable = true;   # Directory management only (mount defined below)
    backup.enable = true;  # Enable backup drive automation
  };

  # Media storage mount (infrastructure module manages directories only)
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

  # ntfy notification system for server alerts
  # Multi-topic architecture: critical, alerts, backups, media, monitoring, updates, ai
  # See: docs/infrastructure/ntfy-notification-classes.md
  hwc.system.services.ntfy = {
    enable = false;
    serverUrl = "https://hwc.ocelot-wahoo.ts.net:2586";  # Self-hosted ntfy via Tailscale port mode
    defaultTopic = "hwc-server-events";  # General server events
    defaultTags = [ "hwc" "server" "production" ];
    defaultPriority = 4;  # Higher priority for server alerts
    hostTag = true;       # Adds "host-hwc-server" tag automatically

    # Authentication disabled for self-hosted (can enable if needed)
    auth.enable = false;
    # To enable auth, add secrets and configure:
    # auth = {
    #   enable = true;
    #   method = "token";
    #   tokenFile = "/run/secrets/ntfy-token";
    # };
  };

  # System monitoring with ntfy notifications
  # TODO: Implement monitoring module
  # hwc.system.services.monitoring = {
  #   enable = true;
  #
  #   # Disk space monitoring (hourly checks)
  #   diskSpace = {
  #     enable = true;
  #     frequency = "hourly";
  #     filesystems = [ "/" "/home" "/mnt/media" "/mnt/hot" ];
  #   };
  #
  #   # Service failure notifications
  #   serviceFailures = {
  #     enable = true;
  #     monitoredServices = [
  #       "backup-local"
  #       "podman-immich"
  #       "podman-jellyfin"
  #       "podman-navidrome"
  #       "podman-frigate"
  #       "couchdb"
  #       "podman-ntfy"
  #       "caddy"
  #     ];
  #   };
  # };

  # Backup configuration for server
  # Supports external drives, NAS, or DAS for local backups
  hwc.system.services.backup = {
    enable = true;

    # Local backup to external storage (NAS, DAS, or external drive)
    local = {
      enable = true;
      mountPoint = "/mnt/backup";  # Mount your backup drive/NAS here
      keepDaily = 14;   # Keep 14 daily backups (2 weeks)
      keepWeekly = 8;   # Keep 8 weekly backups (2 months)
      keepMonthly = 12; # Keep 12 monthly backups (1 year)
      minSpaceGB = 50;  # Require 50GB free space for server
      sources = [
        "/home"
        "/etc/nixos"
        "/mnt/media"       # Include media storage
        "/mnt/photos"      # Immich photo library (CRITICAL)
        "/var/backup/immich-db"  # Immich database backups
        "/opt/business"    # Include business data
      ];
    };

    # Cloud backup as additional offsite backup (optional)
    cloud.enable = false;  # Set to true to enable cloud backup
    protonDrive.enable = false;  # TODO: Configure rclone-proton-config secret

    # Automatic scheduling
    schedule = {
      enable = true;
      frequency = lib.mkForce "weekly";  # Weekly backups for server
      timeOfDay = lib.mkForce "03:00";   # Run at 3 AM on the scheduled day
      onlyOnAC = lib.mkForce false;      # Server is always plugged in
    };

    # Notification configuration
    notifications = {
      enable = true;
      onSuccess = false;  # Don't notify on success to reduce noise
      onFailure = true;   # Always notify on failure

      # ntfy integration for remote notifications
      ntfy = {
        enable = true;
        topic = "hwc-critical";  # Backup failures are critical (P5)
        onSuccess = false;  # No success notifications (or use "hwc-backups" if desired)
        onFailure = true;   # Send critical alert on backup failures
      };
    };
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
  hwc.ai.ollama = {
    enable = true;
    # Optimized models for 4GB VRAM GPU (Quadro P1000) - guaranteed to fit in VRAM
    # Note: Load one at a time due to VRAM constraints (1.9GB + 2.3GB = 4.2GB)
    models = [
      "qwen2.5-coder:3b"              # 1.9GB - Best coding model that fits in 4GB VRAM
      "phi3:3.8b"                     # 2.3GB - General purpose, excellent quality
      "llama3.2:3b"                   # 2.0GB - Chat, summarization, journaling
    ];
  };

  # Local AI workflows and automation
  hwc.ai.local-workflows = {
    enable = true;

    # AI-powered file cleanup agent
    fileCleanup = {
      enable = true;
      watchDirs = [ "/mnt/hot/inbox" "/home/eric/Downloads" ];
      schedule = "*:0/30";  # Every 30 minutes
      model = "qwen2.5-coder:3b";
      dryRun = false;  # Set to true for testing
    };

    # Automatic daily journaling
    journaling = {
      enable = true;
      outputDir = "/home/eric/Documents/HWC-AI-Journal";
      sources = [ "systemd-journal" "container-logs" "nixos-rebuilds" ];
      schedule = "daily";
      timeOfDay = "02:00";
      model = "llama3.2:3b";
      retentionDays = 90;
    };

    # Auto-documentation generator (CLI tool)
    autoDoc = {
      enable = true;
      model = "qwen2.5-coder:3b";
    };

    # Interactive chat CLI
    chatCli = {
      enable = true;
      model = "llama3:8b";  # Better instruction following than qwen2.5-coder
      # systemPrompt inherited from domain default
    };

    # Workflows HTTP API (Sprint 5.4)
    api = {
      enable = true;
      port = 6021;
      # All other settings use defaults from domain options
    };
  };

  # Open WebUI - Modern web interface for Ollama
  # Access: https://hwc.ocelot-wahoo.ts.net:3443 (via Caddy port mode)
  hwc.ai.open-webui = {
    enable = true;
    enableAuth = false;  # TEMPORARY: Disabled to bypass signup page rendering issue
    # All other settings use defaults:
    # - port: 3001
    # - defaultModel: "phi3:3.8b"
    # - enableRAG: true
  };

  # MCP (Model Context Protocol) server for LLM access
  # Provides filesystem access to ~/.nixos for AI assistants
  hwc.ai.mcp = {
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

    # Expose via Caddy at /mcp
    reverseProxy.enable = true;
  };

  # Automated server backups (containers, databases, system)
  # Backups saved to /mnt/hot/backups with daily schedule
  hwc.server.backup.enable = true;
  # Enable AI router and agent on server
  hwc.ai.router = {
    enable = true;
    port = 11435;
  };
  hwc.ai.agent = {
    enable = true;
    port = 6020;
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

  # ntfy notification server (container)
  # Provides notification server for hwc-ntfy-send client
  hwc.services.ntfy = {
    enable = false;
    port = 9999;  # Internal port - Caddy forwards external 2586 to this
    dataDir = "/var/lib/hwc/ntfy";
  };

  # Frigate NVR (Config-First Pattern with GPU Acceleration)
  # Access: https://hwc.ocelot-wahoo.ts.net:5443 (via Caddy)
  # Charter v7.0 Section 19 compliant - TensorRT CUDA support
  hwc.server.frigate = {
    enable = true;

    # Internal port 5001 (exposed as 5443 via Caddy)
    port = 5001;

    # GPU acceleration for ONNX object detection (TensorRT + CUDA)
    gpu = {
      enable = true;
      device = 0;  # NVIDIA P1000
    };

    # Storage paths
    storage = {
      configPath = "/opt/surveillance/frigate/config";
      mediaPath = "/mnt/media/surveillance/frigate/media";
      bufferPath = "/mnt/hot/surveillance/frigate/buffer";
    };

    # Firewall settings
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
    X11Forwarding = lib.mkForce false;  # Headless server doesn't need X11 forwarding
    PasswordAuthentication = lib.mkForce true;  # Temporary - for SSH key update
  };

  # Passwordless sudo for ai-chat tool commands
  hwc.system.services.session.sudo.extraRules = [
    {
      users = [ "eric" ];
      commands = [
        { command = "/run/current-system/sw/bin/podman"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/journalctl"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];
  services.tailscale.permitCertUid = lib.mkIf config.services.caddy.enable "caddy";
  # X11 services disabled for headless server
  # services.xserver.enable = true;

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

