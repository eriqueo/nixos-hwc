# modules/security/secrets/system.nix
#
# System domain secrets - Core system authentication and emergency access
# Data-only module that declares age.secrets entries for system-level authentication
{ config, lib, ... }:
{
  # System domain secrets - core authentication
  age.secrets = {
    # User authentication secrets
    user-initial-password = {
      file = ../../../secrets/user-initial-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # Emergency access for system recovery
    emergency-password = {
      file = ../../../secrets/emergency-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # User SSH public key for authentication
    user-ssh-public-key = {
      file = ../../../secrets/user-ssh-public-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
  };
}