# profiles/core.nix — Universal base profile for every machine
#
# Cross-domain bundle: system + paths + secrets
# Preserves gatherSys pattern (Charter Law 7)
#
# REPLACES: system.nix, base.nix, security.nix
# USED BY: Every machine

{ config, lib, pkgs, ... }:
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
  # IMPORTS — Cross-domain aggregation
  #==========================================================================
  imports = [
    # System domain (includes paths via domains/system/core/index.nix)
    ../domains/system/index.nix

    # Secrets domain (absorbed from profiles/security.nix)
    ../domains/secrets/index.nix

    # Data domain (required for backup defaults below)
    ../domains/data/index.nix
  ] ++ (gatherSys ../domains/home/apps)
    ++ (gatherSys ../domains/mail);

  #==========================================================================
  # BASE NIXOS SETTINGS
  #==========================================================================
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      substituters = [
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };
  time.timeZone = "America/Denver";

  # SSD TRIM for all machines
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  # Limit boot generations to prevent /boot partition from filling up
  boot.loader.systemd-boot.configurationLimit = 10;

  #==========================================================================
  # SYSTEM PACKAGES — Universal CLI tools
  #==========================================================================
  environment.systemPackages = [
    pkgs.parted
    pkgs.gptfdisk
  ];

  #==========================================================================
  # HWC SYSTEM SERVICES — Universal defaults
  #==========================================================================

  # Shell — core CLI environment (git, neovim, tmux, etc.)
  hwc.system.core.shell.enable = true;

  # Hardware monitoring tools (smartctl, sensors, etc.) — all machines
  hwc.system.hardware.enable = true;
  hwc.system.hardware.monitoring.enable = true;

  # Backup — defaults off, machines enable per-need
  hwc.data.backup = {
    enable = lib.mkDefault false;

    local = {
      enable = lib.mkDefault false;
      mountPoint = lib.mkDefault (config.hwc.paths.backup or "/mnt/backup");
      useRsync = true;
      keepDaily = lib.mkDefault 5;
      keepWeekly = lib.mkDefault 2;
      keepMonthly = lib.mkDefault 3;
      minSpaceGB = lib.mkDefault 10;
      sources = [ "/home" "/etc/nixos" ];
      excludePatterns = [
        ".cache" "*.tmp" "*.temp" ".local/share/Trash"
        "node_modules" "__pycache__" ".npm"
        ".cargo/registry" ".cargo/git"
        ".mozilla/firefox/*/storage/default"
        "Downloads/*.iso" "Downloads/*.img"
      ];
    };

    cloud = {
      enable = lib.mkDefault false;
      provider = "proton-drive";
      remotePath = "Backups";
      syncMode = "sync";
      bandwidthLimit = null;
    };

    protonDrive = {
      enable = lib.mkDefault false;
      secretName = "rclone-proton-config";
    };

    schedule = {
      enable = lib.mkDefault false;
      frequency = "daily";
      timeOfDay = "02:00";
      randomDelay = "1h";
      onlyOnAC = true;
    };

    notifications = {
      enable = lib.mkDefault true;
      onSuccess = false;
      onFailure = true;
    };

    monitoring = {
      enable = true;
      logPath = "/var/log/backup";
      healthCheckInterval = "weekly";
    };
  };

  # Networking — universal base
  hwc.system.networking = {
    enable = true;
    ssh.enable = true;
    tailscale.enable = lib.mkDefault true;
    firewall.level = "strict";
  };

  # Users — universal
  hwc.system.users = {
    enable = true;
    emergencyEnable = lib.mkDefault true;
    user = {
      enable = true;
      name = "eric";
      groups = {
        basic = true;
        media = true;
        development = true;
        virtualization = true;
        hardware = true;
      };
    };
  };

  #==========================================================================
  # SECURITY — Absorbed from profiles/security.nix
  #==========================================================================
  hwc.secrets.hardening = {
    enable = true;

    firewall = {
      strictMode = true;
      allowedServices = [ "ssh" "https" ];
    };

    fail2ban = {
      enable = true;
      maxRetries = 3;
      banTime = "30m";
    };

    ssh = {
      passwordAuthentication = false;
      permitRootLogin = false;
    };

    audit.enable = false;
  };

  hwc.secrets.enable = true;

  hwc.secrets.emergency = {
    enable = true;
    hashedPasswordFile = config.hwc.secrets.api."emergency-password" or null;
  };
}
