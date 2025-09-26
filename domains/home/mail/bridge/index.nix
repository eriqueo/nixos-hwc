{ config, lib, pkgs, ... }:
let
  # Domain + shared accounts
  mail = config.hwc.home.mail;
  accs = mail.accounts or {};
  vals = lib.attrValues accs;

  # Is there any Proton Bridge-backed account?
  haveProton = lib.any (a: a.type == "proton-bridge") vals;

  # Submodule config (log level, extra env/args, etc.)
  br  = mail.bridge or {};

  # Turn on only when: domain enabled AND bridge enabled AND there is a proton account
  on = (mail.enable or true) && (br.enable or true) && haveProton;

  # CLI args + env lines
  args = lib.concatStringsSep " " (["--noninteractive" "--log-level" (br.logLevel or "warn")] ++ (br.extraArgs or []));
  envLines = lib.mapAttrsToList (k: v: ''"${k}=${v}"'') (br.environment or {});
in
{
  config = lib.mkIf on {
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
          # Allow pass/gnupg without globally installing into PATH
          "PATH=/run/current-system/sw/bin:${pkgs.pass}/bin"
          "PASSWORD_STORE_DIR=%h/.password-store"
          "GNUPGHOME=%h/.gnupg"
          # Optional port overrides:
          # "PROTONMAIL_BRIDGE_IMAP_PORT=1143"
          # "PROTONMAIL_BRIDGE_SMTP_PORT=1025"
        ] ++ envLines;
      };
      Install = { WantedBy = [ "default.target" ]; };
    };
  };
}
