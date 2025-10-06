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

  # Process mailboxMapping attribute - generates "Remote" "Local" pattern pairs
  patternsFor = a:
    let
      # Use the mailboxMapping attribute from account config
      mapping = a.mailboxMapping or {};

      # Convert attrset to list of quoted "Remote" "Local" pairs
      mappedPatterns = lib.mapAttrsToList
        (remoteName: localName: "${confQuote remoteName} ${confQuote localName}")
        mapping;

      # Allow for additional wildcard patterns if needed
      wildcards = a.sync.wildcards or [];
      wildcardPatterns = map confQuote wildcards;

      # Combine mapped patterns with wildcards
      allPatterns = mappedPatterns ++ wildcardPatterns;

      # For Gmail, expand [Gmail] <-> [Google Mail] aliases in remote names
      processedPatterns =
        if common.isGmail a
        then map escapeSquareBrackets allPatterns
        else allPatterns;
    in
      if allPatterns == []
      then [ (confQuote "INBOX") ]  # Fallback to INBOX if no mapping defined
      else lib.unique processedPatterns;

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
      patStr = lib.concatStringsSep " " (patternsFor a);
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
