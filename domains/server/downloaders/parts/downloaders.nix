# HWC Charter Module/domains/services/media/downloaders.nix
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
#   - profiles/profile.nix: ../domains/services/media/downloaders.nix
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
#   - /etc/nixos/hosts/serv../domains/media-containers.nix (download containers)
#   - /etc/nixos/hosts/serv../domains/media-containers.nix (soularr config)
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
#   - profiles/server.nix: ../domains/services/media/downloaders.nix
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
    PGID = "100";
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
    
    # Container definitions moved to individual service modules:
    # - qBittorrent: modules/services/media/qbittorrent.nix
    # - SABnzbd: modules/services/media/sabnzbd.nix (TODO: create)
    # - SLSKD: modules/services/media/slskd.nix (TODO: implement)
    # - Soularr: modules/services/media/soularr.nix (TODO: implement)
    # Enable individual services in profiles/

    #=========================================================================
    # CONFIGURATION SETUP SERVICES
    #=========================================================================
    
    # Soularr configuration from ARR API keys
    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    
    # Download services depend on network/VPN
    systemd.services = lib.mkMerge [
      # Soularr configuration service
      (lib.mkIf cfg.soularr.enable {
        soularr-config = {
          description = "Setup Soularr configuration from secrets";
          wantedBy = [ "podman-soularr.service" ];
          before = [ "podman-soularr.service" ];
          after = lib.optionals config.hwc.secrets.secrets.arr [ "age-install-secrets.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            set -e
            mkdir -p ${paths.arr.downloads}/soularr
            
            # Read API keys from secrets if available  
            LIDARR_API_KEY="dummy-lidarr"
            SLSKD_API_KEY="dummy-slskd"
            ${lib.optionalString config.hwc.secrets.secrets.arr ''
              if [ -f "${config.age.secrets.lidarr-api-key.path}" ]; then
                LIDARR_API_KEY=$(cat ${config.age.secrets.lidarr-api-key.path})
              fi
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
      })
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
