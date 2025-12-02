# NEW, CLEAN profiles/system.nix

{ lib, pkgs, ... }:
let
  # Helper to gather all sys.nix files from home apps (Charter v7 compliance)
  gatherSys = dir:
    let
      content = builtins.readDir dir;
      names = builtins.attrNames content;
      validDirs = builtins.filter (name:
        content.${name} == "directory" &&
        builtins.pathExists (dir + "/${name}/sys.nix")
      ) names;
    in
      builtins.map (name: dir + "/${name}/sys.nix") validDirs;
in
{
  #==========================================================================
  # IMPORTS
  #==========================================================================
  # System domain modules + co-located sys.nix files from home apps
  imports = [ ../domains/system/index.nix ] ++ (gatherSys ../domains/home/apps);

  #==========================================================================
  # BASE NIXOS SETTINGS
  #==========================================================================
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Pin binary caches for consistent, fast rebuilds
      substituters = [
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
      # Increase download buffer to prevent warnings during large downloads
      download-buffer-size = 256 * 1024 * 1024; # 256 MiB
      # Optimize Nix store automatically
      auto-optimise-store = true;
    };
    # Automatic garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    # Automatically detect and remove duplicate files
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };
  time.timeZone = "America/Denver";

  # Enable SSD TRIM for all machines (improves SSD lifespan and performance)
  services.fstrim = {
    enable = true;
    interval = "weekly"; # Run TRIM weekly
  };

  # Limit boot generations to prevent /boot partition from filling up
  boot.loader.systemd-boot.configurationLimit = 10;

  #==========================================================================
  # SYSTEM PACKAGES
  #==========================================================================
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "pb-cli" ''
      exec sudo -u protonbridge \
        XDG_CONFIG_HOME=/var/lib/proton-bridge/config \
        XDG_DATA_HOME=/var/lib/proton-bridge/data \
        XDG_CACHE_HOME=/var/lib/proton-bridge/cache \
        ${pkgs.protonmail-bridge}/bin/protonmail-bridge --cli
    '')
  ];

  #==========================================================================
  # HWC SYSTEM SERVICES CONFIGURATION
  #==========================================================================
  # This is where the magic happens. Each section corresponds to one
  # of your new, self-contained modules.

  # --- Shell Module ---
  # Enables the core command-line environment (git, neovim, tmux, etc.)
  # and installs all its own packages.
  hwc.system.services.shell.enable = true;

  # --- Hardware Module ---
  # Enables services for keyboard, mouse, and audio (PipeWire),
  # and installs its own packages (lm_sensors, etc.).
  hwc.system.services.hardware.enable = true;

  # --- Session Module ---
  # Manages the login screen, sudo, and user lingering.
  hwc.system.services.session = {
    enable = true;
    loginManager.autoLoginUser = "eric";
    sudo.enable = true;
    sudo.wheelNeedsPassword = false;
    linger.users = [ "eric" ];
  };

  # --- Backup Module ---
  # Comprehensive backup system supporting local (external drives, NAS, DAS)
  # and cloud (Proton Drive) backups with automatic scheduling and rotation.
  hwc.system.services.backup = {
    enable = true;

    # Local backup to external drives/NAS/DAS
    local = {
      enable = lib.mkDefault false;  # Enable per-machine
      mountPoint = lib.mkDefault "/mnt/backup";
      useRsync = true;  # Incremental backups with hard-link snapshots
      keepDaily = lib.mkDefault 7;
      keepWeekly = lib.mkDefault 4;
      keepMonthly = lib.mkDefault 6;
      minSpaceGB = lib.mkDefault 10;
      sources = [ "/home" "/etc/nixos" ];
      # Exclude patterns to reduce backup size
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
        ".mozilla/firefox/*/storage/default"
        "Downloads/*.iso"
        "Downloads/*.img"
      ];
    };

    # Cloud backup (Proton Drive)
    cloud = {
      enable = lib.mkDefault false;  # Enable per-machine
      provider = "proton-drive";
      remotePath = "Backups";
      syncMode = "sync";  # Mirror mode
      bandwidthLimit = null;  # No limit by default
    };

    protonDrive = {
      enable = lib.mkDefault false;
      secretName = "rclone-proton-config";
    };

    # Automatic scheduling
    schedule = {
      enable = lib.mkDefault false;  # Enable per-machine
      frequency = "daily";
      timeOfDay = "02:00";  # 2 AM
      randomDelay = "1h";
      onlyOnAC = true;  # Only run on AC power (for laptops)
    };

    # Notifications
    notifications = {
      enable = lib.mkDefault true;
      onSuccess = false;  # Don't notify on success (reduce noise)
      onFailure = true;   # Always notify on failure
    };

    # Monitoring and health checks
    monitoring = {
      enable = true;
      logPath = "/var/log/backup";
      healthCheckInterval = "weekly";
    };
  };

  # --- Networking Module ---
  # This is the best example of the new simplicity.
  # We now define the machine's networking role with a few high-level toggles.
  hwc.networking = {
    enable = true;
    ssh.enable = true;
    tailscale.enable = lib.mkDefault true;

    # One line to define a comprehensive firewall policy.
    # The implementation handles opening the right ports for SSH and Tailscale.
    firewall.level = "strict";

    # Enable Samba for file sharing.
    samba.enable = true;
    samba.shares = {
      # Define machine-specific shares right here.
      "public" = {
        path = "/data/public";
        browseable = true;
        readOnly = true;
        guestAccess = true;
      };
    };
  };

  # --- Proton Mail Bridge Module ---
  # Isolated system service with dedicated user and proper state management
  hwc.system.services.protonmail-bridge.enable = false;

  # --- User Module ---
  # This remains the same, cleanly handling user creation.
  hwc.system.users = {
    enable = true;
    emergencyEnable = lib.mkDefault true;  # Emergency root access for recovery
    user = {
      enable = true;
      name = "eric";
      groups = {
        basic = true;           # wheel, networkmanager
        media = true;           # video, audio, render
        development = true;     # docker, podman
        virtualization = true;  # libvirtd, kvm
        hardware = true;        # input, uucp
      };
    };
  };
}
