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
    frigate-rtsp-username = {
      file = ../parts/infrastructure/frigate-rtsp-username.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    frigate-rtsp-password = {
      file = ../parts/infrastructure/frigate-rtsp-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    frigate-camera-ips = {
      file = ../parts/infrastructure/frigate-camera-ips.age;
      mode = "0400";
      owner = "root";
      group = "root";
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

    vpn-wireguard-private-key = {
      file = ../parts/infrastructure/vpn-wireguard-private-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
  };
}
