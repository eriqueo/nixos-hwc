# domains/home/apps/courier/index.nix
# courier — our iPhone messages app, a client of tetherd (apps/tether). The app
# (github:eriqueo/courier) owns behaviour, protocol handling and tests; this
# module supplies the palette, runs the service and wires the desktop.
#
# The window is Chromium in app mode at http://courier.localhost:<port>.
# Chromium ignores --class on Wayland and derives the app_id from the host, so
# Hyprland matches `chrome-courier.localhost__-Default` (measured 2026-10-12).
# The hotkey and window rule for that class live in hyprland/parts/behavior.nix.
#
# Tailnet access (tailnet.enable): Eric's other devices pair with courier at
# https://<host>:<tailnet.port> through `tailscale serve`; courier still binds
# loopback only. The app enforces the login, Origin and device checks.

{ config, lib, pkgs, inputs, osConfig ? { }, specialArgs, ... }:

let
  cfg = config.hwc.home.apps.courier;
  courierTailnetHost = specialArgs.courierTailnetHost or null;
  app = inputs.courier.packages.${pkgs.stdenv.hostPlatform.system}.default;
  colors = config.hwc.home.theme.colors;
  hmLib = import ../../../lib/hm.nix { inherit lib; };
  hostName = lib.attrByPath [ "networking" "hostName" ] null osConfig;

  # The CLI that matches the running tailscaled (a user unit may drive serve
  # because hwc-laptop sets --operator=eric).
  tailscale = "/run/current-system/sw/bin/tailscale";
  serveArgs = "serve --https=${toString cfg.tailnet.port}";

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

    tailnet = {
      enable = lib.mkEnableOption ''
        courier on Eric's other tailnet devices, through `tailscale serve`
        (tailnet only, never Funnel). A device pairs with a 6-digit code the
        laptop window shows. Needs tailscaled's --operator set to this user'';

      port = lib.mkOption {
        type = lib.types.port;
        default = 8445;
        description = "HTTPS port `tailscale serve` answers on (8444 is taken on hwc-laptop).";
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        # Standalone hms has no osConfig. The flake passes the system-owned
        # name to both lanes, just as it passes the Tether package.
        default = if courierTailnetHost != null then courierTailnetHost
          else if hostName == null then null
          else "${hostName}.${(hmLib.fleet osConfig).tailnetSuffix}";
        defaultText = lib.literalExpression ''"<networking.hostName>.<hwc.networking.hosts.tailnetSuffix>"'';
        description = "MagicDNS name devices use to reach this machine.";
      };

      login = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "someone@github";
        description = ''
          The one Tailscale login allowed in (serve's Tailscale-User-Login).
          Tagged nodes send no login, so servers cannot use courier.
        '';
      };
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
        ] else [ "COURIER_ALERTS=off" ])
        ++ lib.optionals cfg.tailnet.enable [
          # toString: a missing value reaches the assertion below, not a coercion error.
          "COURIER_TAILNET_HOST=${toString cfg.tailnet.host}:${toString cfg.tailnet.port}"
          "COURIER_TAILNET_LOGIN=${toString cfg.tailnet.login}"
        ];
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Points tailnet port → courier's loopback port. serve keeps its config in
    # tailscaled across reboots; stopping this unit (logout, or tailnet.enable
    # turned off) removes it. While courier is down, devices get 502 and the
    # page shows the laptop as unreachable.
    systemd.user.services.courier-tailnet = lib.mkIf cfg.tailnet.enable {
      Unit = {
        Description = "courier on the tailnet (tailscale serve :${toString cfg.tailnet.port})";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${tailscale} ${serveArgs} --bg http://127.0.0.1:${toString cfg.port}";
        ExecStop = "-${tailscale} ${serveArgs} off";
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
      {
        assertion = !cfg.tailnet.enable || (cfg.tailnet.login != null && cfg.tailnet.host != null && (hmLib.isNixOSHost osConfig || courierTailnetHost != null));
        message = "hwc.home.apps.courier.tailnet needs a NixOS host (for its tailscale CLI), tailnet.login and tailnet.host.";
      }
    ];
  };
}
