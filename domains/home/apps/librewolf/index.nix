{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.home.apps.librewolf or { enable = false; };
  theme = import ./parts/theme.nix { inherit lib config; };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    programs.librewolf = {
      enable = true;
      package = pkgs.librewolf;

      profiles.hwc = {
        isDefault = true;

        settings = lib.mkMerge [
          (import ./parts/behavior.nix { inherit lib pkgs config; })
          (import ./parts/appearance.nix { inherit lib pkgs config; })
        ];

        userChrome  = theme.userChrome;
        userContent = theme.userContent;
      };
    };

    home.sessionVariables = {
      MOZ_ENABLE_WAYLAND = "1";
    };
  };
}
