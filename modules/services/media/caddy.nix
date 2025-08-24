# nixos-hwc/modules/services/network/caddy.nix
#
# Caddy Reverse Proxy
# Provides HTTPS reverse proxy and automatic certificate management
#
# DEPENDENCIES:
#   Upstream: config.hwc.services.jellyfin (modules/services/media/jellyfin.nix) [optional]
#   Upstream: config.hwc.services.sonarr (modules/services/media/sonarr.nix) [optional]
#   Upstream: config.hwc.services.radarr (modules/services/media/radarr.nix) [optional]
#   Upstream: config.hwc.services.prowlarr (modules/services/media/prowlarr.nix) [optional]
#   Upstream: config.hwc.services.lidarr (modules/services/media/lidarr.nix) [optional]
#   Upstream: config.hwc.services.qbittorrent (modules/services/utility/qbittorrent.nix) [optional]
#
# USED BY:
#   Downstream: profiles/media.nix (enables reverse proxy for media services)
#   Downstream: machines/server/config.nix (may override domain settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/network/caddy.nix
#   - Any machine using reverse proxy
#
# USAGE:
#   hwc.services.caddy.enable = true;
#   hwc.services.caddy.domain = "hwc.example.com";
#   hwc.services.caddy.enableMediaServices = true;
#
# VALIDATION:
#   - Domain must be configured for external access
#   - Ports 80 and 443 must be available

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.caddy;
  services = config.hwc.services;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";
    
    # Core settings
    domain = lib.mkOption {
      type = lib.types.str;
      default = "hwc.local";
      description = "Primary domain for reverse proxy";
    };
    
    enableAutoHttps = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic HTTPS with Let's Encrypt";
    };
    
    # Service integration toggles
    enableMediaServices = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable reverse proxy for media services (ARR stack, Jellyfin)";
    };
    
    enableDownloadClients = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable reverse proxy for download clients (qBittorrent, SABnzbd)";
    };
    
    enableMonitoring = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable reverse proxy for monitoring services (Grafana, Prometheus)";
    };
    
    # Custom routes
    customRoutes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Custom reverse proxy routes (path -> upstream)";
      example = {
        "/custom" = "localhost:8080";
        "/api" = "localhost:3000";
      };
    };
    
    # Security settings
    enableBasicAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable basic authentication for all routes";
    };
    
    basicAuthUsers = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Basic auth users (username -> bcrypt hash)";
      example = {
        admin = "$2a$14$..."; # bcrypt hash
      };
    };
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation: Check required dependencies
    assertions = [
      {
        assertion = cfg.domain != "";
        message = "Caddy requires a domain to be configured";
      }
    ];
    
    # Enable Caddy service
    services.caddy = {
      enable = true;
      
      virtualHosts."${cfg.domain}" = {
        extraConfig = ''
          # Global settings
          ${lib.optionalString cfg.enableBasicAuth ''
            basicauth {
              ${lib.concatStringsSep "\n    " (lib.mapAttrsToList (user: hash: "${user} ${hash}") cfg.basicAuthUsers)}
            }
          ''}
          
          # Media Services
          ${lib.optionalString (cfg.enableMediaServices && services.jellyfin.enable or false) ''
            # Jellyfin media server
            handle_path /media/* {
              reverse_proxy localhost:${toString services.jellyfin.port}
            }
          ''}
          
          ${lib.optionalString (cfg.enableMediaServices && services.sonarr.enable or false) ''
            # Sonarr TV management
            handle /sonarr { redir /sonarr/ 301 }
            route /sonarr* {
              reverse_proxy localhost:${toString services.sonarr.port} {
                header_up Host {host}
                header_up X-Forwarded-Host {host}
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-Port {server_port}
                header_up X-Forwarded-For {remote}
                header_up X-Real-IP {remote}
              }
            }
          ''}
          
          ${lib.optionalString (cfg.enableMediaServices && services.radarr.enable or false) ''
            # Radarr movie management
            handle /radarr { redir /radarr/ 301 }
            route /radarr* {
              reverse_proxy localhost:${toString services.radarr.port} {
                header_up Host {host}
                header_up X-Forwarded-Host {host}
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-Port {server_port}
                header_up X-Forwarded-For {remote}
                header_up X-Real-IP {remote}
              }
            }
          ''}
          
          ${lib.optionalString (cfg.enableMediaServices && services.lidarr.enable or false) ''
            # Lidarr music management
            handle /lidarr { redir /lidarr/ 301 }
            route /lidarr* {
              reverse_proxy localhost:${toString services.lidarr.port} {
                header_up Host {host}
                header_up X-Forwarded-Host {host}
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-Port {server_port}
                header_up X-Forwarded-For {remote}
                header_up X-Real-IP {remote}
              }
            }
          ''}
          
          ${lib.optionalString (cfg.enableMediaServices && services.prowlarr.enable or false) ''
            # Prowlarr indexer management
            handle /prowlarr { redir /prowlarr/ 301 }
            route /prowlarr* {
              reverse_proxy localhost:${toString services.prowlarr.port} {
                header_up Host {host}
                header_up X-Forwarded-Host {host}
                header_up X-Forwarded-Proto {scheme}
                header_up X-Forwarded-Port {server_port}
                header_up X-Forwarded-For {remote}
                header_up X-Real-IP {remote}
              }
            }
          ''}
          
          # Download Clients (VPN-routed)
          ${lib.optionalString (cfg.enableDownloadClients && services.qbittorrent.enable or false) ''
            # qBittorrent torrent client
            handle_path /qbt/* {
              reverse_proxy localhost:${toString services.qbittorrent.webPort}
            }
          ''}
          
          ${lib.optionalString (cfg.enableDownloadClients && services.sabnzbd.enable or false) ''
            # SABnzbd usenet client
            handle_path /sab/* {
              reverse_proxy localhost:8081
            }
          ''}
          
          # Monitoring Services
          ${lib.optionalString (cfg.enableMonitoring && services.grafana.enable or false) ''
            # Grafana dashboards
            handle_path /grafana/* {
              reverse_proxy localhost:${toString services.grafana.port}
            }
          ''}
          
          ${lib.optionalString (cfg.enableMonitoring && services.prometheus.enable or false) ''
            # Prometheus metrics
            handle_path /prometheus/* {
              reverse_proxy localhost:${toString services.prometheus.port}
            }
          ''}
          
          # Custom Routes
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: upstream: ''
            handle_path ${path}/* {
              reverse_proxy ${upstream}
            }
          '') cfg.customRoutes)}
          
          # Default response for unmatched routes
          respond "HWC Server - Service not found" 404
        '';
      };
    };
    
    # Firewall configuration
    networking.firewall = {
      allowedTCPPorts = [ 80 443 ];
      
      # Allow Tailscale interface access to internal services
      interfaces."tailscale0" = {
        allowedTCPPorts = [
          # Media services
          (services.jellyfin.port or 8096)
          (services.sonarr.port or 8989)
          (services.radarr.port or 7878)
          (services.lidarr.port or 8686)
          (services.prowlarr.port or 9696)
          
          # Download clients
          (services.qbittorrent.webPort or 8080)
          8081  # SABnzbd
          
          # Monitoring
          (services.grafana.port or 3000)
          (services.prometheus.port or 9090)
        ];
      };
    };
    
    # Health check service
    systemd.services.caddy-health = {
      description = "Caddy reverse proxy health check";
      after = [ "caddy.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost/";
        RemainAfterExit = true;
      };
      
      startAt = "*:0/5"; # Every 5 minutes
    };
    
    # Log rotation for Caddy
    services.logrotate.settings = {
      "/var/log/caddy/*.log" = {
        frequency = "daily";
        rotate = 7;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        create = "644 caddy caddy";
        postrotate = "systemctl reload caddy";
      };
    };
  };
}

