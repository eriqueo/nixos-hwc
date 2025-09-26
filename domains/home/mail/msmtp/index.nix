{ config, lib, pkgs, ... }:
let
  enabled = config.hwc.home.mail.enable or false;
  accs = config.hwc.home.mail.accounts or {};
  vals = lib.attrValues accs;
  common = import ../parts/common.nix { inherit lib; };

  primary =
    let p = lib.filter (a: a.primary or false) vals;
    in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);

  msmtpBlock = a:
    let
      cmd   = common.passCmd a;
      host  = if a.smtpHost != null then a.smtpHost else common.smtpHost a;
      port  = if a.smtpPort != null then a.smtpPort else common.smtpPort a;
      stls  = if a.startTLS != null then a.startTLS else common.startTLS a;
      authLine = if a.type == "proton-bridge" then "auth plain" else "auth on";
    in ''
      account ${a.send.msmtpAccount}
      host ${host}
      port ${toString port}
      ${if stls then "tls on\ntls_starttls on" else "tls off\ntls_starttls off"}
      ${authLine}
      from ${a.address}
      user ${common.loginOf a}
      passwordeval "${cmd}"
      ${a.extraMsmtp}
    '';
in
{
  config = lib.mkIf enabled {
    home.packages = [ pkgs.msmtp pkgs.pass pkgs.gnupg ];

    home.activation.msmtpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      mkdir -p "$HOME/.config/msmtp"
      cat > "$HOME/.config/msmtp/config" <<'EOF'
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-bundle.crt
logfile ~/.config/msmtp/msmtp.log

${lib.concatStringsSep "\n\n" (map msmtpBlock vals)}

${lib.optionalString (primary != null) "account default : ${primary.send.msmtpAccount}"}
EOF
      chmod 600 "$HOME/.config/msmtp/config"
      : > "$HOME/.config/msmtp/msmtp.log"
      chmod 600 "$HOME/.config/msmtp/msmtp.log"
    '';
  };
}
