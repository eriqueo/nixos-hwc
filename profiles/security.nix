{ config, lib,... }:
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  imports = [
    ../domains/server/networking            # Includes VPN configuration
    ../domains/secrets/index.nix            # New consolidated security domain
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.secrets.hardening = {
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
  hwc.secrets.enable = true;

  # Enable emergency access using the materials facade
  hwc.secrets.emergency = {
    enable = true;
    hashedPasswordFile = config.hwc.secrets.api.emergencyPasswordFile;
  };

  hwc.services.vpn.tailscale = {
    enable = false;
    exitNode = false;
  };
}
