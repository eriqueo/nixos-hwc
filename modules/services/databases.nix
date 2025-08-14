{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.databases;
  paths = config.hwc.paths;
in {
  options.hwc.services.databases = {
    postgresql = {
      enable = lib.mkEnableOption "PostgreSQL database";
      
      version = lib.mkOption {
        type = lib.types.str;
        default = "15";
        description = "PostgreSQL version";
      };
      
      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state}/postgresql";
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
        };
      };
    };
    
    redis = {
      enable = lib.mkEnableOption "Redis cache";
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
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
      };
    };
  };
  
  config = lib.mkMerge [
    (lib.mkIf cfg.postgresql.enable {
      services.postgresql = {
        enable = true;
        package = pkgs."postgresql_${cfg.postgresql.version}";
        dataDir = cfg.postgresql.dataDir;
        
        ensureDatabases = cfg.postgresql.databases;
        
        authentication = ''
          local all all trust
          host all all 127.0.0.1/32 trust
          host all all ::1/128 trust
        '';
      };
      
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
        settings = {
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
