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
    # System domain modules (Charter v7 reorganized)
    ../modules/system/index.nix
    
    # Infrastructure
    ../modules/infrastructure/index.nix
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
  # BLUETOOTH (Hardware Infrastructure)
  #============================================================================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  
  services.blueman.enable = true;
  services.dbus.enable = true;
  security.polkit.enable = true;

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
  # Moved to modules/system/base-packages.nix
  hwc.system.basePackages.enable = true;

  #============================================================================
  # SYSTEM DOMAIN - Core system configuration (Charter v4)
  #============================================================================
  # User management with agenix integration
  hwc.system.users = {
    enable = true;
    user = {
      enable = true;
      name = "eric";
      useSecrets = false; # Use fallback password for now
      groups.basic = true;
      groups.media = true;
      groups.hardware = true;
      environment.enableZsh = true;
    };
  };

  # Session management (sudo + login)
  hwc.system.services.session = {
    enable = true;
    sudo = {
      enable = true;
      wheelNeedsPassword = false; # Restore working sudo behavior
    };
  };

  # Security domain provides all secrets (enabled via security profile)
  # No direct configuration needed here - security profile handles it

  #============================================================================
  # USER DOMAIN (Orchestration) - Defers implementation to modules/home/*
  #============================================================================
  # Legacy hwc.home.* configuration removed
  # User management now handled by hwc.system.users in system domain

  #============================================================================
  # SECURITY - Now handled by system domain modules
  #============================================================================
  # Security configuration moved to:
  # - hwc.system.users (user authentication)
  # - hwc.system.services.session.sudo (privilege escalation)
  # - hwc.security.* (via security profile - agenix integration)

  #============================================================================
  # FILESYSTEM (Orchestration) - Defers implementation to modules/system/filesystem.nix
  #============================================================================
  hwc.filesystem = {
    enable = true;
    securityDirectories.enable = true;  # Security dirs always needed
  };
}
