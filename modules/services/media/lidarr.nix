# nixos-hwc/modules/services/media/lidarr.nix
#
# LIDARR - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.lidarr.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/media/lidarr.nix
#
# USAGE:
#   hwc.services.lidarr.enable = true;
#   # TODO: Add specific usage examples

# nixos-hwc/modules/services/media/lidarr.nix
#
# Lidarr Music Management
# Provides automated music downloading and organization
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.storage.hot (modules/system/paths.nix)
#   Upstream: config.hwc.paths.storage.media (modules/system/paths.nix)
#   Upstream: config.hwc.services.prowlarr (modules/services/media/prowlarr.nix) [optional]
#   Upstream: config.hwc.services.qbittorrent (modules/services/utility/qbittorrent.nix) [optional]
#
# USED BY:
#   Downstream: profiles/media.nix (enables this service)
#   Downstream: modules/services/utility/soularr.nix (uses Lidarr API)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/media/lidarr.nix
#   - Any machine using Lidarr
#
# USAGE:
#   hwc.services.lidarr.enable = true;
#   hwc.services.lidarr.port = 8686;
#   hwc.services.lidarr.urlBase = "/lidarr";
#
# VALIDATION:
#   - Requires hwc.paths.storage.hot and media to be configured
#   - Port must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.lidarr;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.lidarr = {
    enable = lib.mkEnableOption "Lidarr music management";
    
    # Core settings
    port = lib.mkOption {
      type = lib.types.port;
      default = 8686;
      description = "Web interface port";
    };
    
    urlBase = lib.mkOption {
      type = lib.types.str;
      default = "/lidarr";
      description = "URL base for reverse proxy";
    };
    
    # Path settings (use centralized paths)
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/lidarr";
      description = "Data directory for Lidarr";
    };
    
    musicDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.media}/music";
      description = "Music library directory";
    };
    
    downloadsDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/downloads";
      description = "Downloads directory";
    };
    
    # Container settings
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/lidarr:latest";
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
        message = "Lidarr requires hwc.paths.storage.hot to be configured";
      }
      {
        assertion = paths.storage.media != null;
        message = "Lidarr requires hwc.paths.storage.media to be configured";
      }
    ];
    
    # Container service
    virtualisation.oci-containers.containers.lidarr = {
      image = cfg.image;
      autoStart = true;
      
      ports = [ "127.0.0.1:${toString cfg.port}:8686" ];
      
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.musicDir}:/music"
        "${cfg.downloadsDir}:/downloads"
        "${paths.storage.hot}/manual/music:/manual"
        "${paths.storage.hot}/quarantine/music:/quarantine"
        "${paths.storage.hot}/processing/lidarr-temp:/processing"
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
      "d ${cfg.dataDir} 0755 lidarr lidarr -"
      "d ${cfg.musicDir} 0755 lidarr lidarr -"
      "d ${cfg.downloadsDir} 0755 lidarr lidarr -"
      "d ${paths.storage.hot}/manual/music 0755 lidarr lidarr -"
      "d ${paths.storage.hot}/quarantine/music 0755 lidarr lidarr -"
      "d ${paths.storage.hot}/processing/lidarr-temp 0755 lidarr lidarr -"
    ];
    
    # Create lidarr user and group
    users.users.lidarr = {
      isSystemUser = true;
      group = "lidarr";
      uid = 1000;
    };
    
    users.groups.lidarr = {
      gid = 1000;
    };
    
    # Configuration seeding service
    systemd.services.lidarr-config = {
      description = "Seed Lidarr configuration";
      before = [ "podman-lidarr.service" ];
      wantedBy = [ "podman-lidarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Ensure Lidarr config directory exists
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
  <Port>8686</Port>
  <SslPort>6868</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AnalyticsEnabled>False</AnalyticsEnabled>
</Config>
CONFIG_EOF
        fi
        
        # Set proper ownership and permissions
        chown -R lidarr:lidarr ${cfg.dataDir}
        chmod -R 755 ${cfg.dataDir}
        
        echo "Lidarr configuration seeded successfully"
      '';
    };
    
    # Firewall configuration (only if not using reverse proxy)
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.urlBase == "") [ cfg.port ];
    
    # Health check service
    systemd.services.lidarr-health = {
      description = "Lidarr health check";
      after = [ "podman-lidarr.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}${cfg.urlBase}/api/v1/system/status";
        RemainAfterExit = true;
      };
      
      startAt = "*:0/5"; # Every 5 minutes
    };
  };
}

