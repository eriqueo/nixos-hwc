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
    radarr = [{
      id = 0;
      name = "Radarr";
      hostname = "10.89.0.1";
      port = 7878;
      apiKey = "fa7cc15c72b84c6e95089ff00194e164";
      useSsl = false;
      activeProfileId = 1;
      activeDirectory = "/movies";
      is4k = false;
      isDefault = true;
      externalUrl = "";
      syncEnabled = false;
      preventSearch = false;
    }];
    sonarr = [{
      id = 0;
      name = "Sonarr";
      hostname = "10.89.0.1";
      port = 8989;
      apiKey = "04014337c5874988a4ffd840237007f3";
      useSsl = false;
      activeProfileId = 1;
      activeDirectory = "/tv";
      activeAnimeProfileId = 1;
      activeAnimeDirectory = "/tv";
      is4k = false;
      isDefault = true;
      enableSeasonFolders = true;
      externalUrl = "";
      syncEnabled = false;
      preventSearch = false;
    }];
  };
in
{
  inherit settingsJson;
  settingsFile = pkgs.writeText "jellyseerr-settings.json" settingsJson;
}
