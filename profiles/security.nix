{ ... }:
{
  imports = [
    ../modules/infrastructure/security.nix
    ../modules/infrastructure/secrets.nix
    ../modules/services/vpn.nix
  ];

  hwc.security = {
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

  hwc.secrets = {
    enable = true;
    provider = "age";
  };

  hwc.services.vpn.tailscale = {
    enable = false;
    exitNode = false;
  };
}
