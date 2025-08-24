# nixos-hwc/modules/services/media/radarr.nix
#
# Radarr Movie Management
# Provides automated movie downloading and organization
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.storage.hot (modules/system/paths.nix)
#   Upstream: config.hwc.paths.storage.media (modules/system/paths.nix)
#   Upstream: config.hwc.services.prowlarr (modules/services/media/prowlarr.nix) [optional]
#   Upstream: config.hwc.services.qbittorrent (modules/services/utility/qbittorrent.nix) [optional]
#
# USED BY:
#   Downstream: profiles/media.nix (enables this service)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/media/radarr.nix
#   - Any machine using Radarr
#
# USAGE:
#   hwc.services.radarr.enable = true;
#   hwc.services.radarr.port = 7878;
#   hwc.services.radarr.urlBase = "/radarr";
#
# VALIDATION:
#   - Requires hwc.paths.storage.hot and media to be configured
#   - Port must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.radarr;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.radarr = {
    enable = lib.mkEnableOption "Radarr movie management";
    
    # Core settings
    port = lib.mkOption {
      type = lib.types.port;
      default = 7878;
      description = "Web interface port";
    };
    
    urlBase = lib.mkOption {
      type = lib.types.str;
      default = "/radarr";
      description = "URL base for reverse proxy";
    };
    
    # Path settings (use centralized paths)
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/radarr";
      description = "Data directory for Radarr";
    };
    
    moviesDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.media}/movies";
      description = "Movies library directory";
    };
    
    downloadsDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/downloads";
      description = "Downloads directory";
    };
    
    # Container settings
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/radarr:latest";
      description = "Container image to use";
    };
    
    memory = lib.mkOption {
      type = lib.types.str;
      default = "2g";
      description = "Memory limit for container";
    };
    
    cpus = lib.mkOption {
      type = lib.types.str;
      default = "1.0";
      description = "CPU limit for container";
    };
    
    # Network settings
    networkName = lib.mkOption {
      type = lib.types.str;
      default = "media-network";
      description = "Container network name";
    };
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation: Check required dependencies
    assertions = [
      {
        assertion = paths.storage.hot != null;
        message = "Radarr requires hwc.paths.storage.hot to be configured";
      }
      {
        assertion = paths.storage.media != null;
        message = "Radarr requires hwc.paths.storage.media to be configured";
      }
    ];
    
    # Container service
    virtualisation.oci-containers.containers.radarr = {
      image = cfg.image;
      autoStart = true;
      
      ports = [ "127.0.0.1:${toString cfg.port}:7878" ];
      
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.moviesDir}:/movies"
        "${cfg.downloadsDir}:/downloads"
        "${paths.storage.hot}/manual/movies:/manual"
        "${paths.storage.hot}/quarantine/movies:/quarantine"
        "${paths.storage.hot}/processing/radarr-temp:/processing"
      ];
      
      environment = {
        TZ = config.time.timeZone;
        PUID = "1000";
        PGID = "1000";
      };
      
      extraOptions = [
        "--network=${cfg.networkName}"
        "--memory=${cfg.memory}"
        "--cpus=${cfg.cpus}"
        "--memory-swap=${cfg.memory}"
      ];
    };
    
    # Directory creation
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 radarr radarr -"
      "d ${cfg.moviesDir} 0755 radarr radarr -"
      "d ${cfg.downloadsDir} 0755 radarr radarr -"
      "d ${paths.storage.hot}/manual/movies 0755 radarr radarr -"
      "d ${paths.storage.hot}/quarantine/movies 0755 radarr radarr -"
      "d ${paths.storage.hot}/processing/radarr-temp 0755 radarr radarr -"
    ];
    
    # Create radarr user and group
    users.users.radarr = {
      isSystemUser = true;
      group = "radarr";
      uid = 1000;
    };
    
    users.groups.radarr = {
      gid = 1000;
    };
    
    # Configuration seeding service
    systemd.services.radarr-config = {
      description = "Seed Radarr configuration";
      before = [ "podman-radarr.service" ];
      wantedBy = [ "podman-radarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Ensure Radarr config directory exists
        mkdir -p ${cfg.dataDir}
        
        # Create basic config.xml with URL base
        if [ ! -f ${cfg.dataDir}/config.xml ]; then
          cat > ${cfg.dataDir}/config.xml << 'CONFIG_EOF'
<Config>
  <LogLevel>info</LogLevel>
  <UpdateMechanism>Docker</UpdateMechanism>
  <Branch>master</Branch>
  <UrlBase>${cfg.urlBase}</UrlBase>
  <BindAddress>*</BindAddress>
  <Port>7878</Port>
  <SslPort>9898</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AnalyticsEnabled>False</AnalyticsEnabled>
</Config>
CONFIG_EOF
        fi
        
        # Set proper ownership and permissions
        chown -R radarr:radarr ${cfg.dataDir}
        chmod -R 755 ${cfg.dataDir}
        
        echo "Radarr configuration seeded successfully"
      '';
    };
    
    # Firewall configuration (only if not using reverse proxy)
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.urlBase == "") [ cfg.port ];
    
    # Health check service
    systemd.services.radarr-health = {
      description = "Radarr health check";
      after = [ "podman-radarr.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}${cfg.urlBase}/api/v3/system/status";
        RemainAfterExit = true;
      };
      
      startAt = "*:0/5"; # Every 5 minutes
    };
  };
}

