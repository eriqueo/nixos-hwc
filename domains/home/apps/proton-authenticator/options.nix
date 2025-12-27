{ lib, ... }:

{
  options.hwc.home.apps.proton-authenticator = {
    enable = lib.mkEnableOption "Two-factor authentication manager with optional sync";

    # Auto-start configuration
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-start Proton Authenticator on login";
    };
  };
}
