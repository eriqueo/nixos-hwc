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
    ../../scripts/vault-sync-system.nix

    # Profiles that define the machine's capabilities.
    # The system.nix profile is now the main entry point for all system services.
    ../../profiles/system.nix
    ../../profiles/home.nix
    ../../profiles/security.nix
    # ../../profiles/ai.nix # This might be imported by a server profile now.

    # Infrastructure domain for GPU only (not storage/virtualization)
    ../../domains/infrastructure/hardware/index.nix
  ];

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "hwc-laptop";
  system.stateVersion = "24.05";

  #============================================================================
  # HWC PROFILE ORCHESTRATION (Facts & Toggles Only)
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

  # Enable the backup system with Proton Drive.
  hwc.system.services.backup = {
    enable = true;
    protonDrive.enable = false;  # TODO: Configure rclone-proton-config secret
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


  # --- Infrastructure & Server Roles ---

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

  # Enable virtualization for WinApps/VMs
  hwc.infrastructure.virtualization.enable = true;

  # AI services (disabled until server domain refactor complete).
  # hwc.server.ai.ollama = {
  #   enable = true;
  #   models = [ "llama3:8b" "codellama:13b" "phi3:medium" ];
  # };

  # --- Miscellaneous Machine-Specific Settings ---

  # Storage paths (remains unchanged).
  hwc.paths.hot = "/home/eric/03-tech/local-storage";

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
