# Co-located system lane for ProtonMail Bridge
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.home.apps.protonBridge;
in {
  imports = [ ./options.nix ];
  config = lib.mkIf cfg.enable {
    # System-level configuration for ProtonMail Bridge
    # pass and gnupg are now provided by base system packages
  };
}