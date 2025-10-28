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
    ../../workspace/infrastructure/vault-sync-system.nix

    # Profiles that define the machine's capabilities.
    # The system.nix profile is now the main entry point for all system services.
    ../../profiles/system.nix
    ../../profiles/home.nix
    ../../profiles/security.nix
    # ../../profiles/ai.nix # This might be imported by a server profile now.

    # Infrastructure domain for GPU only (not storage)
    ../../domains/infrastructure/hardware/index.nix

    # Virtualization domain for WinApps/VMs (without full infrastructure profile)
    ../../domains/infrastructure/virtualization/index.nix

    # WinApps domain for Windows application integration
    ../../domains/infrastructure/winapps/index.nix
  ];

  #============================================================================
  # SYSTEM IDENTITY & BOOT
  #============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "hwc-laptop";
  system.stateVersion = "24.05";

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

  # Libvirt/QEMU: make OVMF visible and avoid extra groups by using wheel sockets.
  virtualisation.libvirtd = {
    # Use wheel for socket perms so you don't need extra groups.
    extraConfig = ''
      unix_sock_group = "wheel"
      unix_sock_ro_perms = "0770"
      unix_sock_rw_perms = "0770"
    '';

    # Ensure firmware enumeration succeeds on this host.
    qemu = {
      runAsRoot = lib.mkForce true;     # fixes OVMF metadata enumeration edge cases
      ovmf.packages = [ pkgs.OVMFFull.fd ];
    };
  };

  # Avoid container engines on the laptop (keep them in server profiles).
  virtualisation.podman.enable = lib.mkForce false;
  virtualisation.docker.enable = lib.mkForce false;

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
  # (Profile-driven; nothing machine-specific added here.)

  #============================================================================
  # === [profiles/security.nix] Orchestration =================================
  #============================================================================
  # (Profile-driven; nothing machine-specific added here.)

  #============================================================================
  # MISCELLANEOUS MACHINE-SPECIFIC SETTINGS
  #============================================================================

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
