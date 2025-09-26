{ config, lib, pkgs, ... }:
let
  cfg  = config.hwc.home.mail;
  accs = cfg.accounts or {};
  vals = lib.attrValues accs;
  on = (cfg.enable or true) && (cfg.msmtp.enable or true) && (vals != []);

  common = import ../parts/common.nix { inherit lib; };
  msmtpBlock = a: let
    cmd = common.passCmd a;
    host = if a.smtpHost != null then a.smtpHost else common.smtpHost a;
    port = if a.smtpPort != null then a.smtpPort else common.smtpPort a;
    startTLS = if a.startTLS != null then a.startTLS else common.startTLS a;
  in ''
    account ${a.send.msmtpAccount}
    host ${host}
    port ${toString port}
    ${if startTLS then "tls on\ntls_starttls on" else "tls off\ntls_starttls off"}
    ${if a.type == "proton-bridge" then "auth plain" else "auth on"}
    from ${a.address}
    user ${common.loginOf a}
    passwordeval "${cmd}"
    ${a.extraMsmtp}
  '';
  primary =
    let p = lib.filter (a: a.primary or false) vals;
    in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);
  defaultLabel = if primary == null then "" else primary.send.msmtpAccount;
in
{
  config = lib.mkIf on {
    home.packages = [ pkgs.msmtp ];

    home.file.".config/msmtp/config" = {
      text = ''
        defaults
        auth on
        tls on
        tls_trust_file /etc/ssl/certs/ca-bundle.crt
        logfile ~/.config/msmtp/msmtp.log

        ${lib.concatStringsSep "\n\n" (map msmtpBlock vals)}

        ${lib.optionalString (defaultLabel != "") "account default : ${defaultLabel}"}
      '';
    };

    home.file.".config/msmtp/msmtp.log".text = "";
  };
}
