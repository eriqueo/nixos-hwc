# domains/system/services/protonmail-bridge-cert/options.nix
# Toggle for exporting Proton Bridge IMAP certificate

{ lib, ... }:
{
  options.hwc.system.services.protonmail-bridge-cert = {
    enable = lib.mkEnableOption "export Proton Bridge IMAP STARTTLS certificate" // {
      default = true;
    };
  };
}
