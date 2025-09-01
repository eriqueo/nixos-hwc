# nixos-hwc/modules/services/media/prowlarr.nix
#
# PROWLARR - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.prowlarr.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/media/prowlarr.nix
#
# USAGE:
#   hwc.services.prowlarr.enable = true;
#   # TODO: Add specific usage examples

# nixos-hwc/modules/services/media/prowlarr.nix
#
# Prowlarr Indexer Management
# Provides centralized indexer management for ARR stack
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.storage.hot (modules/system/paths.nix)
#   Upstream: config.time.timeZone (system configuration)
#
# USED BY:
#   Downstream: profiles/media.nix (enables this service)
#   Downstream: modules/services/media/sonarr.nix (uses indexers)
#   Downstream: modules/services/media/radarr.nix (uses indexers)
#   Downstream: modules/services/media/lidarr.nix (uses indexers)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/media/prowlarr.nix
#   - Any machine using Prowlarr
#
# USAGE:
#   hwc.services.prowlarr.enable = true;
#   hwc.services.prowlarr.port = 9696;
#   hwc.services.prowlarr.urlBase = "/prowlarr";
#
# VALIDATION:
#   - Requires hwc.paths.storage.hot to be configured
#   - Port must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.prowlarr;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.prowlarr = {
    enable = lib.mkEnableOption "Prowlarr indexer management";
    
    # Core settings
    port = lib.mkOption {
      type = lib.types.port;
      default = 9696;
      description = "Web interface port";
    };
    
    urlBase = lib.mkOption {
      type = lib.types.str;
      default = "/prowlarr";
      description = "URL base for reverse proxy";
    };
    
    # Path settings (use centralized paths)
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/prowlarr";
      description = "Data directory for Prowlarr";
    };
    
    # Container settings
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/prowlarr:latest";
      description = "Container image to use";
    };
    
    memory = lib.mkOption {
      type = lib.types.str;
      default = "1g";
      description = "Memory limit for container";
    };
    
    cpus = lib.mkOption {
      type = lib.types.str;
      default = "0.5";
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
        message = "Prowlarr requires hwc.paths.storage.hot to be configured";
      }
    ];
    
    # Container service
    virtualisation.oci-containers.containers.prowlarr = {
      image = cfg.image;
      autoStart = true;
      
      ports = [ "127.0.0.1:${toString cfg.port}:9696" ];
      
      volumes = [
        "${cfg.dataDir}:/config"
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
      "d ${cfg.dataDir} 0755 prowlarr prowlarr -"
    ];
    
    # Create prowlarr user and group
    users.users.prowlarr = {
      isSystemUser = true;
      group = "prowlarr";
      uid = 1000;
    };
    
    users.groups.prowlarr = {
      gid = 1000;
    };
    
    # Configuration seeding service
    systemd.services.prowlarr-config = {
      description = "Seed Prowlarr configuration";
      before = [ "podman-prowlarr.service" ];
      wantedBy = [ "podman-prowlarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Ensure Prowlarr config directory exists
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
  <Port>9696</Port>
  <SslPort>9697</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AnalyticsEnabled>False</AnalyticsEnabled>
</Config>
CONFIG_EOF
        fi
        
        # Set proper ownership and permissions
        chown -R prowlarr:prowlarr ${cfg.dataDir}
        chmod -R 755 ${cfg.dataDir}
        
        echo "Prowlarr configuration seeded successfully"
      '';
    };
    
    # Firewall configuration (only if not using reverse proxy)
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.urlBase == "") [ cfg.port ];
    
    # Health check service
    systemd.services.prowlarr-health = {
      description = "Prowlarr health check";
      after = [ "podman-prowlarr.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}${cfg.urlBase}/api/v1/system/status";
        RemainAfterExit = true;
      };
      
      startAt = "*:0/5"; # Every 5 minutes
    };
  };
}

