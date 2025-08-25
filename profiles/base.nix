# nixos-hwc/profiles/base.nix
#
# Base System Profile (Orchestration Only)
# Aggregates foundational modules and sets high-level toggles.
# No hardware driver details, no nixpkgs-internal imports, no conditional imports.
#
# DEPENDENCIES (Upstream):
#   - modules/system/paths.nix
#   - modules/system/filesystem.nix
#   - modules/system/networking.nix
#   - modules/security/secrets.nix
#   - modules/home/eric.nix
#   - modules/infrastructure/gpu.nix
#
# USED BY (Downstream):
#   - machines/*/config.nix (selects this profile)
#   - profiles/* (stack additional profiles on top, e.g., ai.nix)
#
# IMPORTS REQUIRED IN:
#   - Any machine using the base system:
#       imports = [ ../../profiles/base.nix ];
#
# USAGE:
#   # Machine declares facts/toggles (no implementation here):
#   #   hwc.gpu.type = "nvidia" | "intel" | "amd" | "none";
#   #   hwc.services.ollama.enable = true;
#
# GUARANTEES:
#   - Static imports only (no recursion risk)
#   - No hardware.* or service implementation logic here
#   - Modules implement; profiles orchestrate; machines declare reality

{ lib, pkgs, ... }:

{
  #============================================================================
  # IMPORTS - Assemble foundational modules (no computed paths)
  #============================================================================
  imports = [
    ../modules/system/paths.nix
    ../modules/system/filesystem.nix
    ../modules/system/networking.nix
    ../modules/security/secrets.nix
    ../modules/home/eric.nix
    ../modules/infrastructure/gpu.nix
  ];

  #============================================================================
  # BASE SETTINGS - Cross-cutting defaults (machine can override)
  #============================================================================
  time.timeZone = lib.mkDefault "America/Denver";

  #============================================================================
  # NIX SETTINGS - Package manager features and GC policy
  #============================================================================
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

  #============================================================================
  # NETWORKING (Orchestration) - Defers implementation to modules/system/networking.nix
  #============================================================================
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

  #============================================================================
  # CONTAINERS (Orchestration)
  #============================================================================
 # virtualisation = {
 #   docker.enable = true;
 #   oci-containers.backend = "docker";
 # };

  #============================================================================
  # BASE TOOLING - Editor, shell tools, etc. (ergonomics)
  #============================================================================
  environment.systemPackages = with pkgs; [
    vim
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
  ];

  #============================================================================
  # USER DOMAIN (Orchestration) - Defers implementation to modules/home/*
  #============================================================================
  hwc.home = {
    user.enable = true;
    groups = {
      basic = true;        # wheel, networkmanager
      media = true;        # video, audio, render
      development = true;  # docker, podman
    };
    ssh.enable = true;
    environment = {
      enableZsh = true;
      enablePaths = true;
    };
  };

  #============================================================================
  # SECURITY (Orchestration) - Defers implementation to modules/security/*
  #============================================================================
  hwc.security = {
    enable = true;
    secrets = {
      user = true;  # User account secrets
      vpn  = true;  # VPN credentials for Tailscale/services
    };
    ageKeyFile = lib.mkDefault "/etc/age/keys.txt";
  };

  #============================================================================
  # FILESYSTEM (Orchestration) - Defers implementation to modules/system/filesystem.nix
  #============================================================================
  hwc.filesystem = {
    enable = true;
    securityDirectories.enable = true;  # Security dirs always needed
  };
}
