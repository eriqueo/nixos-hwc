{ lib, config, ... }:
{
  hwc.services.shared.routes = [
    # Jellyfin - strip path (app expects root despite URL_BASE)
  #  {
   #   name = "jellyfin";
   #   mode = "subpath";
   #   path = "/jellyfin";
   #   upstream = "http://127.0.0.1:8096";
   #   needsUrlBase = false;
   #   headers = { "X-Forwarded-Prefix" = "/jellyfin"; };
   # }

    # Jellyseerr - port mode (doesn't work well with subpaths)
    {
      name = "jellyseerr";
      mode = "port";
      port = 5543;  # Dedicated port for Jellyseerr
      upstream = "http://127.0.0.1:5055";
    }

    # Jellyseerr - convenience subpath (strips prefix for client assets)
    {
      name = "jellyseerr-subpath";
      mode = "subpath";
      path = "/jellyseerr";
      upstream = "http://127.0.0.1:5055";
      needsUrlBase = false;
      headers = { "X-Forwarded-Prefix" = "/jellyseerr"; };
    }

    # Navidrome - preserve path (URL base set in app)
    {
      name = "navidrome";
      mode = "subpath";
      path = "/music";
      upstream = "http://127.0.0.1:4533";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/music"; };
    }

    # Immich - port mode (subpath-hostile)
    {
      name = "immich";
      mode = "port";
      port = 7443;
      upstream = "http://127.0.0.1:2283";
    }

    # Frigate - port mode (subpath-hostile, GPU-accelerated with TensorRT)
    {
      name = "frigate";
      mode = "port";
      port = 5443;
      upstream = "http://127.0.0.1:5001";  # GPU-accelerated with CUDA/TensorRT support
    }

    # Sabnzbd - preserve path (URL base set in app)
    {
      name = "sabnzbd";
      mode = "subpath";
      path = "/sab";
      upstream = "http://127.0.0.1:8081";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/sab"; };
    }

    # qBittorrent - strip path (app expects root despite URL_BASE)
    {
      name = "qbittorrent";
      mode = "subpath";
      path = "/qbt";
      upstream = "http://127.0.0.1:8080";
      needsUrlBase = false;
      headers = { "X-Forwarded-Prefix" = "/qbt"; };
    }

    # slskd - port mode with corrected upstream
    {
      name = "slskd";
      mode = "port";
      port = 8443;
      upstream = "http://127.0.0.1:5031";
    }

    # Sonarr - preserve path (URL base set in app)
    {
      name = "sonarr";
      mode = "subpath";
      path = "/sonarr";
      upstream = "http://127.0.0.1:8989";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/sonarr"; };
    }

    # Radarr - preserve path (URL base set in app)
    {
      name = "radarr";
      mode = "subpath";
      path = "/radarr";
      upstream = "http://127.0.0.1:7878";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/radarr"; };
    }

    # Lidarr - preserve path (URL base set in app)
    {
      name = "lidarr";
      mode = "subpath";
      path = "/lidarr";
      upstream = "http://127.0.0.1:8686";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/lidarr"; };
    }

    # Prowlarr - preserve path (URL base set in app)
    {
      name = "prowlarr";
      mode = "subpath";
      path = "/prowlarr";
      upstream = "http://127.0.0.1:9696";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/prowlarr"; };
    }

    # LazyLibrarian (books) - port mode (subpath-hostile with query parameters)
    {
      name = "books";
      mode = "port";
      port = 8299;
      upstream = "http://127.0.0.1:5299";
    }

    # CouchDB (Obsidian LiveSync) - strip /sync prefix
    {
      name = "couchdb";
      mode = "subpath";
      path = "/sync";
      upstream = "http://127.0.0.1:5984";
      needsUrlBase = false;  # Strip /sync prefix - CouchDB doesn't support URL base
    }

    # ntfy notification server - preserve path (ntfy handles subpath natively)
    {
      name = "ntfy";
      mode = "subpath";
      path = "/notify";
      upstream = "http://127.0.0.1:2586";
      needsUrlBase = false;  # ntfy works with subpath without URL base
    }

    # Tdarr - port mode (WebSocket intensive, subpath issues)
    {
      name = "tdarr";
      mode = "port";
      port = 8267;  # Use 8267 externally, forward to internal 8265
      upstream = "http://127.0.0.1:8265";
    }

    # Organizr - Root dashboard on dedicated port
    {
      name = "organizr";
      mode = "port";
      port = 9443;  # Dedicated port for Organizr dashboard
      upstream = "http://127.0.0.1:9983";
    }

    # Transcript API - preserve path (FastAPI routes expect /api prefix)
    {
      name = "transcript-api";
      mode = "subpath";
      path = "/api";
      upstream = "http://127.0.0.1:8099";
      needsUrlBase = true;  # Preserve /api prefix - app routes expect it
      headers = { "X-Forwarded-Prefix" = "/api"; };
    }
  ];
}
