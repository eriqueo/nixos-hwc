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
  tlsType  = a: if a.type == "proton-bridge" then "None"      else "IMAPS";

  smtpHost = a: if a.type == "proton-bridge" then "127.0.0.1" else "smtp.gmail.com";
  smtpPort = a: if a.type == "proton-bridge" then 1025        else 587;
  startTLS = a: if a.type == "proton-bridge" then false       else true;

  passCmd = a:
    let
      pass = "/run/current-system/sw/bin/pass";
      entry      = if a.password.mode == "pass"   then lib.escapeShellArg a.password.pass else null;
      agenixPath = if a.password.mode == "agenix" then lib.escapeShellArg (toString a.password.agenix) else null;
    in
    if a.password.mode == "pass" then
      ''env -i HOME="$HOME" GNUPGHOME="$HOME/.gnupg" PASSWORD_STORE_DIR="$HOME/.password-store" PATH="/run/current-system/sw/bin" ${pass} show ${entry}''
    else if a.password.mode == "agenix" then
      ''sh -c 'tr -d "\n" < "$0"' ${agenixPath}''
    else
      a.password.command;
in
{
  inherit hasField getField hasText loginOf isGmail imapHost imapPort tlsType smtpHost smtpPort startTLS passCmd;
}
