# nixos-hwc/modules/services/media/sonarr.nix
#
# Sonarr TV Series Management
# Provides automated TV series downloading and organization
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.storage.hot (modules/system/paths.nix)
#   Upstream: config.hwc.paths.storage.media (modules/system/paths.nix)
#   Upstream: config.hwc.services.prowlarr (modules/services/media/prowlarr.nix) [optional]
#   Upstream: config.hwc.services.qbittorrent (modules/services/utility/qbittorrent.nix) [optional]
#
# USED BY:
#   Downstream: profiles/media.nix (enables this service)
#   Downstream: modules/services/utility/soularr.nix (uses Sonarr API)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/media/sonarr.nix
#   - Any machine using Sonarr
#
# USAGE:
#   hwc.services.sonarr.enable = true;
#   hwc.services.sonarr.port = 8989;
#   hwc.services.sonarr.urlBase = "/sonarr";
#
# VALIDATION:
#   - Requires hwc.paths.storage.hot and media to be configured
#   - Port must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.sonarr;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.sonarr = {
    enable = lib.mkEnableOption "Sonarr TV series management";
    
    # Core settings
    port = lib.mkOption {
      type = lib.types.port;
      default = 8989;
      description = "Web interface port";
    };
    
    urlBase = lib.mkOption {
      type = lib.types.str;
      default = "/sonarr";
      description = "URL base for reverse proxy";
    };
    
    # Path settings (use centralized paths)
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/sonarr";
      description = "Data directory for Sonarr";
    };
    
    tvDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.media}/tv";
      description = "TV series library directory";
    };
    
    downloadsDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/downloads";
      description = "Downloads directory";
    };
    
    # Container settings
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/sonarr:latest";
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
        message = "Sonarr requires hwc.paths.storage.hot to be configured";
      }
      {
        assertion = paths.storage.media != null;
        message = "Sonarr requires hwc.paths.storage.media to be configured";
      }
    ];
    
    # Container service
    virtualisation.oci-containers.containers.sonarr = {
      image = cfg.image;
      autoStart = true;
      
      ports = [ "127.0.0.1:${toString cfg.port}:8989" ];
      
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.tvDir}:/tv"
        "${cfg.downloadsDir}:/downloads"
        "${paths.storage.hot}/manual/tv:/manual"
        "${paths.storage.hot}/quarantine/tv:/quarantine"
        "${paths.storage.hot}/processing/sonarr-temp:/processing"
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
      "d ${cfg.dataDir} 0755 sonarr sonarr -"
      "d ${cfg.tvDir} 0755 sonarr sonarr -"
      "d ${cfg.downloadsDir} 0755 sonarr sonarr -"
      "d ${paths.storage.hot}/manual/tv 0755 sonarr sonarr -"
      "d ${paths.storage.hot}/quarantine/tv 0755 sonarr sonarr -"
      "d ${paths.storage.hot}/processing/sonarr-temp 0755 sonarr sonarr -"
    ];
    
    # Create sonarr user and group
    users.users.sonarr = {
      isSystemUser = true;
      group = "sonarr";
      uid = 1000;
    };
    
    users.groups.sonarr = {
      gid = 1000;
    };
    
    # Configuration seeding service
    systemd.services.sonarr-config = {
      description = "Seed Sonarr configuration";
      before = [ "podman-sonarr.service" ];
      wantedBy = [ "podman-sonarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Ensure Sonarr config directory exists
        mkdir -p ${cfg.dataDir}
        
        # Create basic config.xml with URL base
        if [ ! -f ${cfg.dataDir}/config.xml ]; then
          cat > ${cfg.dataDir}/config.xml << 'CONFIG_EOF'
<Config>
  <LogLevel>info</LogLevel>
  <UpdateMechanism>Docker</UpdateMechanism>
  <Branch>main</Branch>
  <UrlBase>${cfg.urlBase}</UrlBase>
  <BindAddress>*</BindAddress>
  <Port>8989</Port>
  <SslPort>9898</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AnalyticsEnabled>False</AnalyticsEnabled>
</Config>
CONFIG_EOF
        fi
        
        # Set proper ownership and permissions
        chown -R sonarr:sonarr ${cfg.dataDir}
        chmod -R 755 ${cfg.dataDir}
        
        echo "Sonarr configuration seeded successfully"
      '';
    };
    
    # Firewall configuration (only if not using reverse proxy)
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.urlBase == "") [ cfg.port ];
    
    # Health check service
    systemd.services.sonarr-health = {
      description = "Sonarr health check";
      after = [ "podman-sonarr.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}${cfg.urlBase}/api/v3/system/status";
        RemainAfterExit = true;
      };
      
      startAt = "*:0/5"; # Every 5 minutes
    };
  };
}

