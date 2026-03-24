# domains/home/apps/hyprland/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.hyprland;
  isNixOSHost = osConfig ? hwc;

  theme      = import ./parts/theme.nix      { inherit config lib pkgs; };
  behavior   = import ./parts/behavior.nix   { inherit config lib pkgs; };
  session    = import ./parts/session.nix    { inherit config lib pkgs; osConfig = osConfig; };

  hw = if builtins.pathExists ./parts/hardware.nix
       then import ./parts/hardware.nix { inherit lib pkgs; }
       else {};

  wallpaperPath = ../../theme/nord-mountains.jpg;

  basePkgs = with pkgs; [
    wofi hyprshot grim hypridle swaybg swaylock cliphist wl-clipboard
    brightnessctl networkmanager wirelesstools hyprsome wlogout fend
    socat  # For monitor hotplug listener
  ];

  # Monitor hotplug listener script
  monitorListenerPkg = pkgs.writeShellScriptBin "hyprland-monitor-listener" ''
    #!/usr/bin/env bash
    # Listen to Hyprland IPC socket for monitor events and restart waybar

    SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

    # Wait for socket to exist
    for i in {1..30}; do
      [[ -S "$SOCKET" ]] && break
      sleep 1
    done

    if [[ ! -S "$SOCKET" ]]; then
      echo "hyprland-monitor-listener: socket not found after 30s, exiting" >&2
      exit 1
    fi

    echo "hyprland-monitor-listener: listening on $SOCKET"

    ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$SOCKET" | while read -r line; do
      case "$line" in
        monitoradded*|monitorremoved*)
          echo "hyprland-monitor-listener: $line - restarting waybar"
          # Small delay to let monitor fully initialize
          sleep 1
          ${pkgs.systemd}/bin/systemctl --user restart waybar
          ;;
      esac
    done
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.hyprland = {
    enable = lib.mkEnableOption "Hyprland window manager";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
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
    home.packages = basePkgs ++ (session.packages or []) ++ [ monitorListenerPkg ];

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    home.file.".local/state/hypr/.keep".text = "";

    # Monitor hotplug listener - restarts waybar when monitors are added/removed
    systemd.user.services.hyprland-monitor-listener = {
      Unit = {
        Description = "Hyprland monitor hotplug listener";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${monitorListenerPkg}/bin/hyprland-monitor-listener";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = { WantedBy = [ "graphical-session.target" ]; };
    };

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

    # Wallpaper — swaybg is simpler and avoids hyprpaper IPC version mismatches
    # swaybg is launched in session.nix exec-once

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for system-lane dependencies
      {
        assertion = !cfg.enable || !isNixOSHost || (osConfig.hwc.system.apps.hyprland.enable or false);
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
        assertion = !cfg.enable || config.hwc.home.apps.kitty.enable;
        message = "hyprland requires kitty as session-critical terminal (SUPER+RETURN, multiple keybinds)";
      }
      {
        assertion = !cfg.enable || config.hwc.home.apps.yazi.enable;
        message = "hyprland requires yazi as file manager (SUPER+1, SUPER+T keybinds)";
      }
    ];
  };
}
