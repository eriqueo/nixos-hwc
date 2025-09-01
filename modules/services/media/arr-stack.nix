# nixos-hwc/modules/services/media/arr-stack.nix
#
# ARR STACK - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.arr-stack.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/media/arr-stack.nix
#
# USAGE:
#   hwc.services.arr-stack.enable = true;
#   # TODO: Add specific usage examples

# modules/services/media/arr-stack.nix
#
# HWC ARR Stack Media Management (Charter v3)
# Sonarr, Radarr, Lidarr, and Prowlarr containerized services
#
# SOURCE FILES:
#   - /etc/nixos/hosts/server/modules/media-containers.nix (ARR containers)
#   - /etc/nixos/hosts/server/modules/media-core.nix (networking)
#
# DEPENDENCIES:
#   Upstream: modules/security/secrets.nix (ARR API keys)
#   Upstream: modules/system/paths.nix (storage paths)
#   Upstream: modules/services/media/networking.nix (VPN network)
#
# USED BY:
#   Downstream: profiles/server.nix (media server configuration)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../modules/services/media/arr-stack.nix
#
# USAGE:
#   hwc.services.media.arr.enable = true;           # Enable all ARR services
#   hwc.services.media.arr.sonarr.enable = true;    # Individual services
#   hwc.services.media.arr.gpu.enable = true;       # GPU acceleration
#
# VALIDATION:
#   - Requires hwc.security.secrets.arr = true for API keys
#   - Requires storage paths (hot/media) to be configured
#   - Requires VPN network for download clients

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.media.arr;
  paths = config.hwc.paths;
  
  # Helper functions from source media-containers.nix
  configVol = service: "${paths.arr.downloads}/${service}:/config";
  
  # Standard environment for media services
  mediaServiceEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ = config.time.timeZone or "America/Denver";
  };

  # GPU passthrough options (from source)
  nvidiaGpuOptions = [
    "--device=/dev/nvidia0:/dev/nvidia0:rwm"
    "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
    "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
    "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
    "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
    "--device=/dev/dri:/dev/dri:rwm"
  ];

  nvidiaEnv = {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
  };

  # Container builder for ARR services (adapted from source)
  buildArrContainer = { name, image, mediaType, port }: {
    inherit image;
    autoStart = cfg.enable && cfg.${name}.enable;
    extraOptions = [
      "--network=${cfg.networkName}"
      "--memory=2g" "--cpus=1.0" "--memory-swap=4g"
    ] ++ lib.optionals cfg.gpu.enable nvidiaGpuOptions;
    
    environment = mediaServiceEnv 
      // lib.optionalAttrs cfg.gpu.enable nvidiaEnv
      // cfg.${name}.extraEnvironment;
    
    ports = [ "127.0.0.1:${toString port}:${toString port}" ];
    
    volumes = [
      (configVol name)
      "${paths.media}/${mediaType}:/${mediaType}"
      "${paths.hot}/downloads:/hot-downloads"
      "${paths.hot}/manual/${mediaType}:/manual"  
      "${paths.hot}/quarantine/${mediaType}:/quarantine"
      "${paths.hot}/processing/${name}-temp:/processing"
    ] ++ cfg.${name}.extraVolumes;
  };
in {
  #============================================================================
  # OPTIONS - ARR Stack Configuration
  #============================================================================
  
  options.hwc.services.media.arr = {
    enable = lib.mkEnableOption "ARR stack media management services";

    #=========================================================================
    # NETWORK CONFIGURATION
    #=========================================================================
    networkName = lib.mkOption {
      type = lib.types.str;
      default = "media-network";
      description = "Container network name for ARR services";
    };

    gpu = {
      enable = lib.mkEnableOption "GPU acceleration for ARR services";
    };

    #=========================================================================
    # INDIVIDUAL ARR SERVICES
    #=========================================================================
    sonarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable Sonarr TV series management";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/sonarr:latest";
        description = "Sonarr container image";
      };
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 8989;
        description = "Sonarr web interface port";
      };
      
      extraVolumes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional volume mounts for Sonarr";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables for Sonarr";
      };
    };

    radarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable Radarr movie management";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/radarr:latest";
        description = "Radarr container image";
      };
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 7878;
        description = "Radarr web interface port";
      };
      
      extraVolumes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional volume mounts for Radarr";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables for Radarr";
      };
    };

    lidarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable Lidarr music management";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/lidarr:latest";
        description = "Lidarr container image";
      };
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 8686;
        description = "Lidarr web interface port";
      };
      
      extraVolumes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional volume mounts for Lidarr";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables for Lidarr";
      };
    };

    prowlarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable Prowlarr indexer management";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/prowlarr:latest";
        description = "Prowlarr container image";
      };
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 9696;
        description = "Prowlarr web interface port";
      };
      
      extraVolumes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional volume mounts for Prowlarr";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables for Prowlarr";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION - ARR Container Services
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    
    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = paths.hot != null && paths.media != null;
        message = "ARR stack requires hwc.paths.hot and hwc.paths.media to be configured";
      }
      {
        assertion = config.hwc.security.secrets.arr;
        message = "ARR stack requires hwc.security.secrets.arr = true for API keys";
      }
    ];

    #=========================================================================
    # CONTAINER SERVICES
    #=========================================================================
    
    virtualisation.oci-containers.containers = {
      # Sonarr - TV Series Management
      sonarr = lib.mkIf cfg.sonarr.enable (buildArrContainer {
        name = "sonarr";
        image = cfg.sonarr.image;
        mediaType = "tv";
        port = cfg.sonarr.port;
      });

      # Radarr - Movie Management  
      radarr = lib.mkIf cfg.radarr.enable (buildArrContainer {
        name = "radarr";
        image = cfg.radarr.image;
        mediaType = "movies";
        port = cfg.radarr.port;
      });

      # Lidarr - Music Management
      lidarr = lib.mkIf cfg.lidarr.enable (buildArrContainer {
        name = "lidarr";
        image = cfg.lidarr.image;
        mediaType = "music";
        port = cfg.lidarr.port;
      });

      # Prowlarr - Indexer Management
      prowlarr = lib.mkIf cfg.prowlarr.enable {
        image = cfg.prowlarr.image;
        autoStart = true;
        extraOptions = [
          "--network=${cfg.networkName}"
          "--memory=1g" "--cpus=0.5" "--memory-swap=2g"
        ] ++ lib.optionals cfg.gpu.enable nvidiaGpuOptions;
        
        environment = mediaServiceEnv 
          // lib.optionalAttrs cfg.gpu.enable nvidiaEnv
          // cfg.prowlarr.extraEnvironment;
        
        ports = [ "127.0.0.1:${toString cfg.prowlarr.port}:${toString cfg.prowlarr.port}" ];
        
        volumes = [
          (configVol "prowlarr")
        ] ++ cfg.prowlarr.extraVolumes;
      };
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    
    # Ensure ARR services start after media network
    systemd.services = {
      "podman-sonarr".after = [ "hwc-media-network.service" ];
      "podman-radarr".after = [ "hwc-media-network.service" ];
      "podman-lidarr".after = [ "hwc-media-network.service" ];
      "podman-prowlarr".after = [ "hwc-media-network.service" ];
    };

    #=========================================================================
    # FIREWALL INTEGRATION
    #=========================================================================
    
    # Add ARR service ports to server firewall
    hwc.networking.firewall.extraTcpPorts = [
      cfg.sonarr.port    # 8989
      cfg.radarr.port    # 7878  
      cfg.lidarr.port    # 8686
      cfg.prowlarr.port  # 9696
    ];

    #=========================================================================
    # API KEY MANAGEMENT
    #=========================================================================
    
    # API key integration with agenix secrets
    # Keys will be available at runtime for service configuration
    systemd.services.arr-api-setup = lib.mkIf config.hwc.security.secrets.arr {
      description = "Setup ARR API keys from secrets";
      after = [ "age-install-secrets.service" ];
      wants = [ "age-install-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        # API keys are available in /run/agenix/ for manual configuration
        # This service ensures secrets are available before ARR services start
        echo "ARR API keys available for configuration"
      '';
    };

    # Ensure ARR containers start after API setup
    systemd.services."podman-sonarr".after = [ "arr-api-setup.service" ];
    systemd.services."podman-radarr".after = [ "arr-api-setup.service" ];
    systemd.services."podman-lidarr".after = [ "arr-api-setup.service" ];
    systemd.services."podman-prowlarr".after = [ "arr-api-setup.service" ];
  };
}
