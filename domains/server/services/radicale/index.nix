# domains/server/services/radicale/index.nix
#
# Radicale — self-hosted CalDAV server (tasks + calendars).
#
# NAMESPACE: hwc.server.services.radicale.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.server.services.radicale.enable = true;   (machines/home/config.nix)
#
# Purpose: full two-way task sync with collection creation. iCloud pins the
# tasks pair to fixed collection IDs (lists can only be created on the phone);
# Radicale allows MKCALENDAR, so vdirsyncer's "from a"/"from b" discovery
# creates lists made in todui on the server, and the iPhone reads them via a
# native CalDAV account (Reminders + Calendar both support CalDAV).
#
# Auth: none. The vhost is reachable only from the tailnet, which is Eric's
# alone (decided 2026-10-15). Radicale accepts any password and takes the
# principal from the Basic-auth username, so clients that send eric or
# eric-personal keep their own collections. The vhost supplies "eric" when a
# request carries no credentials, so the web UI at /.web/ logs itself in.
# Clients still read their password from radicale-htpasswd; the server no
# longer does.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.services.radicale;

  # Tolerant secret path: generated.nix mounts the .age once it exists; the
  # fallback keeps eval working before the secret is provisioned. Only the
  # mirrors read it now (their Basic-auth password).
  htpasswdPath = lib.attrByPath
    [ "age" "secrets" "radicale-htpasswd" "path" ]
    "/run/agenix/radicale-htpasswd"
    config;

  # Read-only mirrors of outside calendars (iCal feeds) into Radicale: the
  # radicale-mirror timer. Options for it (mirrors.*) are declared below.
  mirrorsConfig = import ./parts/mirrors.nix { inherit config lib pkgs cfg htpasswdPath; };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.services.radicale = {
    enable = lib.mkEnableOption "Radicale CalDAV server (self-hosted tasks/calendars)";

    mirrors = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          secret = lib.mkOption {
            type = lib.types.str;
            description = "agenix secret name holding the calendar's secret iCal address (one URL).";
          };
          displayName = lib.mkOption {
            type = lib.types.str;
            description = "Calendar name shown on the phone and in khal.";
          };
          color = lib.mkOption {
            type = lib.types.str;
            default = "#8E8E93";
            description = "Calendar colour (#RRGGBB), set once when the collection is created.";
          };
        };
      });
      default = import ./parts/mirror-catalog.nix;
      defaultText = lib.literalExpression "import ./parts/mirror-catalog.nix";
      description = ''
        Outside calendars mirrored read-only into Radicale every mirrorInterval
        (parts/mirrors.nix), keyed by the collection id created under
        /<mirrorUser>/. Defaults to parts/mirror-catalog.nix, the one list:
        hwc.mail.calendar.radicale.extraCollections defaults to its ids on
        every khal machine. Edit the catalog, not this option.
      '';
    };

    mirrorUser = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Radicale principal the mirrors are created under (needs a line in the htpasswd secret).";
    };

    mirrorInterval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "How often the mirrors are refreshed (systemd OnUnitActiveSec).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5232;
      description = "Localhost port Radicale binds (fronted by Caddy).";
    };

    reverseProxy.enable = lib.mkEnableOption
      "Caddy vhost route (tasks.hwc.iheartwoodcraft.com → Radicale)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [ mirrorsConfig (lib.mkIf cfg.enable {
    services.radicale = {
      enable = true;
      settings = {
        server.hosts = [ "127.0.0.1:${toString cfg.port}" ];
        auth.type = "none";
        # storage stays at the upstream default (/var/lib/radicale/collections,
        # via StateDirectory) — covered by the system borg backup of /var/lib.
      };
    };

    # tasks.hwc.iheartwoodcraft.com → Radicale (vhost, same shape as jellyfin).
    # A request with no credentials is treated as eric ("eric:" in base64).
    hwc.networking.shared.routes = lib.mkIf cfg.reverseProxy.enable [
      {
        name = "tasks";
        mode = "vhost";
        upstream = "http://127.0.0.1:${toString cfg.port}";
        headersIfAbsent.Authorization = "Basic ZXJpYzo=";
      }
    ];
  }) ];
}
