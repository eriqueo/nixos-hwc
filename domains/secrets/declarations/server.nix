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
      mode = "0400";
      owner = "root";
      group = "root";
    };

    sonarr-api-key = {
      file = ../parts/server/sonarr-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    lidarr-api-key = {
      file = ../parts/server/lidarr-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    prowlarr-api-key = {
      file = ../parts/server/prowlarr-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # SLSKD API key for Soularr integration
    slskd-api-key = {
      file = ../parts/server/slskd-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # CouchDB admin credentials
    couchdb-admin-username = {
      file = ../parts/server/couchdb-admin-username.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    couchdb-admin-password = {
      file = ../parts/server/couchdb-admin-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # Notification service credentials
    ntfy-user = {
      file = ../parts/server/ntfy-user.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };


    # AI/LLM API keys
    gemini-api-key = {
      file = ../parts/server/gemini_api_key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # Frigate NVR camera credentials
    frigate-rtsp-username = {
      file = ../parts/server/frigate-rtsp-username.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    frigate-rtsp-password = {
      file = ../parts/server/frigate-rtsp-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    frigate-camera-ips = {
      file = ../parts/server/frigate-camera-ips.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
  };
}