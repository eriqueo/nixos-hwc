# modules/home/apps/proton-mail/options.nix
{ lib, ... }:

{
  options.features.protonMail = {
    enable = lib.mkEnableOption "Enable ProtonMail desktop client";
    
    # Auto-start configuration
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-start ProtonMail on login";
    };
  };
}