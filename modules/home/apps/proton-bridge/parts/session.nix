# ProtonMail Bridge • Session part
# Session-scoped things only: packages, user services, env.
{ lib, pkgs, config, ... }:

{
  # ProtonMail Bridge package
  packages = [ pkgs.protonmail-bridge ];

  # User service for ProtonMail Bridge
  services = {
    "protonmail-bridge" = {
      Unit = {
        Description = "ProtonMail Bridge (headless)";
        After = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        # First-time auth: run `protonmail-bridge --cli` manually to login.
        ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive --log-level warn";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = { WantedBy = [ "default.target" ]; };
    };
  };

  # Environment variables for Bridge
  env = {
    PROTONMAIL_BRIDGE_IMAP_PORT = "1143";
    PROTONMAIL_BRIDGE_SMTP_PORT = "1025";
  };
}