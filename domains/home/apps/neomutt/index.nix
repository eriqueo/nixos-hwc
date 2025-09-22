# modules/home/apps/neomutt/index.nix
{ lib, pkgs, config, ... }:

let
  enabled   = config.features.neomutt.enable or false;

  theme     = import ./parts/theme.nix     { inherit config lib; };
  appearance= import ./parts/appearance.nix{ inherit lib pkgs config theme; };
  behavior  = import ./parts/behavior.nix  { inherit lib pkgs config; };
  session   = import ./parts/session.nix   { inherit lib pkgs config; };

in {
  imports = [ ./options.nix ];
  config = lib.mkIf enabled {
    home.packages         = (session.packages or []);
    home.sessionVariables = (session.env or {});
    systemd.user.services = (session.services or {});

    # Parts only return data → index coordinates home.file
    home.file = lib.mkMerge [
      (appearance.files config.home.homeDirectory)
      (behavior.files   config.home.homeDirectory)
      # session.files if you add any, like icons
    ];
  };
}
