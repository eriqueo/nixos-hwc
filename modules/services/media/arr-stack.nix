{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.arrStack;
  paths = config.hwc.paths;
  
  mkArrService = name: port: {
    enable = lib.mkEnableOption "${name} service";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = port;
      description = "${name} web port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/${lib.toLower name}";
      description = "${name} data directory";
    };
  };
in {
  options.hwc.services.arrStack = {
    enable = lib.mkEnableOption "ARR media management stack";
    
    mediaPath = lib.mkOption {
      type = lib.types.path;
      default = config.hwc.storage.media.path;
      description = "Media library path";
    };
    
    downloadPath = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.storage.media.path}/downloads";
      description = "Download path";
    };
    
    sonarr = mkArrService "Sonarr" 8989;
    radarr = mkArrService "Radarr" 7878;
    prowlarr = mkArrService "Prowlarr" 9696;
    bazarr = mkArrService "Bazarr" 6767;
    overseerr = mkArrService "Overseerr" 5055;
    
    vpn = {
      enable = lib.mkEnableOption "VPN for downloads";
      configFile = lib.mkOption {
        type = lib.types.path;
        description = "VPN configuration file";
      };
    };
  };
  
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.sonarr.enable {
      virtualisation.oci-containers.containers.sonarr = {
        image = "lscr.io/linuxserver/sonarr:latest";
        ports = [ "${toString cfg.sonarr.port}:8989" ];
        
        volumes = [
          "${cfg.sonarr.dataDir}:/config"
          "${cfg.mediaPath}/tv:/tv"
          "${cfg.downloadPath}:/downloads"
        ];
        
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = config.time.timeZone;
        };
      };
    })
    
    (lib.mkIf cfg.radarr.enable {
      virtualisation.oci-containers.containers.radarr = {
        image = "lscr.io/linuxserver/radarr:latest";
        ports = [ "${toString cfg.radarr.port}:7878" ];
        
        volumes = [
          "${cfg.radarr.dataDir}:/config"
          "${cfg.mediaPath}/movies:/movies"
          "${cfg.downloadPath}:/downloads"
        ];
        
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = config.time.timeZone;
        };
      };
    })
    
    (lib.mkIf cfg.prowlarr.enable {
      virtualisation.oci-containers.containers.prowlarr = {
        image = "lscr.io/linuxserver/prowlarr:latest";
        ports = [ "${toString cfg.prowlarr.port}:9696" ];
        
        volumes = [
          "${cfg.prowlarr.dataDir}:/config"
        ];
        
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = config.time.timeZone;
        };
      };
    })
    
    {
      systemd.tmpfiles.rules = lib.flatten [
        (lib.optional cfg.sonarr.enable "d ${cfg.sonarr.dataDir} 0755 root root -")
        (lib.optional cfg.radarr.enable "d ${cfg.radarr.dataDir} 0755 root root -")
        (lib.optional cfg.prowlarr.enable "d ${cfg.prowlarr.dataDir} 0755 root root -")
      ];
      
      networking.firewall.allowedTCPPorts = lib.flatten [
        (lib.optional cfg.sonarr.enable cfg.sonarr.port)
        (lib.optional cfg.radarr.enable cfg.radarr.port)
        (lib.optional cfg.prowlarr.enable cfg.prowlarr.port)
      ];
    }
  ]);
}
