{ lib, pkgs, config, osConfig ? {}}:
let
  cfg  = config.hwc.home.mail;
  accs = cfg.accounts or {};
  vals = lib.attrValues accs;
  common = import ../../parts/common.nix { inherit lib; };

  getOr = a: n: def:
    if common.hasField a n then
      let v = common.getField a n; in
      if v == null then def else
      if builtins.isString v then (if v == "" then def else v) else v
    else def;

  msmtpBlock = a:
    let
      cmd = common.passCmd a;
      host = getOr a "smtpHost" (common.smtpHost a);
      port = getOr a "smtpPort" (common.smtpPort a);
      extra = getOr a "extraMsmtp" "";
      startTLS = getOr a "startTLS" (common.startTLS a);
      authLine = if a.type == "proton-bridge" then "auth plain" else "auth on";
      tlsLines = if startTLS then "tls on\ntls_starttls on" else "tls off\ntls_starttls off";
      certLine = if a.type == "proton-bridge" then "tls_trust_file /etc/ssl/local/proton-bridge.pem" else "";
      label = a.send.msmtpAccount;
    in ''
      account ${label}
      host ${host}
      port ${toString port}
      ${tlsLines}
      ${lib.optionalString (certLine != "") certLine}
      ${authLine}
      from ${a.address}
      user ${common.loginOf a}
      passwordeval "${cmd}"
      ${extra}
    '';

  primary =
    let p = lib.filter (a: a.primary or false) vals;
    in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);

  defaultLabel = if primary == null then "" else primary.send.msmtpAccount;

  configText = ''
    defaults
    auth on
    tls on
    tls_trust_file /etc/ssl/certs/ca-bundle.crt
    logfile ~/.config/msmtp/msmtp.log

    ${lib.concatStringsSep "\n\n" (map msmtpBlock vals)}

    ${lib.optionalString (defaultLabel != "") "account default : ${defaultLabel}"}
  '';
in
{
  inherit configText;
  packages = [ pkgs.msmtp ];
  files = {
    ".config/msmtp/config".text = configText;
    ".config/msmtp/msmtp.log".text = "";
  };
}