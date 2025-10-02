{ lib, pkgs, config }:
let
  cfg        = config.hwc.home.mail;
  accs       = cfg.accounts or {};
  common     = import ../../parts/common.nix { inherit lib; };
  maildirRoot = "${config.home.homeDirectory}/Maildir";

  # ---- Account ordering (left-to-right everywhere that iterates 'vals')
  desiredOrder = [ "iheartwoodcraft" "proton" "gmail-personal" "gmail-business" ];
  allNames     = builtins.attrNames accs;
  orderedNames =
    (lib.filter (n: lib.elem n allNames) desiredOrder)
    ++ (lib.filter (n: ! lib.elem n desiredOrder) allNames);
  vals = map (n: accs.${n}) orderedNames;

  haveProton = lib.any (a: a.type == "proton-bridge") vals;

  # ---- Helpers
  escapeSquareBrackets = s: builtins.replaceStrings ["["  "]"] ["\\[" "\\]"] s;

  expandGoogleAliases = s:
    if lib.hasInfix "[Gmail]/" s then
      [ s (lib.replaceStrings ["[Gmail]"] ["[Google Mail]"] s) ]
    else if lib.hasInfix "[Google Mail]/" s then
      [ s (lib.replaceStrings ["[Google Mail]"] ["[Gmail]"] s) ]
    else [ s ];

  confQuote = s:
    let esc = builtins.replaceStrings [ "\"" ] [ "\\\"" ] s;
    in "\"" + esc + "\"";

  # Include Proton custom folders; keep Gmail special-casing for aliases
  patternsFor = a:
    let
      raw0 = a.sync.patterns or [ "INBOX" ];
      raw  =
        if a.type == "proton-bridge"
        then raw0 ++ [ "Folders/*" ]   # Proton Bridge exposes custom folders here
        else raw0;
    in
      if common.isGmail a
      then lib.unique (map escapeSquareBrackets (lib.concatLists (map expandGoogleAliases raw)))
      else lib.unique raw;

  getOr = a: n: def:
    if common.hasField a n then
      let v = common.getField a n; in
      if v == null then def else
      if builtins.isString v then (if v == "" then def else v) else v
    else def;

  mbsyncBlock = a:
    let
      cmd   = common.passCmd a;
      imapH = getOr a "imapHost" (common.imapHost a);
      imapP = getOr a "imapPort" (common.imapPort a);
      tlsT  = getOr a "imapTls"  (common.tlsType a);
      extra = getOr a "extraMbsync" "";
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

      Channel ${a.name}
      Far :${a.name}-remote:
      Near :${a.name}-local:
      Patterns ${patStr}
      ${createPolicy}
      Expunge Both
      SyncState *
      ${extra}
    '';

  mbsyncrc = lib.concatStringsSep "\n\n" (map mbsyncBlock vals);
in
{
  inherit mbsyncrc haveProton;
  packages = [ pkgs.isync pkgs.pass pkgs.gnupg ];
}
