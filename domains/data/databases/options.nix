# domains/data/databases/options.nix
#
# Database services for server workloads
#
# NAMESPACE: hwc.data.databases.*
#
# USED BY:
#   - domains/server/containers/paperless (PostgreSQL)
#   - domains/server/containers/firefly (PostgreSQL)
#   - domains/server/containers/immich (PostgreSQL, Redis)
#   - domains/business (PostgreSQL)
#   - profiles/server.nix, profiles/business.nix

{ lib, config, ... }:

let
  paths = config.hwc.paths or {};
in
{
  options.hwc.data.databases = {
    postgresql = {
      enable = lib.mkEnableOption "PostgreSQL database";

      version = lib.mkOption {
        type = lib.types.str;
        default = "15";
        description = "PostgreSQL version";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state or "/var/lib"}/postgresql";
        description = "PostgreSQL data directory";
      };

      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Databases to create";
      };

      backup = {
        enable = lib.mkEnableOption "Automatic backups";

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "Backup schedule";
        };
      };
    };

    redis = {
      enable = lib.mkEnableOption "Redis cache";

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port";
      };

      bind = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1 10.89.0.1";
        description = "Bind addresses for Redis (include media-network gateway for containers)";
      };

      maxMemory = lib.mkOption {
        type = lib.types.str;
        default = "2gb";
        description = "Maximum memory";
      };
    };

    influxdb = {
      enable = lib.mkEnableOption "InfluxDB time-series database";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8086;
        description = "InfluxDB port";
      };
    };
  };
}
