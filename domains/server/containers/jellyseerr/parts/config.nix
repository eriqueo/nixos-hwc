{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.jellyseerr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/jellyseerr/config";

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
      ip = "192.168.0.97";
      port = 8096;
      useSsl = false;
      urlBase = "";
      externalHostname = "";
      serverId = "016e351828c841fb83af163a59198649";
      apiKey = "26d513d02f27467aa94d70e4b43688f8";
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    # Create settings.json in the container's config directory
    systemd.tmpfiles.rules = [
      "d ${configPath} 0755 1000 100 -"
      # Use C+ to copy file content (not path string)
      "Z ${configPath}/settings.json 0644 1000 100 - ${pkgs.writeText "jellyseerr-settings.json" settingsJson}"
    ];

    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-jellyseerr".wants = [ "network-online.target" ];
  };
}
