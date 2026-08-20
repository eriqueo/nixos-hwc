# profiles/base/sys.nix — base role, NixOS lane (every machine)
#
# Cross-domain bundle: system + paths + secrets
# Preserves gatherSys pattern (Charter Law 7)
#
# REPLACES: profiles/core.nix
# USED BY: every machine (see the machines table in flake.nix)

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
    ../../domains/system/index.nix

    # Secrets domain (absorbed from profiles/security.nix)
    ../../domains/secrets/index.nix

    # Data domain (required for backup defaults below)
    ../../domains/data/index.nix
  ] ++ (gatherSys ../../domains/home/apps)
    ++ (gatherSys ../../domains/mail);

  #==========================================================================
  # BASE NIXOS SETTINGS
  #==========================================================================
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # cache.nixos.org and its key are NixOS defaults for this option, so
      # declaring them here did not add a cache — it added a SECOND entry for
      # the same one. The two spellings differ only by a trailing slash, which
      # is why nothing deduplicated them and why the effective list read
      # "cache.nixos.org  cache.nixos-cuda.org  cache.nixos.org/" on both hosts.
      # Left to the default; extra substituters (e.g. the CUDA cache in
      # domains/system/gpu) append to it as before.
      trusted-public-keys = [ ];
      auto-optimise-store = true;
      trusted-users = [ "root" "eric" ];
    };
    # Make private first-party flake inputs (github:eriqueo/{todui,khalt,workbench})
    # fetchable at eval time — including the root `sudo nixos-rebuild` evaluator,
    # which reads /root's nix.conf, not eric's. The token is a scoped read+write
    # fine-grained PAT in agenix (github-flake-token, root:secrets 0440). `!include`
    # tolerates the file being absent (pre-activation / a host without the secret).
    # See memory feedback_app_dev_build_pattern.
    extraOptions = ''
      !include ${config.age.secrets."github-flake-token".path}
    '';
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
  # NIX-LD — Run pre-compiled binaries (Claude Code, Electron apps, etc.)
  # Core libs here; GUI machines add X11/Wayland libs in their config.
  #==========================================================================
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    glibc glib nss nspr dbus expat
  ];

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

  # Backup — defaults off, machines enable per-need.
  # Value defaults (retention, sources, excludes, schedule, paths) live as
  # option defaults in domains/data/backup/index.nix; this role only flips
  # behavior.
  hwc.data.backup = {
    enable = lib.mkDefault false;
    notifications.enable = lib.mkDefault true;
    monitoring.enable = true;
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
      # Declarative authorized keys (hwc.system.users.user.ssh.keys).
      # Every machine boots with key auth provisioned, so SSH password auth
      # is never needed — including new-machine bootstrap (the key lands
      # with the first nixos-install/nixos-rebuild; nixos-anywhere covers
      # remote installs). Emergency console login (hwc.secrets.emergency)
      # is unaffected by SSH policy.
      ssh.enable = true;
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
