{ lib, ... }:

{
  options.hwc.home.apps.protonAuthenticator = {
    enable = lib.mkEnableOption "Proton Authenticator - Two-factor authentication manager with optional sync";
  };
}