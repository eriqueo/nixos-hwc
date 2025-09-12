# modules/home/apps/hyprland/index.nix  (drop-in fix for the settings block)
{ config, lib, pkgs, ... }:
let
  enabled    = config.features.hyprland.enable or false;
  theme      = import ./parts/theme.nix      { inherit config lib pkgs; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs theme;  };
  behavior   = import ./parts/behavior.nix   { inherit lib pkgs;        };
  session    = import ./parts/session.nix    { inherit config lib pkgs;        };
  hw         = import ./parts/hardware.nix   { inherit lib pkgs; };
  wallpaperPath = ../../theme/nord-mountains.jpg;
in {
  options.features.hyprland.enable = lib.mkEnableOption "Enable Hyprland (HM)";

  config = lib.mkIf enabled {
    home.packages = basePkgs ++ (session.packages or []);

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    wayland.windowManager.hyprland = {
      enable  = true;
      package = pkgs.hyprland;

      settings = lib.mkMerge [
        # Guarded hardware keys — never write = null
        (lib.optionalAttrs (hw ? monitor   && hw.monitor   != null) { monitor   = hw.monitor;   })
        (lib.optionalAttrs (hw ? workspace && hw.workspace != null) { workspace = hw.workspace; })
        (lib.optionalAttrs (hw ? input     && hw.input     != null) { input     = hw.input;     })

        # Behavior (flat)
        behavior

        # Session (guarded)
        (lib.optionalAttrs (session ? execOnce && session.execOnce != null) { "exec-once" = session.execOnce; })
        (lib.optionalAttrs (session ? env      && session.env      != null) { env         = session.env;      })

        # Appearance/theme — use ONLY appearance, because it already merges `theme`
        appearance
      ];
    };

    home.file.".config/hypr/hyprpaper.conf".text = ''
      preload = ${wallpaperPath}
      wallpaper = eDP-1,${wallpaperPath}
      wallpaper = DP-1,${wallpaperPath}
      splash = false
    '';
  };
}
