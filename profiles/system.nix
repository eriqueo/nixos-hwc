# NEW, CLEAN profiles/system.nix

{ lib, ... }:
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
    settings.experimental-features = [ "nix-command" "flakes" ];
    gc.automatic = true;
  };
  time.timeZone = "America/Denver";

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
    loginManager.autoLogin = true; # Example of a high-level tweak
    sudo.wheelNeedsPassword = false;
    linger.users = [ "eric" ];
  };

  # --- Backup Module ---
  # Enables the entire backup system, including the service, timer,
  # scripts, and all required packages (rclone, etc.).
  hwc.system.services.backup = {
    enable = true;
    protonDrive.enable = true;
    protonDrive.useSecret = true; # Let the module handle finding the secret
    monitoring.enable = true;
  };

  # --- Networking Module ---
  # This is the best example of the new simplicity.
  # We now define the machine's networking role with a few high-level toggles.
  hwc.networking = {
    enable = true;
    ssh.enable = true;
    tailscale.enable = true;

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

  # --- User Module ---
  # This remains the same, cleanly handling user creation.
  hwc.system.users = {
    enable = true;
    user.name = "eric";
  };
}
