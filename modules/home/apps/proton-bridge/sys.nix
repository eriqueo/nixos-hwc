# Co-located system lane for ProtonMail Bridge
{ lib, config, pkgs, ... }:
let
  cfg = config.features.protonBridge;
in {
  imports = [ ./options.nix ];
  config = lib.mkIf cfg.enable {
    # System-level configuration for ProtonMail Bridge
    environment.systemPackages = with pkgs; [
      pass  # Password manager required by ProtonMail Bridge
      gnupg # Required by pass for encryption
    ];
  };
}