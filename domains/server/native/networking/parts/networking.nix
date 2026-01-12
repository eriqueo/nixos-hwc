# HWC Charter Module/domains/services/media/networking.nix
#
# NETWORKING - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.server.networking.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/media/networking.nix
#
# USAGE:
#   hwc.server.networking.enable = true;
#   # TODO: Add specific usage examples

# modules/services/media/networking.nix
#
# HWC Media Services Networking (Charter v3)
# VPN networking and container network management for media services
#
# SOURCE FILES:
#   - /etc/nixos/hosts/serv../domains/media-containers.nix (VPN + networking setup)
#   - /etc/nixos/hosts/serv../domains/media-core.nix (media network creation)
#
# DEPENDENCIES:
#   Upstream: modules/security/secrets.nix (VPN credentials)
#   Upstream: modules/system/networking.nix (base networking)
#
# USED BY:
#   Downstream: modules/services/media/downloaders.nix (VPN for downloads)
#   Downstream: modules/services/media/arr-stack.nix (media network)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../domains/services/media/networking.nix
#
# USAGE:
#   hwc.server.media.networking.enable = true;      # Enable media networking
#   hwc.server.media.networking.vpn.enable = true;  # Enable VPN for downloads
#   hwc.server.media.networking.mediaNetwork = "media-network";
#
# VALIDATION:
#   - Requires hwc.secrets.secrets.vpn = true for VPN credentials
#   - Creates container networks before dependent services

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.media.networking;
in {
  #============================================================================
  # IMPLEMENTATION - Media Networking Services
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    
    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = !cfg.vpn.enable || config.hwc.secrets.secrets.vpn;
        message = "VPN requires hwc.secrets.secrets.vpn = true for credentials";
      }
    ];

    #=========================================================================
    # MEDIA CONTAINER NETWORK CREATION
    #=========================================================================
    
    # Create media network before any media services start
    systemd.services.hwc-media-network = {
      description = "Create HWC media container network";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = let 
        podman = "${pkgs.podman}/bin/podman";
        networkName = cfg.mediaNetwork.name;
      in ''
        set -e
        # Check if network already exists
        if ! ${podman} network exists ${networkName}; then
          echo "Creating media network: ${networkName}"
          ${podman} network create \
            --driver ${cfg.mediaNetwork.driver} \
            --subnet ${cfg.mediaNetwork.subnet} \
            ${networkName}
        else
          echo "Media network ${networkName} already exists"
        fi
      '';
    };

    #=========================================================================
    # VPN CONTAINER (GLUETUN)
    #=========================================================================
    
    virtualisation.oci-containers.containers.gluetun = lib.mkIf cfg.vpn.enable {
      image = cfg.vpn.image;
      autoStart = true;
      
      # Privileged mode required for VPN functionality
      extraOptions = [
        "--privileged"
        "--network=${cfg.mediaNetwork.name}"
        "--device=/dev/net/tun:/dev/net/tun"
        "--cap-add=NET_ADMIN"
        "--memory=512m" "--cpus=0.5"
      ];
      
      # VPN configuration from agenix secrets
      environment = {
        VPN_SERVICE_PROVIDER = cfg.vpn.provider;
        VPN_TYPE = "openvpn";
        SERVER_COUNTRIES = lib.concatStringsSep "," cfg.vpn.serverCountries;
        HEALTH_VPN_DURATION_INITIAL = "30s";
        FIREWALL_VPN_INPUT_PORTS = lib.concatMapStringsSep "," toString cfg.firewall.vpnPorts;
        TZ = config.time.timeZone or "America/Denver";
      } // cfg.vpn.extraEnvironment;
      
      # Expose download client ports through VPN
      ports = map (port: "127.0.0.1:${toString port}:${toString port}") cfg.firewall.vpnPorts;
      
      # VPN credentials from agenix secrets
      environmentFiles = lib.optionals config.hwc.secrets.secrets.vpn [
        config.age.secrets.vpn-credentials.path  # Will be created by setup service
      ];
    };

    #=========================================================================
    # VPN CREDENTIALS SETUP
    #=========================================================================
    
    # Create VPN credentials file from agenix secrets
    systemd.services.gluetun-env-setup = lib.mkIf (cfg.vpn.enable && config.hwc.secrets.secrets.vpn) {
      description = "Setup Gluetun VPN credentials from agenix";
      before = [ "podman-gluetun.service" ];
      wantedBy = [ "podman-gluetun.service" ];
      wants = [ "age-install-secrets.service" ];
      after = [ "age-install-secrets.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        # Read VPN credentials from agenix secrets
        VPN_USERNAME=$(cat ${config.age.secrets.vpn-username.path})
        VPN_PASSWORD=$(cat ${config.age.secrets.vpn-password.path})
        
        # Create environment file for Gluetun
        cat > /run/agenix/vpn-credentials <<EOF
        OPENVPN_USER=$VPN_USERNAME
        OPENVPN_PASSWORD=$VPN_PASSWORD
        EOF
        
        chmod 600 /run/agenix/vpn-credentials
        echo "VPN credentials configured for Gluetun"
      '';
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    
    # Ensure VPN container starts after network and secrets
    systemd.services."podman-gluetun" = lib.mkIf cfg.vpn.enable {
      after = [ "hwc-media-network.service" "gluetun-env-setup.service" ];
      wants = [ "hwc-media-network.service" ];
    };

    #=========================================================================
    # FIREWALL INTEGRATION  
    #=========================================================================
    
    # Add VPN and media service ports to firewall
    hwc.networking.firewall = lib.mkIf cfg.firewall.allowMediaPorts {
      extraTcpPorts = cfg.firewall.vpnPorts;
    };

    #=========================================================================
    # CONTAINER NETWORK CLEANUP
    #=========================================================================
    
    # Service to clean up media network on shutdown
    systemd.services.hwc-media-network-cleanup = {
      description = "Cleanup HWC media container network";
      before = [ "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/bin/true";  # Do nothing on start
        ExecStop = let 
          podman = "${pkgs.podman}/bin/podman";
        in "${podman} network rm ${cfg.mediaNetwork.name} || true";
        TimeoutStopSec = "30s";
      };
    };

    #=========================================================================
    # MONITORING AND HEALTH CHECKS
    #=========================================================================
    
    # VPN health monitoring service
    systemd.services.gluetun-health-check = lib.mkIf cfg.vpn.enable {
      description = "Monitor Gluetun VPN health";
      after = [ "podman-gluetun.service" ];
      wants = [ "podman-gluetun.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = let
          podman = "${pkgs.podman}/bin/podman";
        in pkgs.writeScript "gluetun-health-check" ''
          #!/bin/bash
          
          # Check if Gluetun container is running
          if ! ${podman} inspect gluetun --format '{{.State.Running}}' | grep -q true; then
            echo "Gluetun container is not running"
            exit 1
          fi
          
          # Check VPN connectivity
          if ! ${podman} exec gluetun wget -q --spider http://httpbin.org/ip; then
            echo "VPN connectivity check failed"
            exit 1
          fi
          
          echo "Gluetun VPN is healthy"
        '';
      };
    };

    # Run health check every 5 minutes
    systemd.timers.gluetun-health-check = lib.mkIf cfg.vpn.enable {
      description = "Run Gluetun health check every 5 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";  # Every 5 minutes
        Persistent = true;
      };
    };
  };
}
