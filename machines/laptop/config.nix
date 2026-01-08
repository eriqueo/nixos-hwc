# nixos-hwc/machines/laptop/config.nix
#
# MACHINE: HWC-LAPTOP
# Declares machine identity and composes profiles; states hardware reality.
# Follows the refactored system domain architecture.

{ config, lib, pkgs, ... }:

{
  ##############################################################################
  ##  MACHINE: HWC-LAPTOP
  ##  This file defines the unique properties and profile composition for the
  ##  hwc-laptop machine.
  ##############################################################################

  #============================================================================
  # IMPORTS - Compose the machine from profiles and hardware definitions
  #============================================================================
  imports = [
    # Hardware-specific definitions for this machine (e.g., filesystems).
    ./hardware.nix

    # Profiles that define the machine's capabilities.
    # The system.nix profile is now the main entry point for all system services.
    ../../profiles/system.nix
    ../../profiles/home.nix
    ../../profiles/security.nix
    ../../profiles/ai.nix  # Enable local AI for laptop

    # Infrastructure domain for GPU only (not storage)
    ../../domains/infrastructure/hardware/index.nix

    # Virtualization domain for WinApps/VMs (without full infrastructure profile)
    ../../domains/infrastructure/virtualization/index.nix

    # WinApps domain for Windows application integration
    ../../domains/infrastructure/winapps/index.nix
  ];

  # Blender 3D modeling with GPU rendering support (configured in profiles/home.nix)
  # External presets stored in ~/500_media/540_blender

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "hwc-laptop";
  system.stateVersion = "24.05";

  # Hibernation support
  boot.resumeDevice = "/dev/disk/by-uuid/0ebc1df3-65ec-4125-9e73-2f88f7137dc7";
  boot.kernelParams = [ "resume_offset=0" ]; # Will be auto-calculated by NixOS

  # Power management for laptop
  powerManagement.enable = true;
  services.logind = {
    # All settings are now consolidated under the 'settings' attribute set.
    settings = {
      Login = {
        # Ignore lid close to prevent suspend during remote access
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        # From your previous fix
        HandlePowerKey = "hibernate";
        # Disable idle suspend (laptop left running for extended period)
        IdleAction = "ignore";
        # IdleActionSec = "30min";  # Disabled - no idle action configured
      };
    };
  };

  #============================================================================
  # === [profiles/system.nix] Orchestration ====================================
  #============================================================================

  # --- System Services Configuration ---
  # Enable the core shell environment with development tools.
  hwc.system.services.shell = {
    enable = true;
    development.enable = true;
  };

  # Enable hardware services for keyboard remapping and audio.
  hwc.system.services.hardware = {
    enable = true;
    keyboard.enable = true;
    audio.enable = true;
    bluetooth.enable = true;
    monitoring.enable = true;
    fanControl.enable = true;
  };

  # ntfy notification system for laptop alerts
  # Multi-topic architecture: critical, alerts, backups, media, monitoring, updates, ai
  # See: docs/infrastructure/ntfy-notification-classes.md
  hwc.system.services.ntfy = {
    enable = true;
    serverUrl = "https://hwc.ocelot-wahoo.ts.net/notify";  # Self-hosted ntfy via Tailscale at /notify subpath
    defaultTopic = "hwc-laptop-events";  # General laptop events
    defaultTags = [ "hwc" "laptop" ];
    defaultPriority = 3;  # Normal priority for laptop
    hostTag = true;       # Adds "host-hwc-laptop" tag automatically

    # Authentication disabled for self-hosted (can enable if needed)
    auth.enable = false;
    # To enable auth, add secrets and configure:
    # auth = {
    #   enable = true;
    #   method = "token";
    #   tokenFile = "/run/secrets/ntfy-token";
    # };
  };

  # Backup configuration for laptop
  # Supports plugging in external drives for local backups
  hwc.system.services.backup = {
    enable = true;

    # Local backup when external drive is connected
    local = {
      enable = true;
      mountPoint = "/mnt/backup";  # Mount your external drive here
      keepDaily = 5;    # Keep 5 daily backups
      keepWeekly = 2;   # Keep 2 weekly backups
      keepMonthly = 3;  # Keep 3 monthly backups
      minSpaceGB = 20;  # Require 20GB free space
    };

    # Cloud backup as fallback (optional)
    cloud.enable = false;  # Set to true to enable cloud backup
    protonDrive.enable = false;  # TODO: Configure rclone-proton-config secret

    # Notifications configuration
    notifications = {
      enable = true;
      ntfy = {
        enable = true;
        onSuccess = false;
        topic = "hwc-critical";  # Backup failures are critical (P5)
        onFailure = true;
      };
    };

    # Disable automatic scheduling to avoid backups during rebuild; run manually when desired
    schedule.enable = false;

  };

  # Enable the declarative VPN service using the official CLI.
  hwc.system.services.vpn.protonvpn.enable = true;

  # Enable session management (greetd autologin, sudo, lingering).
  hwc.system.services.session = {
    enable = true;
    loginManager.enable = true;
    loginManager.autoLoginUser = "eric";
    sudo.enable = true;
    sudo.extraRules = [
      # Allow eric to start/stop ollama service without password (for waybar toggle)
      {
        users = [ "eric" ];
        commands = [
          { command = "/run/current-system/sw/bin/systemctl start podman-ollama.service"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl stop podman-ollama.service"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
    linger.enable = true;
    linger.users = [ "eric" ];
  };

  # --- Networking Configuration (Laptop: do NOT block boot on network) ---
  hwc.networking = {
    enable = true;
    networkManager.enable = true;

    # Laptop should not wait-online; Hyprland can start immediately.
    waitOnline.mode = "off";

    ssh.enable = true;            # Enable the SSH server.
    firewall.level = "strict";
    tailscale.enable = true;
    tailscale.extraUpFlags = [ "--accept-dns" ];
  };

  #============================================================================
  # === [domains/infrastructure/hardware] Orchestration ========================
  #============================================================================

  # GPU capability (remains unchanged).
  hwc.infrastructure.hardware.gpu = {
    enable = true;
    type = "nvidia";
    nvidia = {
      containerRuntime = true;
      prime.enable = true;
      prime.nvidiaBusId = "PCI:1:0:0";
      prime.intelBusId  = "PCI:0:2:0";
    };
    powerManagement.smartToggle = true;
  };

  # Override NVIDIA power management defaults for proper suspend/resume
  # Fixes GPU state corruption in applications (like Kitty) after resume
  hardware.nvidia.powerManagement = {
    enable = true;           # Enable power management for suspend/resume
    finegrained = false;     # Use full power management, not fine-grained
  };

  #============================================================================
  # === [domains/infrastructure/virtualization] Orchestration ==================
  #============================================================================
  # Minimal virtualization for WinApps/VMs. We avoid pulling full infra profile.
  hwc.infrastructure.virtualization = {
    enable = true;
    spiceSupport = false;  # no SPICE USB redirection on laptop
  };

  # WinApps configuration for Excel access
  hwc.infrastructure.winapps = {
    enable = true;
    rdpSettings = {
      vmName = "RDPWindows";
      ip = "192.168.122.10";  # Update this after VM creation
      user = "eric";  # Update with Windows username
    };
    multiMonitor = true;
    debug = false;
  };

  # Fabric AI integration - REMOVED
  # The Fabric app configuration has been removed from the system.
  # See commit: refactor: cleanup unused AI tools and improve server configuration

  # Libvirt/QEMU: make OVMF visible and avoid extra groups by using wheel sockets.
  virtualisation.libvirtd = {
    # Use wheel for socket perms so you don't need extra groups.
    extraConfig = ''
      unix_sock_group = "wheel"
      unix_sock_ro_perms = "0770"
      unix_sock_rw_perms = "0770"
    '';

    # OVMF is now available by default with QEMU
    qemu = {
      runAsRoot = lib.mkForce true;     # fixes OVMF metadata enumeration edge cases
      # OVMF images are now available by default in newer versions
    };
  };

  # Container engines enabled for Ollama AI workloads
  # Podman is required by hwc.ai.ollama module
  virtualisation.docker.enable = lib.mkForce false;  # Use podman, not docker

  # --- Declarative libvirt storage pool (requires NixVirt in flake) --
  # Commented out until NixVirt module is imported in flake.nix
  # virtualisation.libvirt.pools = [
  #   {
  #     name = "ISOs";
  #     present = true;
  #     type = "dir";
  #     target = {
  #       path = "${config.hwc.paths.hot}/ISOs";
  #       owner = "root";
  #       group = "root";
  #       mode  = "0755";
  #     };
  #     autostart = true;
  #   }
  # ];

  #============================================================================
  # === [profiles/home.nix] Orchestration =====================================
  #============================================================================
  # System-lane dependencies for home apps (co-located sys.nix files)
  # These are enabled separately because system evaluates before Home Manager
  hwc.system.apps.hyprland.enable = true;   # Startup script, helper scripts
  hwc.system.apps.waybar.enable = true;     # System dependency validation
  hwc.system.apps.chromium.enable = true;   # System integration (dconf, dbus)

  #============================================================================
  # === [profiles/security.nix] Orchestration =================================
  #============================================================================
  # (Profile-driven; nothing machine-specific added here.)

  #============================================================================
  # MISCELLANEOUS MACHINE-SPECIFIC SETTINGS
  #============================================================================

  # Storage paths (remains unchanged).
  hwc.paths.hot.root = "/home/eric/500_media/";

  # Home applications
  home-manager.users.eric.hwc.home.apps.qbittorrent.enable = true;
  home-manager.users.eric.hwc.home.apps.wayvnc.enable = false;

  # Enable shell environment with MCP configuration
  home-manager.users.eric.hwc.home.shell = {
    enable = true;
    mcp = {
      enable = true;
      includeConfigDir = false;  # Laptop: don't expose ~/.config to Claude
      includeServerTools = false;  # Laptop: no server MCP tools needed
    };
  };

  #============================================================================
  # AI SERVICES CONFIGURATION (Laptop)
  #============================================================================
  # Laptop has superior hardware (32GB RAM, better GPU) for larger models
  hwc.ai.ollama = {
    enable = false;  # Disabled by default, toggle with waybar button
    # Larger models suitable for 32GB RAM + RTX GPU
    models = [
      "qwen2.5-coder:7b"              # 4.3GB - Primary coding assistant
      "llama3.2:3b"                   # 2.0GB - Fast queries, battery mode
      "mistral:7b-instruct"           # 4.1GB - General reasoning
    ];

    # Aggressive resource limits for laptop (prevent fan noise)
    resourceLimits = {
      enable = true;
      maxCpuPercent = 300;          # Max 3 cores (leave 13 cores for other work)
      maxMemoryMB = 6144;            # Max 6GB (out of 32GB total)
      maxRequestSeconds = 180;       # Kill any request over 3 minutes
    };

    # Auto-shutdown after idle (perfect for grebuild sprints)
    idleShutdown = {
      enable = true;
      idleMinutes = 15;              # Shutdown after 15min of inactivity
      checkInterval = "2min";         # Check every 2 minutes
    };

    # Thermal protection (critical for laptop)
    thermalProtection = {
      enable = true;
      warningTemp = 75;              # Start warning at 75°C
      criticalTemp = 85;             # Emergency stop at 85°C
      checkInterval = "30s";          # Check every 30 seconds
      cooldownMinutes = 10;          # 10min cooldown after thermal shutdown
    };
  };

  # Local AI workflows for laptop
  hwc.ai.local-workflows = {
    enable = false;  # Disabled by default (requires Ollama to be running)

    # File cleanup for Downloads
    fileCleanup = {
      enable = true;
      watchDirs = [ "/home/eric/Downloads" ];
      schedule = "hourly";
      model = "llama3.2:3b";  # Use smaller model for battery efficiency
      dryRun = false;
    };

    # Journaling (less frequent on laptop)
    journaling = {
      enable = true;
      outputDir = "/home/eric/Documents/HWC-AI-Journal";
      sources = [ "systemd-journal" "nixos-rebuilds" ];
      schedule = "weekly";  # Weekly on laptop vs daily on server
      timeOfDay = "02:00";
      model = "llama3.2:3b";
    };

    # Auto-documentation
    autoDoc = {
      enable = true;
      model = "qwen2.5-coder:7b";  # Use larger model on laptop
    };

    # Chat CLI with better model
    chatCli = {
      enable = true;
      model = "mistral:7b-instruct";  # Larger model for better quality
    };
  };

  # Static hosts for local services (remains unchanged).
  networking.hosts = {
    "100.115.126.41" = [
      "sonarr.local" "radarr.local" "prowlarr.local" "jellyfin.local"
      "lidarr.local" "qbittorrent.local" "grafana.local" "dashboard.local"
      "prometheus.local" "caddy.local" "server.local" "hwc.local"
    ];
  };

  #============================================================================
  # LOW-LEVEL SYSTEM OVERRIDES (Use Sparingly)
  #============================================================================
  # Power management: TLP handles thermal + power (thermald conflicts with TLP)
  services.tlp = {
    enable = true;
    settings = {
      # CPU performance settings
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      # Battery charge thresholds (extends battery life)
      START_CHARGE_THRESH_BAT0 = 75;  # Start charging at 75%
      STOP_CHARGE_THRESH_BAT0 = 80;   # Stop charging at 80%

      # Power saving on battery
      WIFI_PWR_ON_BAT = "on";
      WOL_DISABLE = "Y";

      # USB autosuspend
      USB_AUTOSUSPEND = 1;

      # SATA power management
      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
    };
  };

  programs.dconf.enable = true;
}
