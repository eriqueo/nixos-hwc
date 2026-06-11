# domains/server/services/radicale/index.nix
#
# Radicale — self-hosted CalDAV server (tasks + calendars).
#
# NAMESPACE: hwc.server.services.radicale.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.server.services.radicale.enable = true;   (machines/server/config.nix)
#
# Purpose: full two-way task sync with collection creation. iCloud pins the
# tasks pair to fixed collection IDs (lists can only be created on the phone);
# Radicale allows MKCALENDAR, so vdirsyncer's "from a"/"from b" discovery
# creates lists made in tasq on the server, and the iPhone reads them via a
# native CalDAV account (Reminders + Calendar both support CalDAV).
#
# Auth: htpasswd file from agenix (radicale-htpasswd.age under
# domains/secrets/parts/services/, format "user:password", plain encryption —
# the file is age-encrypted at rest and mounted 0440 root:secrets).

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.services.radicale;

  # Tolerant secret path: generated.nix mounts the .age once it exists; the
  # fallback keeps eval working before the secret is provisioned (the service
  # then fails at runtime with a clear "no such file" instead of breaking eval).
  htpasswdPath = lib.attrByPath
    [ "age" "secrets" "radicale-htpasswd" "path" ]
    "/run/agenix/radicale-htpasswd"
    config;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.services.radicale = {
    enable = lib.mkEnableOption "Radicale CalDAV server (self-hosted tasks/calendars)";

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
  config = lib.mkIf cfg.enable {
    services.radicale = {
      enable = true;
      settings = {
        server.hosts = [ "127.0.0.1:${toString cfg.port}" ];
        auth = {
          type = "htpasswd";
          htpasswd_filename = htpasswdPath;
          htpasswd_encryption = "plain";
        };
        # storage stays at the upstream default (/var/lib/radicale/collections,
        # via StateDirectory) — covered by the system borg backup of /var/lib.
      };
    };

    # Read the agenix-mounted htpasswd (0440 root:secrets).
    systemd.services.radicale.serviceConfig.SupplementaryGroups = [ "secrets" ];

    # tasks.hwc.iheartwoodcraft.com → Radicale (vhost, same shape as jellyfin).
    hwc.networking.shared.routes = lib.mkIf cfg.reverseProxy.enable [
      {
        name = "tasks";
        mode = "vhost";
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];
  };
}
