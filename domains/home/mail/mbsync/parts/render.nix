{ lib, pkgs, config }:
let
  cfg        = config.hwc.home.mail;
  accs       = cfg.accounts or {};
  common     = import ../../parts/common.nix { inherit lib; };
  maildirRoot = "${config.home.homeDirectory}/400_mail/Maildir";

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

  # Generate one Channel per mailbox mapping
  channelsFor = a:
    let
      mapping = a.mailboxMapping or {};
      wildcards = a.sync.wildcards or [];
      createPolicy = if common.isGmail a then "Create Near" else "Create Both";

      # Create one channel per mailbox mapping
      makeChannel = remoteName: localName:
        let
          # Clean channel name: remove special chars, use only alphanumeric and hyphens
          cleanName = lib.replaceStrings ["[" "]" "/" " "] ["" "" "-" "-"] remoteName;
          channelName = "${a.name}-${cleanName}";
          # Quote folder names if they contain spaces or special chars
          quotedRemote = confQuote remoteName;
          quotedLocal = confQuote localName;
        in ''
          Channel ${channelName}
          Far :${a.name}-remote:${quotedRemote}
          Near :${a.name}-local:${quotedLocal}
          ${createPolicy}
          Expunge Both
          SyncState *
        '';

      mappedChannels = lib.mapAttrsToList makeChannel mapping;

      # Wildcard channels (e.g., Folders/*) - use pattern-based channel
      wildcardChannel = if wildcards != [] then
        let
          wildcardPatterns = lib.concatStringsSep " " (map confQuote wildcards);
        in ''
          Channel ${a.name}-wildcards
          Far :${a.name}-remote:
          Near :${a.name}-local:
          Patterns ${wildcardPatterns}
          ${createPolicy}
          Expunge Both
          SyncState *
        ''
      else "";

      allChannels = mappedChannels ++ (if wildcardChannel != "" then [wildcardChannel] else []);
    in
      if allChannels == [] then
        # Fallback to simple INBOX channel if no mapping
        [''
          Channel ${a.name}
          Far :${a.name}-remote:
          Near :${a.name}-local:
          Patterns "INBOX"
          ${createPolicy}
          Expunge Both
          SyncState *
        '']
      else allChannels;

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
      channels = channelsFor a;
      channelsStr = lib.concatStringsSep "\n" channels;
      # Proton Bridge uses STARTTLS with a self-signed leaf; pin by file.
      certFile = if a.type == "proton-bridge"
                 then "CertificateFile /etc/ssl/local/proton-bridge.pem"
                 else "";
      tlsFingerprint = "";
    in ''
      IMAPAccount ${a.name}
      Host ${imapH}
      Port ${toString imapP}
      User ${common.loginOf a}
      PassCmd "${cmd}"
      TLSType ${tlsT}
      ${certFile}
      ${tlsFingerprint}

      IMAPStore ${a.name}-remote
      Account ${a.name}

      MaildirStore ${a.name}-local
      Path ${maildirRoot}/${a.maildirName}/
      Inbox ${maildirRoot}/${a.maildirName}/inbox
      SubFolders Verbatim

      ${channelsStr}
      ${extra}
    '';

  mbsyncrc = lib.concatStringsSep "\n\n" (map mbsyncBlock vals);
in
{
  inherit mbsyncrc haveProton;
  packages = [ pkgs.isync pkgs.pass pkgs.gnupg ];
}
