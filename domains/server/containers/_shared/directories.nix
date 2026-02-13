# Shared directory setup for container services (declarative tmpfiles)
{ lib, config, ... }:
let
  paths = config.hwc.paths;
  appsRoot = paths.apps.root;
  hotRoot = paths.hot.root;
  downloadsRoot = paths.hot.downloads;
  mediaRoot = paths.media.root;

  containerEnabled = name:
    lib.attrByPath [ "hwc" "server" "containers" name "enable" ] false config;

  mkDir = path: "d ${path} 0755 1000 100 -";
  mkRootDir = path: "d ${path} 0755 root root -";

  appRoot = name: "${appsRoot}/${name}";
  appConfig = name: "${(appRoot name)}/config";

  mkConfigDirs = names:
    lib.concatMap (name: lib.optionals (containerEnabled name) [ (mkDir (appConfig name)) ]) names;
in
{
  config = {
    systemd.tmpfiles.rules = lib.flatten [
      # Shared downloads structure (hot storage)
      (lib.optionals (downloadsRoot != null) [
        (mkDir downloadsRoot)
        (mkDir "${downloadsRoot}/incomplete")
        (mkDir "${downloadsRoot}/complete")
        (mkDir "${downloadsRoot}/tv")
        (mkDir "${downloadsRoot}/movies")
        (mkDir "${downloadsRoot}/music")
        (mkDir "${downloadsRoot}/scripts")
      ])

      # Event spool + processing areas
      (lib.optionals (hotRoot != null) [
        (mkDir "${hotRoot}/events")
        (mkDir "${hotRoot}/processing")
        (mkDir "${hotRoot}/processing/sonarr-temp")
        (mkDir "${hotRoot}/processing/radarr-temp")
        (mkDir "${hotRoot}/processing/lidarr-temp")
        (mkDir "${hotRoot}/processing/tdarr-temp")
        (mkDir "${hotRoot}/processing/tdarr-backups")
      ])

      # Books library structure
      (lib.optionals (mediaRoot != null) [
        (mkDir "${mediaRoot}/books/ebooks")
        (mkDir "${mediaRoot}/books/audiobooks")
      ])

      # Container config roots (/opt)
      (lib.optionals (appsRoot != null) ([ (mkRootDir appsRoot) ] ++ mkConfigDirs [
        "beets"
        "books"
        "caddy"
        "jellyfin"
        "lidarr"
        "navidrome"
        "organizr"
        "prowlarr"
        "qbittorrent"
        "radarr"
        "recyclarr"
        "sabnzbd"
        "sonarr"
        "soularr"
      ]))

      # Containers with non-standard config layouts
      (lib.optionals (appsRoot != null && containerEnabled "gluetun") [
        (mkDir (appRoot "gluetun"))
      ])
      (lib.optionals (appsRoot != null && containerEnabled "soularr") [
        (mkDir "${(appRoot "soularr")}/data")
      ])
      (lib.optionals (appsRoot != null && containerEnabled "tdarr") [
        (mkDir "${(appRoot "tdarr")}/server")
        (mkDir "${(appRoot "tdarr")}/configs")
        (mkDir "${(appRoot "tdarr")}/logs")
      ])
      (lib.optionals (appsRoot != null && containerEnabled "recyclarr") [
        (mkDir "${(appRoot "recyclarr")}/cache")
      ])

      # System-level config dirs
      (lib.optionals (containerEnabled "slskd") [
        (mkRootDir "/etc/slskd")
        (mkRootDir "/var/lib/slskd")
      ])
    ];
  };
}
