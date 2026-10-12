# domains/server/services/wall-calendar/index.nix
#
# Wall calendar — one week of calendar events and the NOAA forecast for the
# wall tablet, drawn e-ink style (black on white, no colour, no motion).
#
# NAMESPACE: hwc.server.services.wallCalendar.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.server.services.wallCalendar.enable = true;   (machines/work/config.nix)
#
# Reads the local Radicale over CalDAV and asks it for every collection that
# holds events on each refresh, so a new calendar shows up with no config
# change. Weather is api.weather.gov (forecast + active alerts for one point).
# The page lives in parts/server.py; nothing is stored on disk.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.services.wallCalendar;
  radicale = config.hwc.server.services.radicale;

  # Same tolerant lookup as the radicale module: the shared htpasswd secret.
  htpasswdPath = lib.attrByPath
    [ "age" "secrets" "radicale-htpasswd" "path" ]
    "/run/agenix/radicale-htpasswd"
    config;

  python = pkgs.python3.withPackages (p: [ p.icalendar ]);
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.services.wallCalendar = {
    enable = lib.mkEnableOption "wall tablet page: one-week Radicale calendar + NOAA forecast";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8424;
      description = "Localhost port the page binds (fronted by Caddy).";
    };

    calendarUser = lib.mkOption {
      type = lib.types.str;
      default = radicale.mirrorUser;
      description = "Radicale principal whose event calendars are shown (needs a line in the htpasswd secret).";
    };

    noaaPoint = lib.mkOption {
      type = lib.types.str;
      default = "45.6770,-111.0429";
      description = "\"lat,lon\" for the api.weather.gov forecast and alerts (default: Bozeman).";
    };

    place = lib.mkOption {
      type = lib.types.str;
      default = "Bozeman";
      description = "Place name shown before the current conditions.";
    };

    reverseProxy.enable = lib.mkEnableOption
      "Caddy vhost route (wall.hwc.iheartwoodcraft.com → this page)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.wall-calendar = {
      description = "Wall calendar page (Radicale week + NOAA forecast)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "radicale.service" ];
      wants = [ "network-online.target" ];
      environment = {
        WALL_PORT = toString cfg.port;
        WALL_RADICALE_URL = "http://127.0.0.1:${toString radicale.port}";
        WALL_RADICALE_USER = cfg.calendarUser;
        WALL_HTPASSWD_FILE = htpasswdPath;
        WALL_NOAA_POINT = cfg.noaaPoint;
        WALL_PLACE = cfg.place;
        WALL_TZ = config.time.timeZone;
        # api.weather.gov asks every client to identify itself.
        WALL_USER_AGENT = "hwc-wall-calendar (https://iheartwoodcraft.com)";
      };
      serviceConfig = {
        ExecStart = "${python}/bin/python3 ${./parts/server.py}";
        User = lib.mkForce "eric";
        Group = "users";
        # Read the agenix-mounted htpasswd (0440 root:secrets).
        SupplementaryGroups = [ "secrets" ];
        Restart = "on-failure";
        RestartSec = 10;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    hwc.networking.shared.routes = lib.mkIf cfg.reverseProxy.enable [
      {
        name = "wall";
        mode = "vhost";
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = radicale.enable;
        message = "hwc.server.services.wallCalendar reads the local Radicale; enable hwc.server.services.radicale on this host.";
      }
      {
        assertion = config.time.timeZone != null;
        message = "hwc.server.services.wallCalendar needs time.timeZone set to place events on local days.";
      }
    ];
  };
}
