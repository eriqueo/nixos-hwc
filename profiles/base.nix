# nixos-hwc/profiles/base.nix
#
# Base System Profile (Orchestration Only)
# Aggregates foundational modules and sets high-level defaults.
# No hardware driver details; no workstation-specific toggles here.

{ lib, pkgs, ... }:

{
  #==========================================================================
  # IMPORTS – Foundational system + infra modules (single root orchestrator)
  #==========================================================================
  imports = [
    ../domains/system/index.nix
    ../domains/infrastructure/index.nix

  ];

  #==========================================================================
  # BASE SETTINGS – Cross-cutting defaults (machines may override)
  #==========================================================================
  time.timeZone = lib.mkDefault "America/Denver";
  users.users.eric = {
    hashedPassword = "$y$j9T$mpCws7jy8SXAeH2rwkaGr.$lc1CQDwsoUxiv6s0PZqlKBmia1ffk4gs5jfyLW1Yg86";
  };
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "eric" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  #==========================================================================
  # NETWORKING (orchestration only; implementation lives in modules/system/*)
  #==========================================================================
  hwc.networking = {
    enable = true;
    ssh = {
      enable = true;
      passwordAuthentication = false;
      x11Forwarding = lib.mkDefault false;
    };
    networkManager.enable = true;
    firewall = {
      enable = true;
      strict = true;
      allowPing = false;
    };
    tailscale.enable = true;
  };

  #==========================================================================
  # CORE SYSTEM DEFAULTS
  #==========================================================================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.blueman.enable = true;
  services.dbus.enable = true;
  security.polkit.enable = true;

  # Base/essential packages (implementation in modules/system/packages/*)
  hwc.system.basePackages.enable = true;

  # User management (implementation in modules/system/users/*)
  hwc.system.users = {
    enable = true;
    user = {
      enable = true;
      name = "eric";
      # For now, rely on module defaults or secret infra; no inline fallback here
      useSecrets = false;
      groups.basic = true;
      groups.media = true;
      groups.hardware = true;
      environment.enableZsh = true;
    };
  };

  # Session management (sudo + linger; DM is set in sys.nix overlay)
  hwc.system.services.session = {
    enable = true;
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
    linger = {
      enable = true;
      users = [ "eric" ];
    };
  };

  hwc.filesystem = {
      enable = true;
    };
  }
