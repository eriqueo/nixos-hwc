# modules/security/secrets/services.nix
#
# Services domain secrets - Application and service credentials
# Data-only module that declares age.secrets entries for service authentication
{ config, lib, ... }:
{
  # Services domain secrets - application credentials
  age.secrets = {
    # ARR stack API keys
    radarr-api-key = {
      file = ../../../secrets/radarr-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    sonarr-api-key = {
      file = ../../../secrets/sonarr-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    lidarr-api-key = {
      file = ../../../secrets/lidarr-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    prowlarr-api-key = {
      file = ../../../secrets/prowlarr-api-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # CouchDB admin credentials
    couchdb-admin-username = {
      file = ../../../secrets/couchdb-admin-username.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    couchdb-admin-password = {
      file = ../../../secrets/couchdb-admin-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # Notification service credentials
    ntfy-user = {
      file = ../../../secrets/ntfy-user.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # Email service credentials
    proton-bridge-password = {
      file = ../../../secrets/proton-bridge-password.age;
      mode = "0440";
      owner = "eric";
      group = "users";
    };
    
    gmail-personal-password = {
      file = ../../../secrets/gmail-personal-password.age;
      mode = "0440";
      owner = "eric";
      group = "users";
    };
    
    gmail-business-password = {
      file = ../../../secrets/gmail-business-password.age;
      mode = "0440";
      owner = "eric";
      group = "users";
    };
  };
}