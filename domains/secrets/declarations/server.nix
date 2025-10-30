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

    # SLSKD API key for Soularr integration
    slskd-api-key = {
      file = ../parts/server/slskd-api-key.age;
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


    # AI/LLM API keys
    gemini-api-key = {
      file = ../parts/server/gemini_api_key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
  };
}