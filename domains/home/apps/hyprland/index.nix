# domains/home/apps/hyprland/index.nix
#
# HYPRLAND — Window manager + user session.

{ config, lib, pkgs, ... }:

let
  enabled = config.hwc.home.apps.hyprland.enable or false;

  theme      = import ./parts/theme.nix      { inherit config lib pkgs; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs theme;  };
  behavior   = import ./parts/behavior.nix   { inherit config lib pkgs; };
  session    = import ./parts/session.nix    { inherit config lib pkgs; };

  hw = if builtins.pathExists ./parts/hardware.nix
       then import ./parts/hardware.nix { inherit lib pkgs; }
       else {};

  wallpaperPath = ../../theme/nord-mountains.jpg;

  basePkgs = with pkgs; [
    wofi hyprshot grim hypridle hyprpaper hyprlock cliphist wl-clipboard
    brightnessctl networkmanager wirelesstools hyprsome
  ];
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf enabled {
    home.packages = basePkgs ++ (session.packages or []);

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    wayland.windowManager.hyprland = {
      enable  = true;
      package = pkgs.hyprland;

      settings = lib.mkMerge [
        {
          debug = {
            enable_stdout_logs = true;
            log_file = "/home/eric/.local/state/hypr/hyprland.log";
          };
        }

        (lib.optionalAttrs (hw ? monitor   && hw.monitor   != null) { monitor   = hw.monitor;   })
        (lib.optionalAttrs (hw ? workspace && hw.workspace != null) { workspace = hw.workspace; })
        (lib.optionalAttrs (hw ? input     && hw.input     != null) { input     = hw.input;     })

        behavior

        (lib.optionalAttrs (session ? execOnce && session.execOnce != null) { "exec-once" = session.execOnce; })
        (lib.optionalAttrs (session ? env      && session.env      != null) { env         = session.env;      })

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
