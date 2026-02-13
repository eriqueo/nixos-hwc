{ config, pkgs, ... }:
let
  defaultPermissions = 222;
  settingsJson = builtins.toJSON {
    main = {
      initialized = true;
      trustProxy = true;
      applicationUrl = "https://hwc.ocelot-wahoo.ts.net:5543";
      mediaServerType = 2;
      mediaServerLogin = true;
      localLogin = false;
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
      serverId = "016e351828c841fb83af163a59198649";
      apiKey = "26d513d02f27467aa94d70e4b43688f8";
    };
  };
in
{
  inherit settingsJson;
  settingsFile = pkgs.writeText "jellyseerr-settings.json" settingsJson;
}
