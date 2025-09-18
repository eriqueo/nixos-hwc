{ config, lib, pkgs, ... }:
let
  accs = config.features.neomutt.accounts or {};
  vals = lib.attrValues accs;

  # ---- helpers ---------------------------------------------------------------
  passCmd = a:
    let
      pass = "/run/current-system/sw/bin/pass";
      entry = if a.password.mode == "pass" then lib.escapeShellArg a.password.pass else null;
      agenixPath = if a.password.mode == "agenix" then lib.escapeShellArg (toString a.password.agenix) else null;
    in
    if a.password.mode == "pass" then
      # NOTE: double quotes so $HOME expands at runtime
      ''env -i HOME="$HOME" GNUPGHOME="$HOME/.gnupg" PASSWORD_STORE_DIR="$HOME/.password-store" PATH="/run/current-system/sw/bin" ${pass} show ${entry}''
    else if a.password.mode == "agenix" then
      # robust path handling via $0 to avoid quoting hell
      ''sh -c 'tr -d "\n" < "$0"' ${agenixPath}''
    else
      a.password.command;

  imapHost = a: if a.type == "proton-bridge" then "127.0.0.1" else "imap.gmail.com";
  imapPort = a: if a.type == "proton-bridge" then 1143 else 993;
  tlsType  = a: if a.type == "proton-bridge" then "None" else "IMAPS";

  smtpHost = a: if a.type == "proton-bridge" then "127.0.0.1" else "smtp.gmail.com";
  smtpPort = a: if a.type == "proton-bridge" then 1025 else 587;
  startTLS = a: if a.type == "proton-bridge" then false else true;
  loginOf = a:
    let has = s: (s or "") != "";
    in if has a.login then a.login
       else if a.type == "proton-bridge" && has a.bridgeUsername then a.bridgeUsername
       else a.address;  # last resort

  isGmail = a: a.type == "gmail";

  primary =
    let p = lib.filter (a: a.primary or false) vals;
    in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);

  # msmtp per-account block
  msmtpBlock = a:
    let cmd = passCmd a;
    in ''
      account ${a.send.msmtpAccount}
      host ${smtpHost a}
      port ${toString (smtpPort a)}
      ${if startTLS a then "tls_starttls on\ntls on" else "tls off"}
      from ${a.address}
      user ${loginOf a}
      passwordeval "${cmd}"
    '';

  # mbsync per-account block
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
      # AuthMechs *     # (optional) force all mechs; usually not needed

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

  haveProton = lib.any (a: a.type == "proton-bridge") vals;

in
{
  # ---------------- mbsync ----------------------------------------------------
  home.file.".mbsyncrc".text = lib.concatStringsSep "\n\n" (map mbsyncBlock vals);

  
  # Proton default secret path when useAgenixPassword=true:
  #   /run/agenix/proton-bridge-password
  home.file.".config/msmtp/config".text =
    let
      # accounts as a list of values (you already have accs/vals defined above)
      mkMsmtp = a:
        let
          isBridge = (a.type or "proton-bridge") == "proton-bridge";
          host     = if isBridge then "127.0.0.1"     else "smtp.gmail.com";
          port     = if isBridge then 1025           else 587;
          tlsLines = if isBridge then "tls off"      else "tls on\ntls_starttls on";
          fromAddr = (a.address or a.email);
          userName = (a.login or a.bridgeUsername or a.email);
          pwCmd =
            if (a ? bridgePasswordCommand) && a.bridgePasswordCommand != null then a.bridgePasswordCommand
            else if (a ? useAgenixPassword) && a.useAgenixPassword then "sh -c 'tr -d \"\\n\" < /run/agenix/proton-bridge-password'"
            else "sh -c 'echo ERROR: set bridgePasswordCommand or useAgenixPassword'";
          acctName = (a.name or fromAddr);
        in ''
          account ${acctName}
          host ${host}
          port ${toString port}
          ${tlsLines}
          from ${fromAddr}
          user ${userName}
          passwordeval "${pwCmd}"
        '';

      firstName = if accs != {} then lib.head (lib.attrNames accs) else "default";
    in ''
      defaults
      auth on
      tls_trust_file /etc/ssl/certs/ca-bundle.crt
      logfile ~/.config/msmtp/msmtp.log

      ${lib.concatStringsSep "\n\n" (map mkMsmtp vals)}

      account default : ${firstName}
    '';

  home.file.".config/msmtp/config".mode = "0600";
  home.file.".config/msmtp/msmtp.log".text = "";
  home.file.".config/msmtp/msmtp.log".mode = "0600";


  # ---------------- abook -----------------------------------------------------
  home.file.".abook/abookrc".text = ''
    [format]
    field delim = :
    addrfield delim = ;
    tuple delim = ,
    [options]
    autosave = yes
  '';
  home.file.".abook/addressbook".text = "# abook addressbook\n";

  # ---------------- user services/timers -------------------------------------
  # Proton Bridge (headless) as USER service if any proton account exists
  systemd.user.services.protonmail-bridge = lib.mkIf haveProton {
    Unit = {
      Description = "ProtonMail Bridge (headless)";
      After = [ "default.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive --log-level warn"
      ;
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "PATH=/run/current-system/sw/bin:${pkgs.pass}/bin"
        "PASSWORD_STORE_DIR=%h/.password-store"
        "GNUPGHOME=%h/.gnupg"
      ];
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # Periodic mbsync (user timer). Order it after Bridge when Proton is present.
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
