{ ... }:
{
  imports = [
    ../modules/infrastructure/hardening.nix
    ../modules/infrastructure/secrets.nix
    ../modules/services/vpn.nix
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

  hwc.secrets = {
    enable = true;
    provider = "age";
  };

  hwc.services.vpn.tailscale = {
    enable = false;
    exitNode = false;
  };
}
