{ config, lib, pkgs, ... }:
let
  enabled = config.hwc.home.mail.enable or false;
  accs = config.hwc.home.mail.accounts or {};
  vals = lib.attrValues accs;

  haveProton = lib.any (a: a.type == "proton-bridge") vals;

  common = import ../parts/common.nix { inherit lib; };
  maildirRoot = "${config.home.homeDirectory}/Maildir";

  mbsyncBlock = a:
    let
      cmd = common.passCmd a;
      createPolicy = if common.isGmail a then "Create Near" else "Create Both";
      imapH = if a.imapHost != null then a.imapHost else common.imapHost a;
      imapP = if a.imapPort != null then a.imapPort else common.imapPort a;
      tlsT  = if a.imapTls  != null then a.imapTls  else common.tlsType a;
    in ''
      IMAPAccount ${a.name}
      Host ${imapH}
      Port ${toString imapP}
      User ${common.loginOf a}
      PassCmd "${cmd}"
      TLSType ${tlsT}

      IMAPStore ${a.name}-remote
      Account ${a.name}

      MaildirStore ${a.name}-local
      Path ${maildirRoot}/${a.maildirName}/
      Inbox ${maildirRoot}/${a.maildirName}/INBOX
      SubFolders Verbatim

      Channel ${a.name}-all
      Far :${a.name}-remote:
      Near :${a.name}-local:
      Patterns ${lib.concatStringsSep " " (map lib.escapeShellArg a.sync.patterns)}
      ${createPolicy}
      Expunge Both
      SyncState *
      ${a.extraMbsync}
    '';
in
{
  config = lib.mkIf enabled {
    home.packages = [ pkgs.isync pkgs.pass pkgs.gnupg ];

    home.file.".mbsyncrc".text =
      lib.concatStringsSep "\n\n" (map mbsyncBlock vals);

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
  };
}
