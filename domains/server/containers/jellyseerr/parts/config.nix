{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.jellyseerr;

  # Jellyseerr permission flags (bitmask)
  # REQUEST = 2, AUTO_APPROVE = 4, REQUEST_MOVIE = 8, AUTO_APPROVE_MOVIE = 16,
  # REQUEST_4K = 32, REQUEST_TV = 64, AUTO_APPROVE_TV = 128, REQUEST_4K_TV = 256
  # For auto-approval: REQUEST (2) + AUTO_APPROVE (4) + REQUEST_MOVIE (8) + AUTO_APPROVE_MOVIE (16) + REQUEST_TV (64) + AUTO_APPROVE_TV (128) = 222
  defaultPermissions = 222; # Auto-approve all movie and TV requests

  settingsJson = builtins.toJSON {
    main = {
      initialized = true;
      trustProxy = true;
      applicationUrl = "https://hwc.ocelot-wahoo.ts.net:5543";
      mediaServerType = 4;
      inherit defaultPermissions;
    };
    public = {
      initialized = true;
      localLogin = false;
      mediaServerLogin = true;
    };
    auth = {
      local = { enabled = false; };
      jellyfin = { enabled = true; };
    };
    jellyfin = {
      ip = "10.89.0.1";
      port = 8096;
      useSsl = false;
      urlBase = "";
      externalHostname = "";
      serverId = "a2cf771ab06740d9b85ec285a0a96de4";
      apiKey = "cc0974fe24464c208bdd4b2570a01541";
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    # Create settings.json in the container's config directory
    systemd.tmpfiles.rules = [
      "d /opt/jellyseerr/config 0755 1000 1000 -"
      "f /opt/jellyseerr/config/settings.json 0644 1000 1000 - ${pkgs.writeText "jellyseerr-settings.json" settingsJson}"
    ];

    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-jellyseerr".wants = [ "network-online.target" ];
  };
}
