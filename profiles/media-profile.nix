# nixos-hwc/profiles/media.nix
#
# Media Server Profile
# Enables complete media automation stack with GPU acceleration
#
# DEPENDENCIES:
#   Upstream: modules/services/media/jellyfin.nix
#   Upstream: modules/services/media/sonarr.nix
#   Upstream: modules/services/media/radarr.nix
#   Upstream: modules/services/media/lidarr.nix
#   Upstream: modules/services/media/prowlarr.nix
#   Upstream: modules/services/utility/qbittorrent.nix
#   Upstream: modules/services/network/gluetun.nix
#   Upstream: modules/services/network/caddy.nix
#   Upstream: modules/infrastructure/hardware/gpu.nix
#   Upstream: modules/system/paths.nix
#
# USED BY:
#   Downstream: machines/server/config.nix
#
# IMPORTS REQUIRED IN:
#   - machines/server/config.nix: ../profiles/media.nix
#
# USAGE:
#   Import this profile to enable complete media automation stack
#   Override individual service settings in machine configuration
#
# PROVIDES:
#   - Jellyfin media server with GPU transcoding
#   - Complete ARR stack (Sonarr, Radarr, Lidarr, Prowlarr)
#   - VPN-protected download clients
#   - Reverse proxy with HTTPS

{ config, lib, ... }:

{
  imports = [
    # Media services
    ../modules/services/media/jellyfin.nix
    ../modules/services/media/sonarr.nix
    ../modules/services/media/radarr.nix
    ../modules/services/media/lidarr.nix
    ../modules/services/media/prowlarr.nix
    
    # Download and networking
    ../modules/services/utility/qbittorrent.nix
    ../modules/services/network/gluetun.nix
    ../modules/services/network/caddy.nix
    
    # System dependencies
    ../modules/system/gpu.nix
    ../modules/system/paths.nix
    # Media packages removed - duplicates consolidated into packages/base.nix and packages/server.nix
  ];
  
  config = {
    #==========================================================================
    # MEDIA SERVICES - Core media automation stack
    #==========================================================================
    
    # Jellyfin media server with GPU acceleration
    hwc.services.jellyfin = {
      enable = lib.mkDefault true;
      enableGpu = lib.mkDefault true;
      port = lib.mkDefault 8096;
    };
    
    # ARR Stack - Automated media management
    hwc.services.sonarr = {
      enable = lib.mkDefault true;
      port = lib.mkDefault 8989;
      urlBase = lib.mkDefault "/sonarr";
    };
    
    hwc.services.radarr = {
      enable = lib.mkDefault true;
      port = lib.mkDefault 7878;
      urlBase = lib.mkDefault "/radarr";
    };
    
    hwc.services.lidarr = {
      enable = lib.mkDefault true;
      port = lib.mkDefault 8686;
      urlBase = lib.mkDefault "/lidarr";
    };
    
    hwc.services.prowlarr = {
      enable = lib.mkDefault true;
      port = lib.mkDefault 9696;
      urlBase = lib.mkDefault "/prowlarr";
    };
    
    #==========================================================================
    # DOWNLOAD CLIENTS - VPN-protected downloading
    #==========================================================================
    
    # VPN gateway for secure downloading
    hwc.services.gluetun = {
      enable = lib.mkDefault true;
      vpnProvider = lib.mkDefault "protonvpn";
      serverCountries = lib.mkDefault [ "Netherlands" ];
      exposePorts = lib.mkDefault {
        qbittorrent = 8080;
        sabnzbd = 8081;
      };
    };
    
    # qBittorrent torrent client
    hwc.services.qbittorrent = {
      enable = lib.mkDefault true;
      useVpn = lib.mkDefault true;
      webPort = lib.mkDefault 8080;
    };
    
    #==========================================================================
    # REVERSE PROXY - External access and HTTPS
    #==========================================================================
    
    # Caddy reverse proxy with automatic HTTPS
    hwc.services.caddy = {
      enable = lib.mkDefault true;
      enableMediaServices = lib.mkDefault true;
      enableDownloadClients = lib.mkDefault true;
      domain = lib.mkDefault "hwc.local";
    };
    
    #==========================================================================
    # GPU ACCELERATION - Hardware transcoding support
    #==========================================================================
    
    # GPU configuration (type set by machine)
    hwc.infrastructure.hardware.gpu = {
      nvidia = {
        containerRuntime = lib.mkDefault true;
        enableMonitoring = lib.mkDefault true;
      };
    };
    
    #==========================================================================
    # CONTAINER RUNTIME - Required for all services
    #==========================================================================
    
    # Enable container runtime
    virtualisation = {
      docker.enable = lib.mkDefault false;  # Use Podman instead
      podman = {
        enable = lib.mkDefault true;
        dockerCompat = lib.mkDefault true;
        defaultNetwork.settings.dns_enabled = lib.mkDefault true;
      };
      oci-containers.backend = lib.mkDefault "podman";
    };
    
    #==========================================================================
    # NETWORKING - Container networking and firewall
    #==========================================================================
    
    # Firewall configuration
    networking.firewall = {
      enable = lib.mkDefault true;
      
      # Public access (via Caddy)
      allowedTCPPorts = lib.mkDefault [ 80 443 ];
      
      # Tailscale interface access
      interfaces."tailscale0" = {
        allowedTCPPorts = lib.mkDefault [
          8096  # Jellyfin
          8989  # Sonarr
          7878  # Radarr
          8686  # Lidarr
          9696  # Prowlarr
          8080  # qBittorrent
          8081  # SABnzbd
        ];
      };
    };
    
    #==========================================================================
    # SYSTEM PACKAGES - Useful tools for media management
    #==========================================================================
    
    # Media packages moved to modules/system/media-packages.nix
    hwc.system.mediaPackages.enable = true;
    
    #==========================================================================
    # USERS AND GROUPS - Consistent permissions
    #==========================================================================
    
    # Create media group for shared access
    users.groups.media = {
      gid = 1000;
    };
    
    # Ensure all media services use consistent UID/GID
    users.users = {
      jellyfin.extraGroups = [ "media" ];
      sonarr.extraGroups = [ "media" ];
      radarr.extraGroups = [ "media" ];
      lidarr.extraGroups = [ "media" ];
      prowlarr.extraGroups = [ "media" ];
      qbittorrent.extraGroups = [ "media" ];
    };
  };
}

