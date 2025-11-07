# domains/secrets/declarations/apps.nix
#
# Application secrets - User and system application credentials
# Data-only module that declares age.secrets entries for applications
{ config, lib, ... }:
{
  # Application secrets for Fabric AI integration
  age.secrets = {
    # Fabric server API environment file (contains all provider API keys)
    fabric-server-env = {
      file = ../parts/apps/fabric-server.env.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Fabric user configuration (for laptop/desktop use)
    fabric-user-env = {
      file = ../parts/apps/fabric-user.env.age;
      mode = "0440";
      owner = "eric";
      group = "users";
    };
  };
}
