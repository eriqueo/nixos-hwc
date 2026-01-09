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

  # Hibernation disabled (using zram swap for better performance)
  # boot.resumeDevice = "/dev/disk/by-uuid/0ebc1df3-65ec-4125-9e73-2f88f7137dc7";
  # boot.kernelParams = [ "resume_offset=0" ];

  # Power management for laptop
  powerManagement.enable = true;
  services.logind = {
    # All settings are now consolidated under the 'settings' attribute set.
    settings = {
      Login = {
        # Ignore lid close to prevent suspend during remote access
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        # Suspend on power button (hibernation disabled with zram)
        HandlePowerKey = "suspend";
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
          # Performance mode: allow CPU governor changes
          { command = "/run/current-system/sw/bin/tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"; options = [ "NOPASSWD" ]; }
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
  # Laptop has superior hardware (32GB RAM, RTX 2000 Ada GPU) - optimized for performance
  hwc.ai.ollama = {
    enable = false;  # Disabled by default, toggle with waybar button
    # GPU-accelerated models leveraging NVIDIA RTX 2000 (8GB VRAM)
    models = [
      "qwen2.5-coder:14b-q5_K_M"      # 9.7GB - Primary coding, GPU accelerated
      "deepseek-coder:6.7b-instruct"  # 3.9GB - Excellent code generation
      "llama3.2:3b"                   # 2.0GB - Fast queries, battery mode
      "phi-3:14b"                     # 7.9GB - Microsoft's efficient model
    ];

    # Balanced resource limits (50% of system capacity)
    resourceLimits = {
      enable = true;
      maxCpuPercent = 800;          # 8 cores (50% of 16 cores)
      maxMemoryMB = 16384;           # 16GB (50% of 32GB RAM)
      maxRequestSeconds = 300;       # 5 minutes for larger models
    };

    # Auto-shutdown after idle (perfect for grebuild sprints)
    idleShutdown = {
      enable = true;
      idleMinutes = 15;              # Shutdown after 15min of inactivity
      checkInterval = "2min";         # Check every 2 minutes
    };

    # Thermal protection tuned for modern CPU (can handle higher temps)
    thermalProtection = {
      enable = true;
      warningTemp = 85;              # Intel Core Ultra 9 safe operating temp
      criticalTemp = 95;             # Emergency stop (before CPU throttles at 100°C)
      checkInterval = "30s";          # Check every 30 seconds
      cooldownMinutes = 5;           # Faster recovery after thermal event
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
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      # Battery charge thresholds (extends battery life)
      START_CHARGE_THRESH_BAT0 = 75;  # Start charging at 75%
      STOP_CHARGE_THRESH_BAT0 = 90;   # Stop charging at 90%

      # Add CPU energy/performance preferences
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance-power";

      # Boost control (disable turbo on battery for cooler operation)
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;

      # Power saving on battery
      WIFI_PWR_ON_BAT = "on";
      WOL_DISABLE = "Y";

      # USB autosuspend
      USB_AUTOSUSPEND = 1;

      # SATA power management
      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
    };
  };

  #============================================================================
  # PERFORMANCE TUNING (32GB RAM, dual NVMe system)
  #============================================================================
  services.thermald.enable = true;
  boot.kernel.sysctl = {
    # Memory management for high-RAM system
    "vm.swappiness" = 100;              # Rarely use swap (have 32GB RAM + zram)
    "vm.vfs_cache_pressure" = 50;      # Keep file cache longer
    "vm.dirty_ratio" = 6;             # Allow more dirty memory before blocking
    "vm.dirty_background_ratio" = 3;  # Background writeback threshold

    # Network performance tuning
    "net.core.rmem_max" = 134217728;   # 128MB receive buffer
    "net.core.wmem_max" = 134217728;   # 128MB send buffer
    "net.ipv4.tcp_rmem" = "4096 87380 67108864";  # TCP receive buffer
    "net.ipv4.tcp_wmem" = "4096 65536 67108864";  # TCP send buffer
    "net.ipv4.tcp_congestion_control" = "bbr";    # Modern TCP congestion control

    # File descriptor limits for development workloads
    "fs.file-max" = 2097152;
    "fs.inotify.max_user_watches" = 524288;
  };

  # Performance mode wrappers for CPU-intensive tasks
  # TODO: Consider moving to domains/system/services/performance/ module
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "perf-mode" ''
      #!/usr/bin/env bash
      # Temporarily switch to maximum CPU performance
      echo "⚡ Switching to Performance Mode..."
      echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
      ${pkgs.libnotify}/bin/notify-send "Performance Mode" "CPU governors set to maximum performance" -i cpu -u normal
      echo "CPU governors set to 'performance'"
      echo "Use 'balanced-mode' to restore power-efficient operation"
    '')

    (writeShellScriptBin "balanced-mode" ''
      #!/usr/bin/env bash
      # Restore balanced power-efficient mode
      echo "🔋 Restoring Balanced Mode..."
      echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
      ${pkgs.libnotify}/bin/notify-send "Balanced Mode" "CPU governors restored to power-efficient mode" -i cpu -u normal
      echo "CPU governors set to 'powersave' (dynamic scaling)"
    '')
  ];

  programs.dconf.enable = true;
}
