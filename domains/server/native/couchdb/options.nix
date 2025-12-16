{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.couchdb = {
    enable = mkEnableOption "CouchDB database server for Obsidian LiveSync";

    settings = {
      port = mkOption {
        type = types.port;
        default = 5984;
        description = "Port for CouchDB server";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Bind address for CouchDB server (localhost only for security)";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/couchdb";
        description = "CouchDB data directory";
      };

      maxDocumentSize = mkOption {
        type = types.int;
        default = 50000000;
        description = "Maximum document size in bytes (50MB default for Obsidian attachments)";
      };

      maxHttpRequestSize = mkOption {
        type = types.int;
        default = 4294967296;
        description = "Maximum HTTP request size in bytes (4GB default)";
      };

      corsOrigins = mkOption {
        type = types.listOf types.str;
        default = [
          "app://obsidian.md"
          "capacitor://localhost"
          "http://localhost"
        ];
        description = "CORS allowed origins for Obsidian LiveSync";
      };
    };

    secrets = {
      adminUsername = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to admin username secret (defaults to hwc.secrets.api.couchdbAdminUsernameFile)";
      };

      adminPassword = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to admin password secret (defaults to hwc.secrets.api.couchdbAdminPasswordFile)";
      };
    };

    monitoring = {
      enableHealthCheck = mkEnableOption "Enable CouchDB health monitoring service" // { default = true; };

      healthCheckTimeout = mkOption {
        type = types.int;
        default = 60;
        description = "Health check timeout in seconds";
      };
    };

    reverseProxy = {
      enable = mkEnableOption "Enable reverse proxy route for CouchDB";

      path = mkOption {
        type = types.str;
        default = "/couchdb";
        description = "Reverse proxy path";
      };
    };
  };
}
