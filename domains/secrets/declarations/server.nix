# domains/secrets/declarations/server.nix
#
# Server domain secrets - Application and service credentials
# Data-only module that declares age.secrets entries for server services
{ config, lib, ... }:
{
  # Server domain secrets - application credentials
  age.secrets = {
    # ARR stack API keys
    radarr-api-key = {
      file = ../parts/server/radarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    sonarr-api-key = {
      file = ../parts/server/sonarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    lidarr-api-key = {
      file = ../parts/server/lidarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    prowlarr-api-key = {
      file = ../parts/server/prowlarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Indexer API keys
    ninjacentral-api-key = {
      file = ../parts/server/ninjacentral-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # SLSKD credentials
    slskd-api-key = {
      file = ../parts/server/slskd-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-web-username = {
      file = ../parts/server/slskd-web-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-web-password = {
      file = ../parts/server/slskd-web-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-soulseek-username = {
      file = ../parts/server/slskd-soulseek-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-soulseek-password = {
      file = ../parts/server/slskd-soulseek-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # CouchDB admin credentials
    couchdb-admin-username = {
      file = ../parts/server/couchdb-admin-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    couchdb-admin-password = {
      file = ../parts/server/couchdb-admin-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Notification service credentials
    ntfy-user = {
      file = ../parts/server/ntfy-user.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slack-webhook-url = {
      file = ../parts/server/slack-webhook-url.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    # AI/LLM API keys
    gemini-api-key = {
      file = ../parts/server/gemini_api_key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Navidrome music server credentials
    navidrome-admin-password = {
      file = ../parts/server/navidrome-admin-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Monitoring services credentials
    grafana-admin-password = {
      file = ../parts/server/grafana-admin-password.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };
    jellyfin-api-key = {
      file = ../parts/server/jellyfin-api-key.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    # Jellyfin user passwords
    jellyfin-admin-password = {
      file = ../parts/server/jellyfin/admin-password.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    jellyfin-eric-password = {
      file = ../parts/server/jellyfin/eric-password.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    # Frigate secrets are in domains/secrets/declarations/infrastructure.nix
    # (camera/surveillance secrets belong to infrastructure domain)

    # YouTube services credentials
    youtube-transcripts-db-url = {
      file = ../parts/server/youtube-db-url.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    youtube-videos-db-url = {
      file = ../parts/server/youtube-videos-db-url.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    youtube-api-key = {
      file = ../parts/server/youtube-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # WebDAV server credentials (for RetroArch sync)
    webdav-username = {
      file = ../parts/server/webdav-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    webdav-password = {
      file = ../parts/server/webdav-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
  };
}

