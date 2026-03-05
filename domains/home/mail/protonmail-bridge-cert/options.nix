# domains/system/services/protonmail-bridge-cert/options.nix
# Toggle for exporting Proton Bridge IMAP certificate

{ lib, ... }:
{
  options.hwc.home.mail.protonmailBridgeCert = {
    enable = lib.mkEnableOption "export Proton Bridge IMAP STARTTLS certificate" // {
      default = true;
    };
  };
}
