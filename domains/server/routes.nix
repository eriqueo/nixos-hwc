{ lib, config, ... }:
{
  hwc.services.shared.routes = [
    # Jellyfin
    {
      name = "jellyfin";
      mode = "subpath";
      path = "/jellyfin";
      upstream = "http://127.0.0.1:8096";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/jellyfin"; };
    }

    # Jellyseerr
    {
      name = "jellyseerr";
      mode = "subpath";
      path = "/jellyseerr";
      upstream = "http://127.0.0.1:5055";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/jellyseerr"; };
    }

    # Navidrome
    {
      name = "navidrome";
      mode = "subpath";
      path = "/music";
      upstream = "http://127.0.0.1:4533";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/music"; };
    }

    # Immich (port mode - access via https://hwc.ocelot-wahoo.ts.net:7443)
    {
      name = "immich";
      mode = "port";
      port = 7443;
      upstream = "http://127.0.0.1:2283";
    }

    # Frigate (port mode - access via https://hwc.ocelot-wahoo.ts.net:5443)
    {
      name = "frigate";
      mode = "port";
      port = 5443;
      upstream = "http://127.0.0.1:5000";
    }

    # Sabnzbd
    {
      name = "sabnzbd";
      mode = "subpath";
      path = "/sab";
      upstream = "http://127.0.0.1:8081";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/sab"; };
    }

    # qBittorrent
    {
      name = "qbittorrent";
      mode = "subpath";
      path = "/qbt";
      upstream = "http://127.0.0.1:8080";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/qbt"; };
    }

    # slskd
    {
      name = "slskd";
      mode = "port";
      port = 8443;
      upstream = "http://127.0.0.1:5030";
    }

    # Sonarr
    {
      name = "sonarr";
      mode = "subpath";
      path = "/sonarr";
      upstream = "http://127.0.0.1:8989";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/sonarr"; };
    }

    # Radarr
    {
      name = "radarr";
      mode = "subpath";
      path = "/radarr";
      upstream = "http://127.0.0.1:7878";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/radarr"; };
    }

    # Lidarr
    {
      name = "lidarr";
      mode = "subpath";
      path = "/lidarr";
      upstream = "http://127.0.0.1:8686";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/lidarr"; };
    }

    # Prowlarr
    {
      name = "prowlarr";
      mode = "subpath";
      path = "/prowlarr";
      upstream = "http://127.0.0.1:9696";
      stripPrefix = true;
      assetStrategy = "rewrite";
      headers = { "X-Forwarded-Prefix" = "/prowlarr"; };
    }

    # CouchDB (Obsidian LiveSync)
    {
      name = "couchdb";
      mode = "subpath";
      path = "/sync";
      upstream = "http://127.0.0.1:5984";
      stripPrefix = true;
      headers = { "X-Forwarded-Prefix" = "/sync"; };
    }
  ];
}