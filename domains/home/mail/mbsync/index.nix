{ config, lib, pkgs, ... }:
let
  cfg  = config.hwc.home.mail;
  accs = cfg.accounts or {};
  vals = lib.attrValues accs;

  # Enable when the domain is on AND the per-program toggle is on AND there is at least one account
  on = (cfg.enable or true) && (cfg.mbsync.enable or true) && (vals != []);

  haveProton = lib.any (a: a.type == "proton-bridge") vals;

  common = import ../parts/common.nix { inherit lib; };
  maildirRoot = "${config.home.homeDirectory}/Maildir";

  mbsyncBlock = a:
    let
      cmd  = common.passCmd a;
      imapH = if a.imapHost != null then a.imapHost else common.imapHost a;
      imapP = if a.imapPort != null then a.imapPort else common.imapPort a;
      tlsT  = if a.imapTls  != null then a.imapTls  else common.tlsType a;
      createPolicy = if common.isGmail a then "Create Near" else "Create Both";
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
  config = lib.mkIf on {
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
