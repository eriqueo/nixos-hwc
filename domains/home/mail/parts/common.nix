{ lib }:
let
  hasField = a: n: builtins.hasAttr n a;
  getField = a: n: if hasField a n then builtins.getAttr n a else null;
  hasText  = s: builtins.isString s && s != "";

  loginOf = a:
    let try = n: if hasField a n && hasText (getField a n) then getField a n else null;
    in if      try "login"          != null then try "login"
       else if try "bridgeUsername" != null then try "bridgeUsername"
       else if try "address"        != null then try "address"
       else "";

  isGmail = a: a.type == "gmail";

  imapHost = a: if a.type == "proton-bridge" then "127.0.0.1" else "imap.gmail.com";
  imapPort = a: if a.type == "proton-bridge" then 1143        else 993;
  tlsType  = a: if a.type == "proton-bridge" then "STARTTLS" else "IMAPS";

  smtpHost = a: if a.type == "proton-bridge" then "127.0.0.1" else "smtp.gmail.com";
  smtpPort = a: if a.type == "proton-bridge" then 1025        else 587;
  startTLS = a: if a.type == "proton-bridge" then true        else true;

  passCmd = a:
    let
      entry      = if a.password.mode == "pass"   then lib.escapeShellArg a.password.pass else null;
      agenixPath = if a.password.mode == "agenix" then lib.escapeShellArg (toString a.password.agenix) else null;
    in
    if a.password.mode == "pass" then
      ''sh -c 'pass show ${entry}' ''
    else if a.password.mode == "agenix" then
      ''sh -c 'tr -d "\n" < "$0"' ${agenixPath}''
    else if a.type == "proton-bridge" then
      ''cat /run/agenix/proton-bridge-password''
    else
      a.password.command;

  md = a:
    if hasField a "maildirName" && hasText (getField a "maildirName")
    then a.maildirName
    else (a.name or "");

  rolesFor = a:
    let base = md a; in
    if isGmail a then {
      sent    = [ "${base}/[Gmail]/Sent Mail" ];
      drafts  = [ "${base}/[Gmail]/Drafts" ];
      trash   = [ "${base}/[Gmail]/Trash" ];
      spam    = [ "${base}/[Gmail]/Spam" ];
      archive = [ "${base}/[Gmail]/All Mail" ];
    } else {
      sent    = [ "${base}/Sent" ];
      drafts  = [ "${base}/Drafts" ];
      trash   = [ "${base}/Trash" ];
      spam    = [ "${base}/Spam" ];
      archive = [ "${base}/Archive" "${base}/All Mail" ];
    };

  imapDefaultsFor = a: {
    host   = imapHost a;
    port   = imapPort a;
    tlsType = tlsType a;
    user   = loginOf a;
  };

  smtpDefaultsFor = a: {
    host     = smtpHost a;
    port     = smtpPort a;
    startTLS = startTLS a;
    user     = loginOf a;
  };
in
{
  inherit
    hasField getField hasText loginOf isGmail
    imapHost imapPort tlsType smtpHost smtpPort startTLS
    passCmd
    md rolesFor imapDefaultsFor smtpDefaultsFor;
}
