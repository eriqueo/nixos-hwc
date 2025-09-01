# nixos-hwc/modules/services/media/downloaders.nix
#
# DOWNLOADERS - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.downloaders.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/media/downloaders.nix
#
# USAGE:
#   hwc.services.downloaders.enable = true;
#   # TODO: Add specific usage examples

# modules/services/media/downloaders.nix
#
# HWC Media Download Clients (Charter v3)
# qBittorrent, SABnzbd, SLSKD, and Soularr download services
#
# SOURCE FILES:
#   - /etc/nixos/hosts/server/modules/media-containers.nix (download containers)
#   - /etc/nixos/hosts/server/modules/media-containers.nix (soularr config)
#
# DEPENDENCIES:
#   Upstream: modules/services/media/networking.nix (VPN network)
#   Upstream: modules/security/secrets.nix (download service credentials)
#   Upstream: modules/system/paths.nix (storage paths)
#
# USED BY:
#   Downstream: profiles/server.nix (media server configuration)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../modules/services/media/downloaders.nix
#
# USAGE:
#   hwc.services.media.downloaders.enable = true;        # Enable all downloaders
#   hwc.services.media.downloaders.qbittorrent.enable = true;  # Individual services
#   hwc.services.media.downloaders.useVpn = true;        # Use VPN for downloads
#
# VALIDATION:
#   - Requires VPN network when useVpn is enabled
#   - Requires storage paths for downloads and media
#   - Requires secrets for service authentication

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.media.downloaders;
  paths = config.hwc.paths;
  
  # Helper functions from source
  configVol = service: "${paths.arr.downloads}/${service}:/config";
  
  # Standard environment for download services
  mediaServiceEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ = config.time.timeZone or "America/Denver";
  };

  # Network options - VPN or media network
  networkOptions = if cfg.useVpn 
    then [ "--network=container:gluetun" ]
    else [ "--network=${cfg.networkName}" ];

  # Download container builder (adapted from source buildDownloadContainer)
  buildDownloadContainer = { name, image, ports ? [], extraVolumes ? [], extraOptions ? [], environment ? {} }: {
    inherit image;
    autoStart = cfg.enable && cfg.${name}.enable;
    dependsOn = lib.optionals cfg.useVpn [ "gluetun" ];
    extraOptions = networkOptions ++ extraOptions ++ [
      "--memory=2g" "--cpus=1.0" "--memory-swap=4g"
    ];
    environment = mediaServiceEnv // environment;
    ports = if cfg.useVpn then [] else ports;  # VPN exposes ports
    volumes = [
      (configVol name)
      "${paths.hot}/downloads:/downloads"
    ] ++ extraVolumes;
  };
in {
  #============================================================================
  # OPTIONS - Download Services Configuration
  #============================================================================
  
  options.hwc.services.media.downloaders = {
    enable = lib.mkEnableOption "media download clients";

    #=========================================================================
    # NETWORK CONFIGURATION
    #=========================================================================
    useVpn = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Route download traffic through VPN container";
    };
    
    networkName = lib.mkOption {
      type = lib.types.str;
      default = "media-network";
      description = "Container network name when not using VPN";
    };

    #=========================================================================
    # QBITTORRENT TORRENT CLIENT
    #=========================================================================
    qbittorrent = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable qBittorrent torrent client";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/qbittorrent:latest";
        description = "qBittorrent container image";
      };
      
      webPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "qBittorrent web UI port";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };

    #=========================================================================
    # SABNZBD USENET CLIENT
    #=========================================================================
    sabnzbd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable SABnzbd usenet client";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/sabnzbd:latest";
        description = "SABnzbd container image";
      };
      
      webPort = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = "SABnzbd web UI port";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };

    #=========================================================================
    # SLSKD SOULSEEK CLIENT
    #=========================================================================
    slskd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable SLSKD Soulseek client";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "slskd/slskd:latest";
        description = "SLSKD container image";
      };
      
      webPort = lib.mkOption {
        type = lib.types.port;
        default = 5030;
        description = "SLSKD web UI port";
      };
      
      username = lib.mkOption {
        type = lib.types.str;
        default = "eriqueok";
        description = "SLSKD web username";
      };
      
      slskUsername = lib.mkOption {
        type = lib.types.str;
        default = "eriqueok";
        description = "Soulseek network username";
      };
      
      useSecrets = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use secrets for SLSKD passwords";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };

    #=========================================================================
    # SOULARR AUTOMATION
    #=========================================================================
    soularr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable && cfg.slskd.enable;
        description = "Enable Soularr automation for SLSKD/Lidarr";
      };
      
      image = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/mrusse08/soularr:latest";
        description = "Soularr container image";
      };
      
      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION - Download Container Services
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    
    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = !cfg.useVpn || config.hwc.services.media.networking.vpn.enable;
        message = "Download services with VPN require hwc.services.media.networking.vpn.enable = true";
      }
      {
        assertion = paths.hot != null;
        message = "Download services require hwc.paths.hot to be configured";
      }
    ];

    #=========================================================================
    # CONTAINER SERVICES
    #=========================================================================
    
    virtualisation.oci-containers.containers = {
      
      # qBittorrent - Torrent Downloads
      qbittorrent = lib.mkIf cfg.qbittorrent.enable (buildDownloadContainer {
        name = "qbittorrent";
        image = cfg.qbittorrent.image;
        ports = [ "127.0.0.1:${toString cfg.qbittorrent.webPort}:${toString cfg.qbittorrent.webPort}" ];
        environment = {
          WEBUI_PORT = toString cfg.qbittorrent.webPort;
        } // cfg.qbittorrent.extraEnvironment;
        extraVolumes = [
          "${paths.hot}/downloads/torrents:/downloads/torrents"
          "${paths.hot}/cache:/incomplete-downloads"
        ];
      });

      # SABnzbd - Usenet Downloads
      sabnzbd = lib.mkIf cfg.sabnzbd.enable (buildDownloadContainer {
        name = "sabnzbd";
        image = cfg.sabnzbd.image;
        ports = [ "127.0.0.1:${toString cfg.sabnzbd.webPort}:${toString cfg.sabnzbd.webPort}" ];
        environment = cfg.sabnzbd.extraEnvironment;
        extraVolumes = [
          "${paths.hot}/downloads/usenet:/downloads/usenet"
          "${paths.hot}/cache:/incomplete-downloads"
        ];
      });

      # SLSKD - Soulseek Downloads
      slskd = lib.mkIf cfg.slskd.enable {
        image = cfg.slskd.image;
        autoStart = true;
        extraOptions = networkOptions ++ [ "--memory=1g" "--cpus=0.5" ];
        environment = mediaServiceEnv // {
          SLSKD_USERNAME = cfg.slskd.username;
          SLSKD_SLSK_USERNAME = cfg.slskd.slskUsername;
          # Passwords will be set via secrets if enabled
        } // (if cfg.slskd.useSecrets then { } else {
          SLSKD_PASSWORD = "il0wwlm?";  # Fallback password
          SLSKD_SLSK_PASSWORD = "il0wwlm?";
        }) // cfg.slskd.extraEnvironment;
        ports = if cfg.useVpn then [ ] else [ "127.0.0.1:${toString cfg.slskd.webPort}:${toString cfg.slskd.webPort}" ];
        cmd = [ "--config" "/config/slskd.yml" ];
        volumes = [
          (configVol "slskd")
          "${paths.hot}/downloads/soulseek:/downloads"
          "${paths.media}/music:/data/music:ro"
          "${paths.media}/music-soulseek:/data/music-soulseek:ro"
          "${paths.media}/music:/data/downloads"
        ];
      };

      # Soularr - SLSKD/Lidarr Integration
      soularr = lib.mkIf cfg.soularr.enable {
        image = cfg.soularr.image;
        autoStart = true;
        dependsOn = [ "slskd" "lidarr" ];
        extraOptions = networkOptions ++ [ "--memory=1g" "--cpus=0.5" ];
        environment = cfg.soularr.extraEnvironment;
        volumes = [
          (configVol "soularr")
          "${paths.arr.downloads}/soularr:/data"
          "${paths.hot}/downloads:/downloads"
        ];
      };
    };

    #=========================================================================
    # CONFIGURATION SETUP SERVICES
    #=========================================================================
    
    # Soularr configuration from ARR API keys
    systemd.services.soularr-config = lib.mkIf cfg.soularr.enable {
      description = "Setup Soularr configuration from secrets";
      wantedBy = [ "podman-soularr.service" ];
      before = [ "podman-soularr.service" ];
      after = lib.optionals config.hwc.security.secrets.arr [ "age-install-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -e
        mkdir -p ${paths.arr.downloads}/soularr
        
        # Read API keys from secrets if available
        ${lib.optionalString config.hwc.security.secrets.arr ''
          LIDARR_API_KEY=$(cat ${config.age.secrets.lidarr-api-key.path} 2>/dev/null || echo "dummy-lidarr")
          SLSKD_API_KEY=$(cat ${config.age.secrets.slskd-api-key.path} 2>/dev/null || echo "dummy-slskd")
        ''}
        
        # Create Soularr configuration
        cat > "${paths.arr.downloads}/soularr/config.ini" <<EOF
        [Lidarr]
        host_url = http://lidarr:8686
        api_key = ''${LIDARR_API_KEY:-dummy-lidarr}
        download_dir = /downloads
        
        [Slskd]
        host_url = http://slskd:5030
        api_key = ''${SLSKD_API_KEY:-dummy-slskd}
        EOF
        
        echo "Soularr configuration created"
      '';
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    
    # Download services depend on network/VPN
    systemd.services = lib.mkMerge [
      # VPN dependencies
      (lib.mkIf cfg.useVpn {
        "podman-qbittorrent".after = [ "podman-gluetun.service" ];
        "podman-qbittorrent".wants = [ "podman-gluetun.service" ];
        "podman-sabnzbd".after = [ "podman-gluetun.service" ];
        "podman-sabnzbd".wants = [ "podman-gluetun.service" ];
        "podman-slskd".after = [ "podman-gluetun.service" ];
        "podman-slskd".wants = [ "podman-gluetun.service" ];
      })
      
      # Media network dependencies
      (lib.mkIf (!cfg.useVpn) {
        "podman-qbittorrent".after = [ "hwc-media-network.service" ];
        "podman-sabnzbd".after = [ "hwc-media-network.service" ];
        "podman-slskd".after = [ "hwc-media-network.service" ];
      })
    ];

    #=========================================================================
    # FIREWALL INTEGRATION
    #=========================================================================
    
    # Add download service ports when not using VPN
    hwc.networking.firewall.extraTcpPorts = lib.optionals (!cfg.useVpn) [
      cfg.qbittorrent.webPort  # 8080
      cfg.sabnzbd.webPort      # 8081
      cfg.slskd.webPort        # 5030
    ];
    
    # UDP ports for P2P
    hwc.networking.firewall.extraUdpPorts = lib.optionals (!cfg.useVpn) [
      50300  # SLSKD P2P
    ];
  };
}