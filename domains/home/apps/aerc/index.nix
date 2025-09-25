# modules/home/apps/aerc/index.nix
{ lib, pkgs, config, ... }:

let
  enabled = config.hwc.home.apps.aerc.enable or false;
  
  # Import the part that generates the config files
  aercConfig = import ./parts/config.nix { inherit lib pkgs config; };

in {
  imports = [ ./options.nix ];

   config = lib.mkIf enabled (lib.mkMerge [
    { home.packages = [ pkgs.aerc ]; }
    # aercConfig now provides the home.file attribute directly, so we merge it in
    aercConfig 
  ]);
}
