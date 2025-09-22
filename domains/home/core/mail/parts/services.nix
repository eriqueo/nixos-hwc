# modules/home/core/mail/parts/services.nix
{ config, lib, pkgs, ... }:

let
  vals = lib.attrValues (config.hwc.home.core.mail.accounts or {});
  haveProton = lib.any (a: a.type == "proton-bridge") vals;
in
{
  # Proton Bridge user service (if any proton account exists)
  systemd.user.services.protonmail-bridge = lib.mkIf haveProton {
    Unit = {
      Description = "ProtonMail Bridge (headless)";
      After = [ "default.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive --log-level warn";
      Restart = "on-failure";
      Environment = [
        "PATH=/run/current-system/sw/bin:${pkgs.pass}/bin"
        "PASSWORD_STORE_DIR=%h/.password-store"
        "GNUPGHOME=%h/.gnupg"
      ];
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # Periodic mbsync timer + unit
  systemd.user.services.mbsync = {
    Unit = {
      Description = "mbsync all";
      After = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
      Wants = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.isync}/bin/mbsync -a";
      Environment = [
        "PATH=/run/current-system/sw/bin"
        "PASSWORD_STORE_DIR=%h/.password-store"
        "GNUPGHOME=%h/.gnupg"
      ];
    };
  };

  systemd.user.timers.mbsync = {
    Unit.Description = "Periodic mbsync";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      AccuracySec = "30s";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
