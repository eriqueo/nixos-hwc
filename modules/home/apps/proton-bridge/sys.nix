# Co-located system lane for ProtonMail Bridge
{ lib, config, pkgs, ... }:
let
  cfg = config.features.protonBridge;
in {
  imports = [ ./options.nix ];
  config = lib.mkIf cfg.enable {
    # System-level configuration for ProtonMail Bridge
    # Currently minimal - Bridge runs as user service per Charter
    # Could add system packages or firewall rules here if needed
  };
}