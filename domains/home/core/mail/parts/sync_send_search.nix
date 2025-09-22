# modules/home/core/mail/parts/sync_send_search.nix
{ config, lib, pkgs, ... }:

let
  accs = config.features.mail.accounts or {};
  vals = lib.attrValues accs;

  # ---------------- helpers ----------------
  passCmd = a:
    let
      pass = "/run/current-system/sw/bin/pass";
      entry      = if a.password.mode == "pass"   then lib.escapeShellArg a.password.pass            else null;
      agenixPath = if a.password.mode == "agenix" then lib.escapeShellArg (toString a.password.agenix) else null;
    in
    if a.password.mode == "pass" then
      ''env -i HOME="$HOME" GNUPGHOME="$HOME/.gnupg" PASSWORD_STORE_DIR="$HOME/.password-store" PATH="/run/current-system/sw/bin" ${pass} show ${entry}''
    else if a.password.mode == "agenix" then
      ''sh -c 'tr -d "\n" < "$0"' ${agenixPath}''
    else
      a.password.command;

  imapHost = a: if a.type == "proton-bridge" then "127.0.0.1" else "imap.gmail.com";
  imapPort = a: if a.type == "proton-bridge" then 1143        else 993;
  tlsType  = a: if a.type == "proton-bridge" then "None"      else "IMAPS";

  smtpHost = a: if a.type == "proton-bridge" then "127.0.0.1" else "smtp.gmail.com";
  smtpPort = a: if a.type == "proton-bridge" then 1025        else 587;
  startTLS = a: if a.type == "proton-bridge" then false       else true;

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

  # ---------------- msmtp ----------------
  msmtpBlock = a:
    let cmd = passCmd a;
    in ''
      account ${a.send.msmtpAccount}
      host ${smtpHost a}
      port ${toString (smtpPort a)}
      ${if startTLS a then "tls on\ntls_starttls on" else "tls off\ntls_starttls off"}
      ${if a.type == "proton-bridge" then "auth plain" else "auth on"}
      from ${a.address}
      user ${loginOf a}
      passwordeval "${cmd}"
    '';

  primary =
    let p = lib.filter (a: a.primary or false) vals;
    in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);

  # ---------------- mbsync ----------------
  mbsyncBlock = a:
    let
      cmd = passCmd a;
      createPolicy = if isGmail a then "Create Near" else "Create Both";
    in ''
      IMAPAccount ${a.name}
      Host ${imapHost a}
      Port ${toString (imapPort a)}
      User ${loginOf a}
      PassCmd "${cmd}"
      TLSType ${tlsType a}

      IMAPStore ${a.name}-remote
      Account ${a.name}

      MaildirStore ${a.name}-local
      Path ~/Maildir/${a.maildirName}/
      Inbox ~/Maildir/${a.maildirName}/INBOX
      SubFolders Verbatim

      Channel ${a.name}-all
      Far :${a.name}-remote:
      Near :${a.name}-local:
      Patterns ${lib.concatStringsSep " " (map (p: lib.escapeShellArg p) a.sync.patterns)}
      ${createPolicy}
      Expunge Both
      SyncState *
    '';

  # A reasonable notmuch default; safe if user doesn’t care
  primaryAddr = if primary == null then "" else (primary.address or "");
  maildirRoot = "${config.home.homeDirectory}/Maildir";

in
{
  # Packages (safe to add here; core plumbing)
  home.packages = with pkgs; [ isync msmtp notmuch abook pass gnupg ];

  # mbsync
  home.file.".mbsyncrc".text =
    lib.concatStringsSep "\n\n" (map mbsyncBlock vals);

  # msmtp (write locked-down file)
  home.activation.msmtpConfig = lib.mkIf (primary != null) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu
    mkdir -p "$HOME/.config/msmtp"
    cat > "$HOME/.config/msmtp/config" <<'EOF'
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-bundle.crt
logfile ~/.config/msmtp/msmtp.log

${lib.concatStringsSep "\n\n" (map msmtpBlock vals)}

account default : ${primary.send.msmtpAccount}
EOF
    chmod 600 "$HOME/.config/msmtp/config"
    : > "$HOME/.config/msmtp/msmtp.log"
    chmod 600 "$HOME/.config/msmtp/msmtp.log"
  '');

  # notmuch (non-destructive; user can overwrite later)
  home.file.".notmuch-config".text = ''
    [database]
    path=${maildirRoot}

    [user]
    name=${config.home.username or "user"}
    primary_email=${primaryAddr}

    [new]
    tags=unread;inbox;
    ignore=
  '';
}
