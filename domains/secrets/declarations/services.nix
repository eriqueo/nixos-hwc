# domains/secrets/declarations/services.nix
#
# Service secrets - Application and service credentials
# Data-only module that declares age.secrets entries for server services
{ config, lib, ... }:
{
  # Server domain secrets - application credentials
  age.secrets = {
    # ARR stack API keys
    radarr-api-key = {
      file = ../parts/services/radarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    sonarr-api-key = {
      file = ../parts/services/sonarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    lidarr-api-key = {
      file = ../parts/services/lidarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    prowlarr-api-key = {
      file = ../parts/services/prowlarr-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Indexer API keys
    ninjacentral-api-key = {
      file = ../parts/services/ninjacentral-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # SLSKD credentials
    slskd-api-key = {
      file = ../parts/services/slskd-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-web-username = {
      file = ../parts/services/slskd-web-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-web-password = {
      file = ../parts/services/slskd-web-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-soulseek-username = {
      file = ../parts/services/slskd-soulseek-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slskd-soulseek-password = {
      file = ../parts/services/slskd-soulseek-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # CouchDB admin credentials
    couchdb-admin-username = {
      file = ../parts/services/couchdb-admin-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    couchdb-admin-password = {
      file = ../parts/services/couchdb-admin-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Notification service credentials
    ntfy-user = {
      file = ../parts/services/ntfy-user.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    slack-webhook-url = {
      file = ../parts/services/slack-webhook-url.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    # AI/LLM API keys
    gemini-api-key = {
      file = ../parts/services/gemini_api_key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Navidrome music server credentials
    navidrome-admin-password = {
      file = ../parts/services/navidrome-admin-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Monitoring services credentials
    grafana-admin-password = {
      file = ../parts/services/grafana-admin-password.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };
    jellyfin-api-key = {
      file = ../parts/services/jellyfin-api-key.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    # Jellyfin user passwords
    jellyfin-admin-password = {
      file = ../parts/services/jellyfin/admin-password.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    jellyfin-eric-password = {
      file = ../parts/services/jellyfin/eric-password.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    # Frigate secrets are in domains/secrets/declarations/infrastructure.nix
    # (camera/surveillance secrets belong to infrastructure domain)

    # YouTube services credentials
    youtube-transcripts-db-url = {
      file = ../parts/services/youtube-db-url.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    youtube-videos-db-url = {
      file = ../parts/services/youtube-videos-db-url.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    youtube-api-key = {
      file = ../parts/services/youtube-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # WebDAV server credentials (for RetroArch sync)
    webdav-username = {
      file = ../parts/services/webdav-username.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    webdav-password = {
      file = ../parts/services/webdav-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Audiobookshelf API key (for audiobook copier library scans)
    audiobookshelf-api-key = {
      file = ../parts/services/audiobookshelf-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Firefly III app key (Laravel encryption key)
    firefly-app-key = {
      file = ../parts/services/firefly-app-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # Paperless-NGX secrets
    paperless-secret-key = {
      file = ../parts/services/paperless-secret-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    paperless-admin-password = {
      file = ../parts/services/paperless-admin-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    # n8n workflow automation credentials
    n8n-owner-password-hash = {
      file = ../parts/services/n8n-owner-password-hash.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };

    # Slack integration secrets
    slack-signing-secret = {
      file = ../parts/services/slack-signing-secret.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };
  };
}
