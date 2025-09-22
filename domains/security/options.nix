# modules/security/options.nix
{ lib, ... }:

{
  # Security domain enable option
  options.hwc.security.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable security domain with secrets management";
  };
}