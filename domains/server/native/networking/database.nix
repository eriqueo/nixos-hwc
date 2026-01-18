# HWC Charter Module/domains/services/business/database.nix
#
# DATABASE - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.server.database.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/business/database.nix
#
# USAGE:
#   hwc.server.database.enable = true;
#   # TODO: Add specific usage examples

# modules/services/business/database.nix
# Charter v3 Business Database Services
# SOURCE: /etc/nixos/hosts/serv../domains/business-services.nix (lines 1-133)
{ config, lib, pkgs, ... }:

with lib;

let 
  cfg = config.hwc.server.business.database;
  paths = config.hwc.paths;
in {
  
  ####################################################################
  # CHARTER V3 OPTIONS
  ####################################################################
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.server.business.database = {
    enable = mkEnableOption "business database services";
    
    postgresql = {
      enable = mkEnableOption "PostgreSQL database for business data";
      package = mkOption {
        type = types.package;
        default = pkgs.postgresql_15;
        description = "PostgreSQL package to use";
      };
      databaseName = mkOption {
        type = types.str;
        default = "heartwood_business";
        description = "Name of the business database";
      };
      username = mkOption {
        type = types.str;
        default = "business_user";
        description = "Database username for business operations";
      };
      settings = mkOption {
        type = types.attrsOf (types.oneOf [types.str types.int]);
        default = {
          shared_buffers = "256MB";
          effective_cache_size = "1GB";
          maintenance_work_mem = "64MB";
        };
        description = "PostgreSQL configuration settings";
      };
    };
    
    redis = {
      enable = mkEnableOption "Redis for business caching and sessions";
      port = mkOption {
        type = types.port;
        default = 6379;
        description = "Redis server port";
      };
      bind = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Redis bind address";
      };
    };
    
    backup = {
      enable = mkEnableOption "automated database backups";
      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Backup schedule (systemd timer format)";
      };
      retentionDays = mkOption {
        type = types.int;
        default = 30;
        description = "Number of days to retain backups";
      };
    };
    
    packages = {
      enable = mkEnableOption "business-specific packages for document processing and analysis";
    };
  };

  ####################################################################
  # CHARTER V3 IMPLEMENTATION
  ####################################################################

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = mkIf cfg.enable {
    
    # Assertions

    #==========================================================================
    # VALIDATION - Assertions and checks
    #==========================================================================
    assertions = [
      {
        assertion = cfg.postgresql.enable -> config.hwc.secrets.secrets.database;
        message = "Business PostgreSQL requires database secrets to be enabled (hwc.secrets.secrets.database = true)";
      }
      {
        assertion = cfg.backup.enable -> cfg.postgresql.enable;
        message = "Database backup requires PostgreSQL to be enabled";
      }
    ];

    ####################################################################
    # POSTGRESQL SERVICE
    ####################################################################
    services.postgresql = mkIf cfg.postgresql.enable {
      enable = true;
      package = cfg.postgresql.package;
      
      # Database initialization with agenix integration
      initialScript = pkgs.writeShellScript "postgres-business-init.sh" ''
        # Wait for agenix secret to be available
        while [ ! -f /run/agenix/database-password ]; do
          echo "Waiting for database password secret..."
          sleep 1
        done
        
        # Read password from agenix secret
        DB_PASSWORD=$(cat /run/agenix/database-password)
        
        # Check if database exists, create if not
        if ! ${cfg.postgresql.package}/bin/psql -U postgres -lqt | cut -d \| -f 1 | grep -qw ${cfg.postgresql.databaseName}; then
          echo "Creating ${cfg.postgresql.databaseName} database..."
          ${cfg.postgresql.package}/bin/psql -U postgres -c "CREATE DATABASE ${cfg.postgresql.databaseName};"
        else
          echo "Database ${cfg.postgresql.databaseName} already exists"
        fi
        
        # Create role (user) with proper conditional syntax
        ${cfg.postgresql.package}/bin/psql -U postgres -c "
        DO \$\$
        BEGIN
          IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '${cfg.postgresql.username}') THEN
            CREATE ROLE ${cfg.postgresql.username} WITH LOGIN PASSWORD '$DB_PASSWORD';
          END IF;
        END
        \$\$;
        "
        
        # Grant privileges
        ${cfg.postgresql.package}/bin/psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.postgresql.databaseName} TO ${cfg.postgresql.username};"
        
        # Enable UUID extension in the business database
        ${cfg.postgresql.package}/bin/psql -U postgres -d ${cfg.postgresql.databaseName} -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
        
        echo "PostgreSQL business database initialization completed successfully"
      '';
      
      # PostgreSQL optimizations
      settings = cfg.postgresql.settings;
    };

    # Ensure PostgreSQL waits for agenix secrets
    systemd.services.postgresql = mkIf cfg.postgresql.enable {
      after = [ "agenix.service" ];
      wants = [ "agenix.service" ];
    };

    ####################################################################
    # REDIS SERVICE  
    ####################################################################
    services.redis.servers.business = mkIf cfg.redis.enable {
      enable = true;
      port = cfg.redis.port;
      bind = cfg.redis.bind;
    };

    ####################################################################
    # BUSINESS PACKAGES
    ####################################################################
    environment.systemPackages = mkIf cfg.packages.enable (with pkgs; [
      # OCR and document processing
      tesseract
      imagemagick
      poppler_utils  # PDF processing
      
      # Python packages for business automation
      python3Packages.fastapi
      python3Packages.sqlalchemy
      python3Packages.psycopg2
      python3Packages.pandas
      python3Packages.streamlit
      python3Packages.python-multipart  # For file uploads
      python3Packages.pillow  # Image processing
      python3Packages.opencv4  # Advanced image processing
      python3Packages.pytesseract
      # python3Packages.spacy  # Temporarily disabled due to wandb build issues
      python3Packages.httpx  # For API requests
      python3Packages.asyncpg
      python3Packages.redis
      
      # Additional utilities
      curl
      jq
      postgresql  # Client tools
    ]);

    ####################################################################
    # DATABASE BACKUP SYSTEM
    ####################################################################
    systemd.services.business-backup = mkIf (cfg.backup.enable && cfg.postgresql.enable) {
      description = "Business database backup service";
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        ExecStart = pkgs.writeShellScript "business-backup" ''
          # Wait for database password secret
          while [ ! -f /run/agenix/database-password ]; do
            echo "Waiting for database password secret for backup..."
            sleep 1
          done
          
          # Set database password for pg_dump
          export PGPASSWORD=$(cat /run/agenix/database-password)
          
          # Create backup with timestamp
          DATE=$(date +%Y%m%d_%H%M%S)
          BACKUP_FILE="${paths.business.backups}/${cfg.postgresql.databaseName}_$DATE.sql.gz"
          
          echo "Creating backup: $BACKUP_FILE"
          ${pkgs.postgresql}/bin/pg_dump \
            -U ${cfg.postgresql.username} \
            -h localhost \
            ${cfg.postgresql.databaseName} \
            | gzip > "$BACKUP_FILE"
          
          # Verify backup was created
          if [ -f "$BACKUP_FILE" ]; then
            echo "Backup created successfully: $BACKUP_FILE"
          else
            echo "ERROR: Backup failed to create"
            exit 1
          fi
          
          # Keep only last N days of backups
          find ${paths.business.backups} -name "${cfg.postgresql.databaseName}_*.sql.gz" -mtime +${toString cfg.backup.retentionDays} -delete
          echo "Cleaned up backups older than ${toString cfg.backup.retentionDays} days"
        '';
      };
    };
    
    # Schedule database backups
    systemd.timers.business-backup = mkIf (cfg.backup.enable && cfg.postgresql.enable) {
      description = "Business database backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backup.schedule;
        Persistent = true;
      };
    };

    ####################################################################
    # NETWORKING INTEGRATION
    ####################################################################
    # Register business database ports with Charter v3 networking
    hwc.system.networking.firewall.extraTcpPorts = mkIf config.hwc.system.networking.enable (
      optional cfg.postgresql.enable 5432 ++
      optional cfg.redis.enable cfg.redis.port
    );

    # Allow business database access on Tailscale interface
    networking.firewall.interfaces."tailscale0" = mkIf config.hwc.system.networking.tailscale.enable {
      allowedTCPPorts = 
        optional cfg.postgresql.enable 5432 ++
        optional cfg.redis.enable cfg.redis.port;
    };
  };
}
