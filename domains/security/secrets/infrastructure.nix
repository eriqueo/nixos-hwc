# modules/security/secrets/infrastructure.nix
#
# Infrastructure domain secrets - Database and infrastructure service credentials
# Data-only module that declares age.secrets entries for infrastructure authentication
{ config, lib, ... }:
{
  # Infrastructure domain secrets - databases and infrastructure services
  age.secrets = {
    # Database credentials
    database-name = {
      file = ../../../secrets/database-name.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    database-password = {
      file = ../../../secrets/database-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    database-user = {
      file = ../../../secrets/database-user.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # Surveillance system credentials
    surveillance-rtsp-username = {
      file = ../../../secrets/surveillance-rtsp-username.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    surveillance-rtsp-password = {
      file = ../../../secrets/surveillance-rtsp-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # Frigate RTSP credentials
    frigate-rtsp-password = {
      file = ../../../secrets/frigate-rtsp-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
  };
}