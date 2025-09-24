# modules/home/apps/aerc/index.nix
{ lib, pkgs, config, ... }:

let
  enabled = config.hwc.home.apps.aerc.enable or false;
  
  # Import the part that generates the config files
  aercConfig = import ./parts/config.nix { inherit lib pkgs config; };

in {
  imports = [ ./options.nix ];

  config = lib.mkIf enabled {
    # 1. Install the aerc package
    home.packages = [ pkgs.aerc ];

    # 2. Generate the configuration files
    home.file = aercConfig.files;
  };
}
