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

<<<<<<< HEAD
  #==========================================================================
  # BASE SETTINGS – Cross-cutting defaults (machines may override)
  #==========================================================================


  #==========================================================================
  # NETWORKING (orchestration only; implementation lives in modules/system/*)
  #==========================================================================
  

  #==========================================================================
  # CORE SYSTEM DEFAULTS
  #==========================================================================

=======
  time.timeZone = "America/Denver";
  security.polkit.enable = true;
  services.dbus.enable = true;
  
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

  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowPing = true;
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  virtualisation = {
    docker.enable = true;
    oci-containers.backend = "docker";
  };

  environment.systemPackages = with pkgs; [
    vim
    micro
    git
    wget
    curl
    htop
    tmux
    ncdu
    tree
    ripgrep
    fd
    bat
    eza
    zoxide
    fzf
    file
    p7zip
    bchunk
    fuseiso
    dosbox-staging
    wineWowPackages.stable
    winetricks
  ];

  programs.zsh.enable = true;
}
>>>>>>> 5dca300 (hwc-kids: finalize ESP mount, systemd-boot, NM+polkit, zsh tidy)
