# nixos-hwc/profiles/base.nix
#
# This profile provides the foundational configuration for all machines in the system.
# It includes essential system settings, timezone, and a simplified, robust secret
# management setup using agenix.

{ lib, pkgs, config, ... }:

{
  imports = [
    # Foundational modules that all machines will need.
    ../modules/system/paths.nix
    ../modules/users/eric.nix
  ];

  config = {
    # 1. Core System Configuration
    boot.loader.systemd-boot.enable = lib.mkDefault true;
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
    time.timeZone = lib.mkDefault "America/New_York";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    # 2. Nix Settings for Optimization and Flakes
    nix = {
      package = pkgs.nixFlakes;
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
      };
      # Garbage Collection to keep the system clean
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
    };

    # 3. Secret Management with agenix (replaces SOPS)
    # Provides simple, robust secret management using machine SSH keys and/or YubiKeys.
    age.secrets = {
      # EXAMPLE: This is how you would define a secret.
      # "my-api-key" = {
      #   file = ../secrets/my-api-key.age; # Path to your encrypted file
      #   owner = config.users.users.some-service-user.name;
      # };
    };
    # Enable the agenix service
    age.identityPaths = [
      # This tells agenix it can use the machine's own SSH host key to decrypt secrets.
      "/etc/ssh/ssh_host_ed25519_key"
    ];
    # To support YubiKey decryption, you would add age-plugin-yubikey to
    # environment.systemPackages and configure it here if needed, but typically
    # agenix handles it automatically if the plugin is present.

    # 4. Enable the 'eric' user by default on all base systems
    hwc.users.eric.enable = lib.mkDefault true;
  };
}