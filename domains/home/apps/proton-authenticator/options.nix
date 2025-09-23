{ lib, ... }:

{
  options.hwc.home.apps.protonAuthenticator = {
    enable = lib.mkEnableOption "Two-factor authentication manager with optional sync";
  };
}
