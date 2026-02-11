# nixos-hwc/machines/xps/config.nix
#
# MACHINE: HWC-XPS
# Declares machine identity and composes profiles; states hardware reality.
# Dell XPS 2018 laptop configured as remote backup server with desktop environment

{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/system.nix
    ../../profiles/home.nix         # Home Manager domain menu
    ../../profiles/server.nix
    ../../profiles/security.nix
    ../../profiles/ai.nix
    ../../domains/server/native/routes.nix
    # NOTE: Frigate NOT imported - no surveillance cameras at remote location
    ../../profiles/monitoring.nix   # Monitoring enabled: Prometheus + Grafana
    # ../../profiles/media.nix         # TODO: Fix sops/agenix conflict in orchestrator
    # ../../profiles/business.nix      # TODO: Enable when business services are implemented
  ];

  # System identity
  networking.hostName = "hwc-xps";
  networking.hostId = "a7c3d821";  # Generated: head -c 8 /dev/urandom | od -A n -t x1 | tr -d ' '

  # MIGRATION FIX: Use actual working password hash from hwc-kids
  # This overrides the fallback password from domains/system/users/options.nix
  # Using hashedPassword directly since secrets/age not configured yet
  users.users.eric.hashedPassword = "$6$XeiiTwbz$qYPx.U2Gj0K4BiKqqniBbI9m2WWU9.rKelkJceqjXlgbnXRcbsbQ8idxmj28FK2mjjtOqU5aKV4oYQt3Wa91f.";

  # Keep mutableUsers = false for security (declarative password management)
  # users.mutableUsers stays false (default from domains/system/users/eric.nix)

  # ZFS support for backup drives (if needed)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # ZFS configuration (if using ZFS for backups)
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";  # Monthly scrub for data integrity
    };
    trim = {
      enable = true;
      interval = "weekly";  # Weekly TRIM for performance
    };
  };

  # Charter v10.1 path configuration (hostname-based defaults)
  # XPS hostname detection provides defaults:
  #   hot.root = "/mnt/hot"          (Internal SSD hot storage)
  #   media.root = "/mnt/media"      (External DAS cold storage)
  #   cold = "/mnt/media"            (Cold storage, same as media)
  #   photos = "/mnt/photos"         (Not used on XPS - Immich disabled)
  #   business.root = "/opt/business"
  # No overrides needed - all defaults match requirements

  # Storage infrastructure configuration (Charter v10.1 compliant)
  # DISABLED: External storage not yet configured
  hwc.infrastructure.storage = {
    hot = {
      enable = false;  # DISABLED: No /mnt/hot partition yet
      # device = "/dev/disk/by-uuid/PLACEHOLDER-HOT-UUID";
      # fsType = "ext4";
    };
    media.enable = false;   # DISABLED: External DAS not connected yet
    backup.enable = false;  # DISABLED: External backup drive not configured yet
  };

  # Root filesystem mount (will be generated in hardware.nix)
  # Uncomment and update UUID during installation:
  # fileSystems."/" = {
  #   device = "/dev/disk/by-uuid/PLACEHOLDER-ROOT-UUID";
  #   fsType = "ext4";
  # };

  # Boot filesystem mount (will be generated in hardware.nix)
  # fileSystems."/boot" = {
  #   device = "/dev/disk/by-uuid/PLACEHOLDER-BOOT-UUID";
  #   fsType = "vfat";
  # };

  # Media storage mount (external DAS with 2x3TB HDDs)
  # DISABLED: External DAS not connected yet
  # fileSystems."/mnt/media" = {
  #   device = "/dev/disk/by-label/media";  # Or use UUID after setup
  #   fsType = "ext4";
  # };

  # Backup storage mount (external DAS partition)
  # DISABLED: External backup drive not configured yet
  # fileSystems."/mnt/backup" = {
  #   device = "/dev/disk/by-label/backup";  # Or use UUID after setup
  #   fsType = "ext4";
  # };

  # Swap file for laptop (16GB recommended)
  swapDevices = [ { device = "/var/swapfile"; size = 16384; } ];

  # Time zone
  time.timeZone = "America/Denver";

  # Production system settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # allowUnfree set in flake.nix

  # --- Networking Configuration (Server: DO wait for network) ---
  hwc.system.networking = {
    enable = true;
    networkManager.enable = true;

    # Wait for network (important for Tailscale and remote services)
    waitOnline.mode = "all";
    waitOnline.timeoutSeconds = 30;

    ssh.enable = true;
    tailscale.enable = true;
    tailscale.funnel.enable = false;  # Using port mode like hwc-server
    firewall.level = lib.mkForce "server";
    firewall.extraTcpPorts = [ 8096 7359 2283 4533 ];  # Jellyfin, Ollama (optional), Immich (future), Navidrome
    firewall.extraUdpPorts = [ 7359 ];  # Jellyfin discovery
  };

  # Power Management (Laptop-Specific)
  # Keep laptop running 24/7 as server
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      # Prevent aggressive power saving when plugged in
      PCIE_ASPM_ON_AC = "default";
      RUNTIME_PM_ON_AC = "auto";
    };
  };

  # Laptop lid management (keep running when closed)
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # Thermal management for 24/7 operation
  services.thermald.enable = true;

  # ntfy notification system CLI client for server alerts
  # Multi-topic architecture: critical, alerts, backups, media, monitoring, updates, ai
  hwc.system.services.ntfy = {
    enable = false;  # Can enable after configuring server URL
    serverUrl = "https://hwc-xps.ocelot-wahoo.ts.net:2586";  # TODO: Update with correct Tailscale domain
    defaultTopic = "hwc-xps-events";  # General XPS server events
    defaultTags = [ "hwc" "xps" "production" ];
    defaultPriority = 4;  # Higher priority for server alerts
    hostTag = true;       # Adds "host-hwc-xps" tag automatically

    # Authentication disabled for self-hosted (can enable if needed)
    auth.enable = false;
  };

  # Backup configuration for XPS server
  hwc.system.services.backup = {
    enable = lib.mkForce false;  # DISABLED: /mnt/backup not configured yet

    # Local backup to external DAS
    local = {
      enable = lib.mkForce false;  # DISABLED: /mnt/backup not mounted
      mountPoint = "/mnt/backup";  # External DAS backup partition
      keepDaily = 7;    # Keep 7 daily backups (1 week)
      keepWeekly = 4;   # Keep 4 weekly backups (1 month)
      keepMonthly = 6;  # Keep 6 monthly backups (6 months)
      minSpaceGB = 50;  # Require 50GB free space

      # CRITICAL DATA ONLY (smaller backup than main server)
      sources = [
        "/home"                     # User data, configs, nixos repo
        # "/opt/business"           # Business data (if any) - DISABLED: not configured yet
        # "/mnt/media/databases"    # Database backups - DISABLED: /mnt/media not mounted
        # "/mnt/media/backups"      # Other backups - DISABLED: /mnt/media not mounted
        # NOTE: /home/eric/.nixos is backed up via /home
        # EXCLUDED (replaceable):
        # "/mnt/media/movies"       # Can re-download
        # "/mnt/media/tv"           # Can re-download
        # "/mnt/media/music"        # Can re-download
      ];

      # Exclude patterns for backup efficiency
      excludePatterns = [
        ".cache"
        "*.tmp"
        "*.temp"
        ".local/share/Trash"
        "node_modules"
        "__pycache__"
        ".npm"
        ".cargo/registry"
        ".cargo/git"
      ];
    };

    # Cloud backup disabled (optional future enhancement)
    cloud.enable = false;
    protonDrive.enable = false;

    # Automatic scheduling
    schedule = {
      enable = true;
      frequency = lib.mkForce "weekly";  # Weekly backups
      timeOfDay = lib.mkForce "03:00";   # Run at 3 AM
      onlyOnAC = lib.mkForce false;      # Server is always plugged in
    };

    # Notification configuration
    notifications = {
      enable = true;
      onSuccess = false;  # Don't notify on success
      onFailure = true;   # Always notify on failure

      # ntfy integration
      ntfy = {
        enable = true;
        topic = "hwc-critical";  # Backup failures are critical
        onSuccess = false;
        onFailure = true;
      };
    };
  };

  # GPU Configuration (depends on hardware)
  # Check during installation: lspci | grep -i vga
  # If NVIDIA MX150 present, enable GPU support
  # If Intel integrated only, keep disabled or configure for VA-API
  hwc.infrastructure.hardware.gpu = {
    enable = lib.mkDefault false;  # Disabled by default, enable if GPU detected
    # Uncomment and configure if NVIDIA MX150 present:
    # type = "nvidia";
    # nvidia = {
    #   driver = "stable";
    #   containerRuntime = true;
    #   enableMonitoring = true;
    # };
  };

  # Disable heavyweight creative/productivity apps on the backup laptop build
  home-manager.users.eric.hwc.home.apps = {
    blender.enable = lib.mkForce false;
    freecad.enable = lib.mkForce false;
    obsidian.enable = lib.mkForce false;
    onlyoffice-desktopeditors.enable = lib.mkForce false;
    slack.enable = lib.mkForce false;
    bottles-unwrapped.enable = lib.mkForce false;
  };

  # Desktop Environment - System-lane dependencies
  hwc.system.apps.hyprland.enable = true;  # Startup script, helper scripts
  hwc.system.apps.waybar.enable = true;    # Waybar system dependencies
  hwc.system.apps.chromium.enable = true;  # Chromium system integration (dconf, dbus)

  # Display manager (greetd for Wayland)
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  # AI DOMAIN CONFIGURATION (Laptop Server)
  #============================================================================
  # Explicit laptop profile selection for conservative thermal limits
  hwc.ai = {
    enable = true;

    # Explicit laptop profile selection
    profiles.selected = "laptop";

    # AI CLI tools disabled (conflicts with local-workflows post-rebuild-ai-docs service)
    tools.enable = false;

    # Ollama could be enabled later for on-device LLMs
    ollama.enable = false;

    # Disable automation workloads for the lightweight laptop build
    local-workflows = {
      enable = false;
      fileCleanup.enable = false;
      journaling.enable = false;
      autoDoc.enable = false;
      chatCli.enable = false;
      api.enable = false;
    };
  };

  # Open WebUI - Modern web interface for Ollama
  # Access: https://hwc-xps.ocelot-wahoo.ts.net:3443 (via Caddy port mode)
  # TODO: Update Tailscale domain in routes.nix
  hwc.ai.open-webui = {
    enable = false;
    enableAuth = false;  # TEMPORARY: Disabled to bypass signup page rendering issue
    # All other settings use defaults:
    # - port: 3001
    # - defaultModel: "phi3:3.8b"
    # - enableRAG: true
  };

  # MCP (Model Context Protocol) server for LLM access
  hwc.ai.mcp = {
    enable = false;

    # Filesystem MCP for ~/.nixos directory
    filesystem.nixos = {
      enable = true;
    };

    # HTTP proxy for remote access
    proxy.enable = true;

    # Expose via Caddy at /mcp
    reverseProxy.enable = true;
  };

  # Enable AI router and agent
  hwc.ai.router = {
    enable = false;
    port = 11435;
  };
  hwc.ai.agent = {
    enable = false;
    port = 6020;
  };

  # Server reverse proxy configuration (Tailscale domain)
  hwc.server.shared = {
    tailscaleDomain = "hwc-xps.ocelot-wahoo.ts.net";
    rootHost = "hwc-xps.ocelot-wahoo.ts.net";
  };

  # Automated server backups (containers, databases, system)
  hwc.server.native.backup.enable = true;

  # CouchDB for Obsidian LiveSync
  hwc.server.couchdb = {
    enable = true;
    settings = {
      port = 5984;
      bindAddress = "127.0.0.1";
    };
    monitoring.enableHealthCheck = true;
    reverseProxy = {
      enable = true;
      path = "/sync";
    };
  };

  # ntfy notification server (native service)
  hwc.server.ntfy = {
    enable = true;
    port = 2586;
    dataDir = "/var/lib/hwc/ntfy";
  };

  # Frigate NVR - DISABLED (no cameras at remote location)
  hwc.server.frigate.enable = lib.mkForce false;

  # Immich - DISABLED (primary photo library stays at home)
  # Must use mkForce to override server profile default
  hwc.server.immich.enable = lib.mkForce false;

  # Media Services (independent libraries or synced from home server)
  # Jellyfin, Navidrome, *arr stack all enabled via server profile

  # Feature enablement
  hwc.features = {
    monitoring.enable = true;     # Prometheus + Grafana monitoring stack
    # media.enable = true;        # TODO: Fix sops/agenix conflict
    # business.enable = true;     # TODO: Enable when business containers are implemented
  };

  # Enhanced SSH configuration
  services.openssh.settings = {
    X11Forwarding = lib.mkForce true;   # Enable X11 forwarding for remote GUI access
    PasswordAuthentication = lib.mkForce true;  # Temporary - for SSH key update
  };

  # Passwordless sudo for ai-chat tool commands and grebuild workflow
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

  # Tailscale certificate management for Caddy
  services.tailscale.permitCertUid = lib.mkIf config.services.caddy.enable "caddy";

  # Server-specific packages
  hwc.system.core.packages.server.enable = true;

  # Emergency access via security domain
  # hwc.secrets.emergency.enable is handled by security profile

  # Home Manager Configuration - Desktop Environment for Hybrid Laptop/Server
  # Unlike hwc-server (headless), hwc-xps needs GUI for local work
  # profiles/home.nix provides defaults; we override for desktop environment needs
  # NOTE: home-manager.users.eric already defined in profiles/home.nix, we just override specific apps

  system.stateVersion = "24.05";
}
