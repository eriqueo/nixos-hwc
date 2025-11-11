{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.jellyseerr;
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."jellyseerr/settings.json".text = builtins.toJSON {
      main = {
        initialized = true;
        trustProxy = true;
        applicationUrl = "https://hwc.ocelot-wahoo.ts.net/jellyseerr";
        mediaServerType = 4;
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

    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-jellyseerr".wants = [ "network-online.target" ];
  };
}
