# NEW, CLEAN profiles/system.nix

{ lib, pkgs, ... }:
{
  #==========================================================================
  # IMPORTS
  #==========================================================================
  # The import is now simpler. The main system index.nix handles
  # aggregating all the service modules automatically.
  imports = [ ../domains/system/index.nix ];

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
    };
    gc.automatic = true;
  };
  time.timeZone = "America/Denver";

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
  # Enables the entire backup system, including the service, timer,
  # scripts, and all required packages (rclone, etc.).
  hwc.system.services.backup = {
    enable = true;
    protonDrive.enable = lib.mkDefault false;
    monitoring.enable = true;
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
