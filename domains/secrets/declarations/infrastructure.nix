# domains/secrets/declarations/infrastructure.nix
#
# Infrastructure domain secrets - Database and infrastructure service credentials
# Data-only module that declares age.secrets entries for infrastructure authentication
{ config, lib, ... }:
{
  # Infrastructure domain secrets - databases and infrastructure services
  age.secrets = {
    # Database credentials
    database-name = {
      file = ../parts/infrastructure/database-name.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    
    database-password = {
      file = ../parts/infrastructure/database-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    
    database-user = {
      file = ../parts/infrastructure/database-user.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    
    # Surveillance system credentials
    surveillance-rtsp-username = {
      file = ../parts/infrastructure/surveillance-rtsp-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    
    surveillance-rtsp-password = {
      file = ../parts/infrastructure/surveillance-rtsp-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    
    # Frigate RTSP credentials
    frigate-rtsp-password = {
      file = ../parts/infrastructure/frigate-rtsp-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # VPN credentials
    vpn-username = {
      file = ../parts/infrastructure/vpn-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    vpn-password = {
      file = ../parts/infrastructure/vpn-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
  };
}