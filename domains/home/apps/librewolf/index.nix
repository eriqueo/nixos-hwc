{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.home.apps.librewolf;
  theme = import ../../theme/adapters/firefox-css.nix { inherit lib config; };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      package = pkgs.librewolf;

      profiles.hwc = {
        isDefault = true;

        settings = lib.mkMerge [
          (import ./parts/performance.nix { inherit lib; })
          (import ./parts/privacy.nix { inherit lib; })
          (import ./parts/ux.nix { inherit lib; })
        ];

        userChrome = theme.userChrome;
        userContent = theme.userContent;
      };
    };
  };
}
