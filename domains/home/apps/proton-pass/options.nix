# modules/home/apps/proton-pass/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.protonPass = {
    enable = lib.mkEnableOption "Enable ProtonPass password manager";
    
    # Auto-start configuration
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-start ProtonPass on login";
    };
    
    # Browser integration
    browserIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable browser extension integration";
    };
  };
}