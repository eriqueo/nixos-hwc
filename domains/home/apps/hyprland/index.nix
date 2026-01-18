# domains/home/apps/hyprland/index.nix
#
# HYPRLAND — Window manager + user session.

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  enabled = config.hwc.home.apps.hyprland.enable or false;

  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;

  theme      = import ./parts/theme.nix      { inherit config lib pkgs; };
  behavior   = import ./parts/behavior.nix   { inherit config lib pkgs; };
  session    = import ./parts/session.nix    { inherit config lib pkgs; };

  hw = if builtins.pathExists ./parts/hardware.nix
       then import ./parts/hardware.nix { inherit lib pkgs; }
       else {};

  wallpaperPath = ../../theme/nord-mountains.jpg;

  basePkgs = with pkgs; [
    wofi hyprshot grim hypridle hyprpaper hyprlock cliphist wl-clipboard
    brightnessctl networkmanager wirelesstools hyprsome wlogout
  ];
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  config = lib.mkIf enabled {
    #==========================================================================
    # DEPENDENCY FORCING (Home domain only)
    #==========================================================================
    # Hyprland requires these home apps - enforce at module level
    hwc.home.apps.waybar.enable = lib.mkForce true;
    hwc.home.apps.swaync.enable = lib.mkForce true;
    # System-level forcing done in sys.nix

    #==========================================================================
    # IMPLEMENTATION
    #==========================================================================
    home.packages = basePkgs ++ (session.packages or []);

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    home.file.".local/state/hypr/.keep".text = "";

    wayland.windowManager.hyprland = {
      enable  = true;
      package = pkgs.hyprland;

      settings = lib.mkMerge [
        {
          debug = {
            enable_stdout_logs = false;
          };
        }

        (lib.optionalAttrs (hw ? monitor   && hw.monitor   != null) { monitor   = hw.monitor;   })
        (lib.optionalAttrs (hw ? workspace && hw.workspace != null) { workspace = hw.workspace; })
        (lib.optionalAttrs (hw ? input     && hw.input     != null) { input     = hw.input;     })

        behavior

        (lib.optionalAttrs (session ? execOnce && session.execOnce != null) { "exec-once" = session.execOnce; })
        (lib.optionalAttrs (session ? env      && session.env      != null) { env         = session.env;      })

        theme
      ];
    };

    home.file.".config/hypr/hyprpaper.conf".text = ''
      preload = ${wallpaperPath}
      wallpaper = eDP-1,${wallpaperPath}
      wallpaper = DP-1,${wallpaperPath}
      splash = false
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for system-lane dependencies
      {
        assertion = !enabled || !isNixOSHost || (osConfig.hwc.system.apps.hyprland.enable or false);
        message = ''
          hwc.home.apps.hyprland is enabled but hwc.system.apps.hyprland is not.
          System dependencies (hyprland-startup script, helper scripts) are required.
          Enable hwc.system.apps.hyprland in machine config.
        '';
      }

      # Home-lane dependencies
      {
        assertion = config.hwc.home.apps.waybar.enable;
        message = "hyprland requires waybar (critical dependency - forced via mkForce)";
      }
      {
        assertion = config.hwc.home.apps.swaync.enable;
        message = "hyprland requires swaync notification daemon (critical dependency - forced via mkForce)";
      }
      {
        assertion = !enabled || config.hwc.home.apps.kitty.enable;
        message = "hyprland requires kitty as session-critical terminal (SUPER+RETURN, multiple keybinds)";
      }
      {
        assertion = !enabled || config.hwc.home.apps.yazi.enable;
        message = "hyprland requires yazi as file manager (SUPER+1, SUPER+T keybinds)";
      }
    ];
  };
}
