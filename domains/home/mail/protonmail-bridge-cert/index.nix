{ config, lib, pkgs, ... }:
let
  openssl = pkgs.openssl;
  inetutils = pkgs.inetutils;

  waitFor1143 = pkgs.writeShellScript "wait-for-bridge-1143" ''
    set -euo pipefail
    for i in $(seq 1 60); do
      if ${inetutils}/bin/telnet 127.0.0.1 1143 </dev/null 2>/dev/null | grep -qi "Escape character"; then
        exit 0
      fi
      sleep 0.5
    done
    echo "Port 1143 did not become ready" >&2
    exit 1
  '';

  exportCert = pkgs.writeShellScript "export-proton-bridge-cert" ''
    set -euo pipefail
    install -d -m 0755 /etc/ssl/local
    ${openssl}/bin/openssl s_client -starttls imap -connect 127.0.0.1:1143 -showcerts </dev/null 2>/dev/null \
      | ${openssl}/bin/openssl x509 -out /etc/ssl/local/proton-bridge.pem
    chmod 0644 /etc/ssl/local/proton-bridge.pem
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf config.hwc.system.services.protonmail-bridge-cert.enable {
    systemd.services.protonmail-bridge-cert = {
      description = "Export Proton Bridge IMAP STARTTLS certificate";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "protonmail-bridge.service" ];
      wants = [ "network-online.target" ];
      requires = [ "protonmail-bridge.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${waitFor1143}";
        ExecStartPost = "${exportCert}";
      };
    };
    assertions = [];
  };

}
