{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.data.couchdb;
  generateConfig = import ./config-generator.nix;

  # Use secrets API with fallback
  adminUsernamePath =
    if cfg.secrets.adminUsername != null
    then cfg.secrets.adminUsername
    else config.hwc.secrets.api."couchdb-admin-username" or null;

  adminPasswordPath =
    if cfg.secrets.adminPassword != null
    then cfg.secrets.adminPassword
    else config.hwc.secrets.api."couchdb-admin-password" or null;
in
{
  # OPTIONS
  options.hwc.data.couchdb = {
    enable = lib.mkEnableOption "CouchDB database server for Obsidian LiveSync";

    settings = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 5984;
        description = "Port for CouchDB server";
      };

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Bind address for CouchDB server (localhost only for security)";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/couchdb";
        description = "CouchDB data directory";
      };

      maxDocumentSize = lib.mkOption {
        type = lib.types.int;
        default = 50000000;
        description = "Maximum document size in bytes (50MB default for Obsidian attachments)";
      };

      maxHttpRequestSize = lib.mkOption {
        type = lib.types.int;
        default = 4294967296;
        description = "Maximum HTTP request size in bytes (4GB default)";
      };

      corsOrigins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "app://obsidian.md"
          "capacitor://localhost"
          "http://localhost"
        ];
        description = "CORS allowed origins for Obsidian LiveSync";
      };
    };

    secrets = {
      adminUsername = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to admin username secret (defaults to hwc.secrets.api.\"couchdb-admin-username\")";
      };

      adminPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to admin password secret (defaults to hwc.secrets.api.\"couchdb-admin-password\")";
      };
    };

    monitoring = {
      enableHealthCheck = lib.mkEnableOption "Enable CouchDB health monitoring service" // { default = true; };

      healthCheckTimeout = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Health check timeout in seconds";
      };
    };

    reverseProxy = {
      enable = lib.mkEnableOption "Enable reverse proxy route for CouchDB";

      path = lib.mkOption {
        type = lib.types.str;
        default = "/couchdb";
        description = "Reverse proxy path";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Systemd service to setup CouchDB configuration BEFORE CouchDB starts
    # This injects secrets from agenix into local.ini
    systemd.services.couchdb-config-setup = {
      description = "Setup CouchDB admin configuration from agenix secrets";
      before = [ "couchdb.service" ];
      wantedBy = [ "couchdb.service" ];
      wants = [ "agenix.service" ];
      after = [ "agenix.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        # Ensure CouchDB config directory exists
        mkdir -p ${cfg.settings.dataDir}

        # Read credentials from agenix secrets
        ADMIN_USERNAME=$(cat ${adminUsernamePath})
        ADMIN_PASSWORD=$(cat ${adminPasswordPath})

        # Generate configuration with runtime variable substitution
        cat > ${cfg.settings.dataDir}/local.ini << EOF
[admins]
$ADMIN_USERNAME = $ADMIN_PASSWORD

[couchdb]
single_node=true
max_document_size = ${toString cfg.settings.maxDocumentSize}

[chttpd]
require_valid_user = true
max_http_request_size = ${toString cfg.settings.maxHttpRequestSize}

[chttpd_auth]
require_valid_user = true

[httpd]
WWW-Authenticate = Basic realm="couchdb"
enable_cors = true

[cors]
origins = ${builtins.concatStringsSep "," cfg.settings.corsOrigins}
credentials = true
headers = accept, authorization, content-type, origin, referer
methods = GET, PUT, POST, HEAD, DELETE
max_age = 3600
EOF

        # Set proper ownership and permissions (eric for simplified permissions)
        chown eric:users ${cfg.settings.dataDir}/local.ini
        chmod 600 ${cfg.settings.dataDir}/local.ini
      '';
    };

    # Native CouchDB service configuration
    services.couchdb = {
      enable = true;
      port = cfg.settings.port;
      bindAddress = cfg.settings.bindAddress;
      # Admin credentials handled via local.ini from systemd service above
    };

    # Run couchdb as eric user for simplified permissions
    systemd.services.couchdb = {
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
        # Override state directory to use hwc structure
        StateDirectory = lib.mkForce "hwc/couchdb";
        # Runtime directory for couchdb.uri file
        RuntimeDirectory = "couchdb";
      };
    };

    # Health monitoring service for Obsidian LiveSync
    systemd.services.couchdb-health-monitor = lib.mkIf cfg.monitoring.enableHealthCheck {
      description = "Monitor CouchDB health for Obsidian LiveSync";
      after = [ "couchdb.service" ];
      wants = [ "couchdb.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "couchdb-health-check" ''
          echo "Checking CouchDB health for Obsidian LiveSync..."
          TIMEOUT=${toString cfg.monitoring.healthCheckTimeout}
          ATTEMPTS=$((TIMEOUT / 2))

          for i in $(seq 1 $ATTEMPTS); do
            if ${pkgs.curl}/bin/curl -s http://${cfg.settings.bindAddress}:${toString cfg.settings.port}/_up > /dev/null 2>&1; then
              echo "CouchDB is healthy and ready for Obsidian LiveSync"
              exit 0
            fi
            echo "Waiting for CouchDB... ($i/$ATTEMPTS)"
            sleep 2
          done

          echo "CouchDB health check timeout after $TIMEOUT seconds"
          exit 1
        '';
      };
      # Manual health checks only - don't auto-start
      # wantedBy = [ "multi-user.target" ];
    };



    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (adminUsernamePath != null);
        message = "hwc.data.couchdb requires couchdb-admin-username secret (via hwc.secrets.api or cfg.secrets.adminUsername)";
      }
      {
        assertion = !cfg.enable || (adminPasswordPath != null);
        message = "hwc.data.couchdb requires couchdb-admin-password secret (via hwc.secrets.api or cfg.secrets.adminPassword)";
      }
      {
        assertion = !cfg.reverseProxy.enable || config.hwc.networking.reverseProxy.enable;
        message = "hwc.data.couchdb.reverseProxy requires hwc.networking.reverseProxy.enable = true";
      }
      {
        assertion = cfg.settings.bindAddress == "127.0.0.1" || cfg.settings.bindAddress == "0.0.0.0";
        message = "hwc.data.couchdb bindAddress should be 127.0.0.1 (localhost) or 0.0.0.0 (all interfaces)";
      }
    ];
  };
}
