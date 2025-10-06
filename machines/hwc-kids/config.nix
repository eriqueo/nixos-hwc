# nixos-hwc/machines/hwc-kids/config.nix
#
# MACHINE: HWC-KIDS
# Declares machine identity and composes profiles; states hardware reality.
# Mirrors the refactored system domain architecture used by other machines.

{ config, lib, pkgs, ... }:

{
  ##############################################################################
  ##  MACHINE: HWC-KIDS
  ##  This file defines the unique properties and profile composition for the
  ##  hwc-kids machine.
  ##############################################################################

  #============================================================================
  # IMPORTS - Compose the machine from profiles and hardware definitions
  #============================================================================
  imports = [
    # Hardware-specific definitions for this machine (e.g., filesystems).
    ./hardware.nix

    # Home Manager activation (machine-specific user environment)
    ./home.nix

    # Vault sync system for Obsidian (same as laptop).
    ../../scripts/vault-sync-system.nix

    # Profiles that define the machine's capabilities.
    # The system.nix profile is the main entry point for system services.
    ../../profiles/system.nix
    # NOTE: profiles/home.nix NOT imported - using ./home.nix instead (Charter compliant)
    ../../profiles/server.nix    # Server workload capabilities (Ollama, containers)
    ../../profiles/ai.nix         # AI service capabilities (Ollama defaults)
    # ../../profiles/security.nix  # Disabled until age keys deployed

    # Infrastructure domain for hardware toggles (GPU/etc).
    ../../domains/infrastructure/hardware/index.nix
  ];

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "hwc-kids";
  system.stateVersion = "24.05";

  #============================================================================
  # HWC PROFILE ORCHESTRATION (Facts & Toggles Only)
  #============================================================================

  # --- System Services Configuration ---
  # Shell + dev tools; keep true if you want normal tooling here.
  hwc.system.services.shell = {
    enable = true;
    development.enable = true;
  };

  # Hardware services (safe defaults).
  hwc.system.services.hardware = {
    enable = true;
    keyboard.enable = true;
    audio.enable = true;
    bluetooth.enable = true;
    monitoring.enable = true;
  };

  # Backups (disabled by default until rclone secrets exist).
  hwc.system.services.backup = {
    enable = true;
    protonDrive.enable = false;  # configure secrets before enabling
  };

  # VPN (off by default on kids machine; toggle to true if needed).
  hwc.system.services.vpn.protonvpn.enable = false;

  # Session management (adjust autologin to your preference).
  hwc.system.services.session = {
    enable = true;
    loginManager.enable = true;
    # Set to a user you want auto-logged-in (or leave unset/commented).
    # loginManager.autoLoginUser = "eric";
    sudo.enable = true;
    linger.enable = true;
    linger.users = [ "eric" ];
  };

  # --- Networking (don’t block boot on network; consistent with laptop) ---
  hwc.networking = {
    enable = true;
    networkManager.enable = true;

    # Laptop-style fast boot: don’t wait for network.
    waitOnline.mode = "off";

    ssh.enable = true;            # flip to false if you don’t want SSH on this box
    firewall.level = "strict";
    tailscale.enable = true;
    tailscale.extraUpFlags = [ "--accept-dns" ];
  };

  # --- Infrastructure & Server Roles ---
  # GPU capability for Intel integrated graphics
  hwc.infrastructure.hardware.gpu = {
    enable = true;
    type = lib.mkForce "intel";  # Override server profile default (nvidia)
    intel = {
      enableCompute = true;      # Enable oneAPI/Level Zero for AI compute
      enableMonitoring = false;  # Optional: enable intel_gpu_top monitoring
    };
    powerManagement.smartToggle = true;
  };

  # AI Compute Node - Ollama service
  hwc.server.ai.ollama = {
    enable = true;
    models = [
      "llama3:8b"       # General purpose LLM (optimized for Intel)
      "codellama:7b"    # Code-focused model (lighter than 13b for Intel GPU)
    ];
    port = 11434;
    dataDir = "/var/lib/ollama";
  };

  # --- Miscellaneous Machine-Specific Settings ---
  hwc.system.users.emergencyEnable = true;

  # Enable SSH for user
  hwc.system.users.user.ssh.enable = true;
  hwc.system.users.user.ssh.fallbackKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICRZRWyarR6++0B2scCEtAptrdRe85i0BeMy+sMBGGSM root@hwc-kids";

  # Disable secrets for initial setup (no age keys deployed yet)
  # Security profile disabled in imports until age keys deployed
  hwc.system.users.user.useSecrets = false;
  hwc.system.users.user.ssh.useSecrets = false;

  # Override server profile assertion - secrets not required during bootstrap
  assertions = lib.mkForce [];


  # Storage paths for hwc-kids (gaming + compute node)
  # Override server profile defaults with mkForce
  hwc.paths = {
    hot = lib.mkForce "/home/eric/03-tech/local-storage";
    media = lib.mkForce "/home/eric/retro-roms";  # ROM library location
    cache = lib.mkForce "/var/cache/hwc";
  };

  # Static hosts (carry over or prune as you like).
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
