# HWC Charter Module/domains/services/databases.nix
#
# DATABASES - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.server.databases.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/databases.nix
#
# USAGE:
#   hwc.server.databases.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.databases;
  paths = config.hwc.paths;
in {
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.postgresql.enable {
      services.postgresql = {
        enable = true;
        # CHARTER v9.0: Explicitly pin PostgreSQL 15 to prevent data format breakage
        # Data directory initialized with PostgreSQL 15 - upgrading requires migration
        # Include pgvector and vectorchord for Immich vector search support
        # pgvector provides "vector" extension, vectorchord provides "vchord" extension
        # Note: pgvecto-rs removed due to library path issues after NixOS 25.11 update
        package = pkgs.postgresql_15;
        extensions = ps: [ ps.pgvector ps.vectorchord ];
        dataDir = cfg.postgresql.dataDir;

        ensureDatabases = cfg.postgresql.databases;

        # Listen on localhost and container network gateway
        settings.listen_addresses = lib.mkForce "localhost,10.89.0.1";

        # vectorchord requires shared preload
        settings.shared_preload_libraries = "vchord";

        authentication = ''
          local all all trust
          host all all 127.0.0.1/32 trust
          host all all ::1/128 trust
          # Allow connections from Podman media-network (10.89.0.0/16)
          host all all 10.89.0.0/16 trust
        '';
      };

      # CHARTER v9.0: Prevent accidental PostgreSQL version upgrades
      assertions = [{
        assertion =
          builtins.match "15\\..*" config.services.postgresql.package.version != null;
        message = ''
          ============================================================
          POSTGRESQL VERSION CHANGE DETECTED
          ============================================================
          Current: ${config.services.postgresql.package.version}
          Expected: 15.x

          PostgreSQL data directory is PostgreSQL 15 format.
          Upgrading requires data migration:

          1. Backup: pg_dumpall -f /backup/postgresql-pre-upgrade.sql
          2. Stop PostgreSQL: systemctl stop postgresql
          3. Migrate data: pg_upgrade or pg_dumpall/restore
          4. Update pin: package = pkgs.postgresql_16;
          5. Test thoroughly before applying

          See CHARTER.md section 24 "Flake Update Strategy"
          ============================================================
        '';
      }];

      # Backup service
      systemd.services.postgresql-backup = lib.mkIf cfg.postgresql.backup.enable {
        description = "PostgreSQL backup";
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          ExecStart = "${pkgs.postgresql}/bin/pg_dumpall -f ${paths.backup}/postgresql-$(date +%Y%m%d).sql";
        };
      };
      
      systemd.timers.postgresql-backup = lib.mkIf cfg.postgresql.backup.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.postgresql.backup.schedule;
          Persistent = true;
        };
      };
    })
    
    (lib.mkIf cfg.redis.enable {
      services.redis.servers.main = {
        enable = true;
        port = cfg.redis.port;
        bind = cfg.redis.bind;
        settings = {
          protected-mode = "no";
          maxmemory = cfg.redis.maxMemory;
          maxmemory-policy = "allkeys-lru";
        };
      };
    })
    
    (lib.mkIf cfg.influxdb.enable {
      services.influxdb2 = {
        enable = true;
        settings = {
          http-bind-address = ":${toString cfg.influxdb.port}";
        };
      };
      
      networking.firewall.allowedTCPPorts = [ cfg.influxdb.port ];
    })
  ];
}
