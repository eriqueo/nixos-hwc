{ config, lib, pkgs, ... }:

let
  enabled = config.features.hyprland.enable or false;

  # Parts must return flat attrsets (no nested `settings = {}` inside them)
  theme      = import ./parts/theme.nix      { inherit config lib pkgs; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs theme;  };
  behavior   = import ./parts/behavior.nix   { inherit config lib pkgs;        };
  session    = import ./parts/session.nix    { inherit config lib pkgs;        };

  # Optional hardware part (guarded import)
  hw = if builtins.pathExists ./parts/hardware.nix
       then import ./parts/hardware.nix { inherit lib pkgs; }
       else {};

  wallpaperPath = ../../theme/nord-mountains.jpg;

  # >>> DEFINE basePkgs IN THIS LET <<<
  basePkgs = with pkgs; [
    wofi hyprshot hypridle hyprpaper hyprlock cliphist wl-clipboard
    brightnessctl networkmanager wirelesstools hyprsome
  ];
in
{
  config = lib.mkIf enabled {
    # list ++ list (DON'T use `pkgs ++ …`)
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

        # Session bits (guarded)
        (lib.optionalAttrs (session ? execOnce && session.execOnce != null) { "exec-once" = session.execOnce; })
        (lib.optionalAttrs (session ? env      && session.env      != null) { env         = session.env;      })

        # Appearance (already merged with theme)
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
