# domains/home/apps/courier/index.nix
# courier — our iPhone messages app, a client of tetherd (apps/tether). The app
# (github:eriqueo/courier) owns behaviour, protocol handling and tests; this
# module supplies the palette, runs the service and wires the desktop.
#
# The window is Chromium in app mode at http://courier.localhost:<port>.
# Chromium ignores --class on Wayland and derives the app_id from the host, so
# Hyprland matches `chrome-courier.localhost__-Default` (measured 2026-10-12).
# The hotkey and window rule for that class live in hyprland/parts/behavior.nix.

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.home.apps.courier;
  app = inputs.courier.packages.${pkgs.stdenv.hostPlatform.system}.default;
  colors = config.hwc.home.theme.colors;

  # An alert's Open: show the window, never toggle it. The same helper as
  # SUPER+U (hyprland/index.nix), which is on the session PATH.
  showWindow = pkgs.writeShellScript "courier-show-window" ''
    exec hyprland-app-toggle --show ${lib.escapeShellArg cfg.windowClass} courier open
  '';

  # The HWC palette as CSS variables. hwc.nix stays the only producer: every
  # 6-digit hex token is exported under its own name (--bg1, --accent, …).
  isHex = v: builtins.isString v && builtins.match "[0-9a-fA-F]{6}" v != null;
  themeFile = pkgs.writeText "courier-theme.css" (
    ":root {\n"
    + lib.concatStrings (lib.mapAttrsToList (name: v: "  --${name}: #${v};\n") (lib.filterAttrs (_: isHex) colors))
    + "}\n"
  );
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.courier = {
    enable = lib.mkEnableOption "courier, the iPhone messages app over Tether";

    port = lib.mkOption {
      type = lib.types.port;
      default = 47318;
      description = "Loopback port for courier's API and UI (127.0.0.1 only).";
    };

    windowClass = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "chrome-courier.localhost__-Default";
      description = "Wayland app_id of the courier window, for Hyprland rules.";
    };

    alerts.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        courier shows the desktop alerts for new messages (Open, Mark read,
        Copy code, per-conversation hide, burst cap). This turns tetherd's own
        message popup off (message_popups_enabled, from the HWC tether patch);
        tetherd keeps showing other phone notifications. Off: courier shows no
        alerts and tetherd's message popup stays on.
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ app ];
    home.sessionVariables.COURIER_PORT = toString cfg.port;

    systemd.user.services.courier = {
      Unit = {
        Description = "courier (iPhone messages over Tether)";
        After = [ "graphical-session.target" "tetherd.service" ];
        Wants = [ "tetherd.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${app}/bin/courier serve";
        Environment = [
          "COURIER_PORT=${toString cfg.port}"
          "COURIER_THEME=${themeFile}"
        ] ++ (if cfg.alerts.enable then [
          "COURIER_NOTIFY_SEND=${pkgs.libnotify}/bin/notify-send"
          "COURIER_WL_COPY=${pkgs.wl-clipboard}/bin/wl-copy"
          "COURIER_SHOW_WINDOW=${showWindow}"
        ] else [ "COURIER_ALERTS=off" ]);
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # One producer of message alerts: courier. tetherd's other popups stay on.
    hwc.home.apps.tether.settings.message_popups_enabled = !cfg.alerts.enable;

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = config.hwc.home.apps.tether.enable;
        message = "hwc.home.apps.courier needs hwc.home.apps.tether.enable (courier is a tetherd client).";
      }
      {
        assertion = config.hwc.home.apps.chromium.enable;
        message = "hwc.home.apps.courier opens its window with chromium-hwc (hwc.home.apps.chromium.enable).";
      }
    ];
  };
}
