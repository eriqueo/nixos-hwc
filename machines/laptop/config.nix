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

    # Vault sync system for Obsidian (remains unchanged).
    ../../workspace/infrastructure/vault-sync-system.nix

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

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "hwc-laptop";
  system.stateVersion = "24.05";

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
  };

  # ntfy notification system for laptop alerts
  hwc.system.services.ntfy = {
    enable = true;
    serverUrl = "https://ntfy.sh";
    defaultTopic = "hwc-laptop-events";
    defaultTags = [ "hwc" "laptop" ];
    defaultPriority = 3;  # Normal priority for laptop
    hostTag = true;       # Adds "host-hwc-laptop" tag automatically

    # Authentication disabled for public topics (enable for private)
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
      keepDaily = 7;    # Keep 7 daily backups
      keepWeekly = 4;   # Keep 4 weekly backups
      keepMonthly = 3;  # Keep 3 monthly backups
      minSpaceGB = 20;  # Require 20GB free space
    };

    # Cloud backup as fallback (optional)
    cloud.enable = false;  # Set to true to enable cloud backup
    protonDrive.enable = false;  # TODO: Configure rclone-proton-config secret

    # Automatic scheduling
    schedule = {
      enable = true;
      frequency = "daily";
      timeOfDay = "02:00";  # Run at 2 AM
      onlyOnAC = true;  # Only backup when plugged in
    };

    # Notification configuration
    notifications = {
      enable = true;
      onSuccess = false;  # Don't notify on success to reduce noise
      onFailure = true;   # Always notify on failure

      # ntfy integration for remote notifications
      ntfy = {
        enable = true;
        topic = null;  # Use default topic from hwc.system.services.ntfy
        onSuccess = false;  # No success notifications
        onFailure = true;   # Send ntfy alert on backup failures
      };
    };
  };

  # Enable the declarative VPN service using the official CLI.
  hwc.system.services.vpn.protonvpn.enable = true;

  # Enable session management (greetd autologin, sudo, lingering).
  hwc.system.services.session = {
    enable = true;
    loginManager.enable = true;
    loginManager.autoLoginUser = "eric";
    sudo.enable = true;
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
  # Podman is required by hwc.server.ai.ollama module
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
  hwc.paths.hot = "/home/eric/03-tech/local-storage";

  #============================================================================
  # AI SERVICES CONFIGURATION (Laptop)
  #============================================================================
  # Laptop has superior hardware (32GB RAM, better GPU) for larger models
  hwc.server.ai.ollama = {
    enable = true;
    # Larger models suitable for 32GB RAM + RTX GPU
    models = [
      "qwen2.5-coder:7b"              # 4.3GB - Primary coding assistant
      "llama3.2:3b"                   # 2.0GB - Fast queries, battery mode
      "mistral:7b-instruct"           # 4.1GB - General reasoning
    ];
  };

  # Local AI workflows for laptop
  hwc.server.ai.local-workflows = {
    enable = true;

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
  services.thermald.enable = true;
  services.tlp.enable = true;
  programs.dconf.enable = true;
}
