# domains/secrets/declarations/system.nix
#
# System domain secrets - Core system authentication and emergency access
# Data-only module that declares age.secrets entries for system-level authentication
{ config, lib, ... }:
{
  # System domain secrets - core authentication
  age.secrets = {
    # User authentication secrets
    user-initial-password = {
      file = ../parts/system/user-initial-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Emergency access for system recovery
    emergency-password = {
      file = ../parts/system/emergency-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # User SSH public key for authentication
    user-ssh-public-key = {
      file = ../parts/system/user-ssh-public-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Rclone configuration for Proton Drive backups
    rclone-proton-config = {
      file = ../parts/system/rclone-proton-config.age;
      mode = "0600"; # Rclone configs need to be readable only by root
      owner = "root";
      group = "root";
    };
  };
}