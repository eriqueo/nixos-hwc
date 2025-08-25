{ config, lib,... }:
{
  imports = [
    ../modules/infrastructure/hardening.nix
    ../modules/infrastructure/secrets.nix
    ../modules/services/vpn.nix
    ../modules/security/emergency-access.nix
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
  # Decrypt this secret at boot (agenix)
  age.secrets."emergency-password".file = ../secrets/emergency-password.age;

  # Enable emergency access using the *hashed* password from the secret
  hwc.security.emergencyAccess = {
    enable = true;
    hashedPasswordFile = config.age.secrets."emergency-password".path;
  };

  hwc.services.vpn.tailscale = {
    enable = false;
    exitNode = false;
  };
}
