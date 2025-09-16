{ config, lib,... }:
{
  imports = [
    ../modules/server/networking/vpn.nix
    ../modules/security/index.nix          # New consolidated security domain
  ];

  hwc.security.hardening = {
    enable = true;

    firewall = {
      strictMode = true;
      allowedServices = [ "ssh" "https" ];
    };

    fail2ban = {
      enable = true;
      maxRetries = 3;
      banTime = "30m";
    };

    ssh = {
      passwordAuthentication = false;
      permitRootLogin = false;
    };

    audit.enable = true;
  };

  # Security domain provides all secrets via materials facade
  hwc.security.enable = true;

  # Enable emergency access using the materials facade
  hwc.security.emergencyAccess = {
    enable = true;
    hashedPasswordFile = config.hwc.security.materials.emergencyPasswordFile;
  };

  hwc.services.vpn.tailscale = {
    enable = false;
    exitNode = false;
  };
}
