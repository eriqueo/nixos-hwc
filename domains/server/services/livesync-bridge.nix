# HWC Charter Module/domains/server/services/livesync-bridge.nix
#
# LIVESYNC BRIDGE - Filesystem to CouchDB sync for Obsidian LiveSync
# Syncs transcript markdown files from filesystem to CouchDB in proper LiveSync format
#
# DEPENDENCIES (Upstream):
#   - config.hwc.server.couchdb (domains/server/couchdb/index.nix)
#   - config.age.secrets.couchdb-admin-* (domains/secrets/declarations/server.nix)
#   - pkgs.deno, pkgs.git
#
# USED BY (Downstream):
#   - profiles/server.nix (enables via hwc.services.livesyncBridge.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../domains/server/services/livesync-bridge.nix
#
# USAGE:
#   hwc.services.livesyncBridge.enable = true;
#   hwc.services.livesyncBridge.watchPath = "/home/eric/01-documents/01-vaults/04-transcripts";

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.livesyncBridge;

  livesyncBridgeDir = "/var/lib/livesync-bridge";
  configFile = "${livesyncBridgeDir}/dat/config.json";

  # Repository URL
  bridgeRepo = "https://github.com/vrtmrz/livesync-bridge";
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.services.livesyncBridge = {
    enable = lib.mkEnableOption "LiveSync Bridge service for Obsidian sync";

    watchPath = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/01-documents/01-vaults/04-transcripts";
      description = "Filesystem path to watch for markdown files";
    };

    couchdbUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:5984";
      description = "CouchDB server URL";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "sync_transcripts";
      description = "CouchDB database name (must match Obsidian LiveSync config)";
    };

    passphrase = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Encryption passphrase (leave empty if not using E2EE in Obsidian)";
    };

    chunkSize = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Custom chunk size for large files (KB)";
    };

    minimumChunkSize = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Minimum chunk size (KB)";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Clone livesync-bridge repository on system activation
    system.activationScripts.livesync-bridge-setup = lib.stringAfter [ "var" ] ''
      if [ ! -d ${livesyncBridgeDir} ]; then
        echo "Cloning LiveSync Bridge repository..."
        mkdir -p ${livesyncBridgeDir}
        ${pkgs.git}/bin/git clone --recursive ${bridgeRepo} ${livesyncBridgeDir}
        chown -R root:root ${livesyncBridgeDir}
      fi
    '';

    # Systemd service for LiveSync Bridge
    systemd.services.livesync-bridge = {
      description = "LiveSync Bridge - Filesystem to CouchDB Sync for Obsidian";
      after = [ "network.target" "couchdb.service" ];
      wants = [ "couchdb.service" "agenix.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DENO_DIR = "/var/cache/deno";
        NO_COLOR = "1";  # Disable color output in logs
      };

      serviceConfig = {
        Type = "simple";
        User = "root";  # Needs access to transcript directories
        WorkingDirectory = livesyncBridgeDir;
        Restart = "always";
        RestartSec = "10s";

        # Load CouchDB credentials from agenix
        LoadCredential = [
          "couchdb-username:${config.age.secrets.couchdb-admin-username.path}"
          "couchdb-password:${config.age.secrets.couchdb-admin-password.path}"
        ];

        # State directory for Deno cache
        StateDirectory = "deno";
        CacheDirectory = "deno";
      };

      # Generate config file from credentials before starting
      preStart = ''
        echo "LiveSync Bridge: Starting pre-start configuration..."

        # Read CouchDB credentials
        COUCHDB_USER=$(cat $CREDENTIALS_DIRECTORY/couchdb-username)
        COUCHDB_PASS=$(cat $CREDENTIALS_DIRECTORY/couchdb-password)

        # Ensure config directory exists
        mkdir -p ${livesyncBridgeDir}/dat

        # Ensure watch directory exists
        mkdir -p ${cfg.watchPath}

        # Generate configuration file
        cat > ${configFile} <<EOF
        {
          "peers": [
            {
              "type": "storage",
              "name": "transcript-filesystem",
              "baseDir": "${cfg.watchPath}",
              "scanOfflineChanges": true,
              "useChokidar": true,
              "doNotDeleteOnSync": false
            },
            {
              "type": "couchdb",
              "name": "obsidian-livesync",
              "url": "${cfg.couchdbUrl}",
              "database": "${cfg.database}",
              "username": "$COUCHDB_USER",
              "password": "$COUCHDB_PASS",
              "passphrase": "${cfg.passphrase}",
              "obfuscatePassphrase": "",
              "customChunkSize": ${toString cfg.chunkSize},
              "minimumChunkSize": ${toString cfg.minimumChunkSize},
              "baseDir": ""
            }
          ]
        }
        EOF

        echo "LiveSync Bridge: Configuration generated at ${configFile}"
        echo "  Watch path: ${cfg.watchPath}"
        echo "  Database: ${cfg.database}"
        echo "  CouchDB URL: ${cfg.couchdbUrl}"
      '';

      # Start LiveSync Bridge with Deno
      script = ''
        echo "LiveSync Bridge: Starting sync service..."

        # Install dependencies if needed
        if [ ! -f "${livesyncBridgeDir}/deno.lock" ]; then
          echo "Installing Deno dependencies..."
          ${pkgs.deno}/bin/deno install
        fi

        # Run LiveSync Bridge
        echo "Starting LiveSync Bridge..."
        exec ${pkgs.deno}/bin/deno task run
      '';

      # Log output for debugging
      postStart = ''
        echo "LiveSync Bridge is now running"
        echo "Watching: ${cfg.watchPath}"
        echo "Syncing to: ${cfg.couchdbUrl}/${cfg.database}"
      '';
    };

    # Ensure Deno is available system-wide
    environment.systemPackages = with pkgs; [
      deno
      git
    ];
  };

  #============================================================================
  # VALIDATION
  #============================================================================
  config.assertions = [
    {
      assertion = !cfg.enable || config.hwc.server.couchdb.enable;
      message = "hwc.services.livesyncBridge requires hwc.server.couchdb.enable = true";
    }
    {
      assertion = !cfg.enable || (config.age.secrets.couchdb-admin-username.path != null);
      message = "hwc.services.livesyncBridge requires couchdb-admin-username secret";
    }
    {
      assertion = !cfg.enable || (config.age.secrets.couchdb-admin-password.path != null);
      message = "hwc.services.livesyncBridge requires couchdb-admin-password secret";
    }
  ];
}
