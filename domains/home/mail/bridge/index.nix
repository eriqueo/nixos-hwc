{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.mail.bridge;
  accs = config.hwc.home.mail.accounts or {};
  vals = lib.attrValues accs;
  haveProton = lib.any (a: a.type == "proton-bridge") vals;

  # Auto-enable if any account uses Proton Bridge; explicit cfg.enable overrides if set
  enabled = (cfg.enable or (lib.mkDefault haveProton));

  args = lib.concatStringsSep " " (["--noninteractive" "--log-level" cfg.logLevel] ++ cfg.extraArgs);
  envLines = lib.mapAttrsToList (k: v: ''"${k}=${v}"'') cfg.environment;
in
{
  config = lib.mkIf enabled {
    home.packages = [ pkgs.protonmail-bridge ];

    # First-time helper
    home.file.".local/bin/proton-bridge-setup".text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      echo "ProtonMail Bridge Setup"
      echo "1) Run: protonmail-bridge --cli"
      echo "2) Login; note the app-specific IMAP/SMTP password"
      echo "IMAP: 127.0.0.1:1143  SMTP: 127.0.0.1:1025  User: your@proton.me"
    '';
    home.file.".local/bin/proton-bridge-setup".executable = true;

    # Ensure config dir exists (Bridge populates its own files)
    home.file.".config/protonmail/bridge/.keep".text = "";

    systemd.user.services.protonmail-bridge = {
      Unit = {
        Description = "ProtonMail Bridge (headless)";
        After = [ "default.target" "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge ${args}";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = [
          # Needed if you use pass for Bridge creds
          "PATH=/run/current-system/sw/bin:${pkgs.pass}/bin"
          "PASSWORD_STORE_DIR=%h/.password-store"
          "GNUPGHOME=%h/.gnupg"
          # Bridge defaults are 1143/1025; override here if you want different ports:
          # "PROTONMAIL_BRIDGE_IMAP_PORT=1143"
          # "PROTONMAIL_BRIDGE_SMTP_PORT=1025"
        ] ++ envLines;
      };
      Install = { WantedBy = [ "default.target" ]; };
    };
  };
}
