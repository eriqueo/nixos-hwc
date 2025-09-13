# modules/security/secrets/networking.nix
#
# Networking domain secrets - VPN and network authentication credentials
# Data-only module that declares age.secrets entries for network authentication
{ config, lib, ... }:
{
  # Networking domain secrets - VPN and network authentication
  age.secrets = {
    # VPN credentials
    vpn-username = {
      file = ../../../secrets/vpn-username.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    vpn-password = {
      file = ../../../secrets/vpn-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
  };
}