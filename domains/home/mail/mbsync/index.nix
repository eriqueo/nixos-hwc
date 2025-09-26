{ config, lib, pkgs, ... }:
let
  cfg  = config.hwc.home.mail;
  accs = cfg.accounts or {};
  vals = lib.attrValues accs;

  on = (cfg.enable or true) && (cfg.mbsync.enable or true) && (vals != []);

  haveProton = lib.any (a: a.type == "proton-bridge") vals;

  common = import ../parts/common.nix { inherit lib; };
  maildirRoot = "${config.home.homeDirectory}/Maildir";

  # Escape [ and ] for mbsync patterns
  escapeSquareBrackets = s: builtins.replaceStrings ["["  "]"] ["\\[" "\\]"] s;

  # Expand Gmail namespace aliases: [Gmail] <-> [Google Mail]
  expandGoogleAliases = s:
    if lib.hasInfix "[Gmail]/" s then
      [ s (lib.replaceStrings ["[Gmail]"] ["[Google Mail]"] s) ]
    else if lib.hasInfix "[Google Mail]/" s then
      [ s (lib.replaceStrings ["[Google Mail]"] ["[Gmail]"] s) ]
    else
      [ s ];

  # Quote for mbsync conf (double quotes; escape any " or \ just in case)
    confQuote = s:
      let esc = builtins.replaceStrings [ "\"" ] [ "\\\"" ] s;
      in "\"" + esc + "\"";

  # Build the final Patterns list per account
  patternsFor = a:
    let
      raw = a.sync.patterns or [ "INBOX" ];
    in if common.isGmail a then
      let
        expanded  = lib.concatLists (map expandGoogleAliases raw);
        escaped   = map escapeSquareBrackets expanded;
      in lib.unique escaped
    else
      raw;

  mbsyncBlock = a:
    let
      cmd   = common.passCmd a;
      imapH = if a.imapHost != null then a.imapHost else common.imapHost a;
      imapP = if a.imapPort != null then a.imapPort else common.imapPort a;
      tlsT  = if a.imapTls  != null then a.imapTls  else common.tlsType a;
      createPolicy = if common.isGmail a then "Create Near" else "Create Both";

      patStr = lib.concatStringsSep " " (map confQuote (patternsFor a));
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
      Patterns ${patStr}
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
        After  = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
        Wants  = [ "network-online.target" ] ++ lib.optionals haveProton [ "protonmail-bridge.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.isync}/bin/mbsync -a";
        ExecStartPost = "${pkgs.notmuch}/bin/notmuch new";
        
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
