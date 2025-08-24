# nixos-hwc/modules/services/network/gluetun.nix
#
# Gluetun VPN Gateway
# Provides VPN connectivity for download clients and other services
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.storage.hot (modules/system/paths.nix)
#   Upstream: config.hwc.secrets.vpn_username (secrets management)
#   Upstream: config.hwc.secrets.vpn_password (secrets management)
#   Upstream: config.time.timeZone (system configuration)
#
# USED BY:
#   Downstream: modules/services/utility/qbittorrent.nix (routes through VPN)
#   Downstream: modules/services/utility/sabnzbd.nix (routes through VPN)
#   Downstream: profiles/media.nix (enables VPN for downloaders)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/network/gluetun.nix
#   - Any machine using VPN routing
#
# USAGE:
#   hwc.services.gluetun.enable = true;
#   hwc.services.gluetun.vpnProvider = "protonvpn";
#   hwc.services.gluetun.serverCountries = [ "Netherlands" ];
#   hwc.services.gluetun.exposePorts = { qbittorrent = 8080; sabnzbd = 8081; };
#
# VALIDATION:
#   - Requires hwc.paths.storage.hot to be configured
#   - Requires VPN credentials to be configured
#   - Requires NET_ADMIN capability

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.gluetun;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.gluetun = {
    enable = lib.mkEnableOption "Gluetun VPN gateway";
    
    # VPN settings
    vpnProvider = lib.mkOption {
      type = lib.types.str;
      default = "protonvpn";
      description = "VPN service provider";
    };
    
    vpnType = lib.mkOption {
      type = lib.types.enum [ "openvpn" "wireguard" ];
      default = "openvpn";
      description = "VPN protocol type";
    };
    
    serverCountries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Netherlands" ];
      description = "Preferred VPN server countries";
    };
    
    # Port exposure for services using VPN
    exposePorts = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = {
        qbittorrent = 8080;
        sabnzbd = 8081;
      };
      description = "Ports to expose for services using VPN";
    };
    
    # Path settings (use centralized paths)
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/gluetun";
      description = "Data directory for Gluetun";
    };
    
    configDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/config";
      description = "Configuration directory for environment files";
    };
    
    # Container settings
    image = lib.mkOption {
      type = lib.types.str;
      default = "qmcgaw/gluetun:latest";
      description = "Container image to use";
    };
    
    # Network settings
    networkName = lib.mkOption {
      type = lib.types.str;
      default = "media-network";
      description = "Container network name";
    };
    
    # Health check settings
    healthCheckDuration = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "Initial VPN health check duration";
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
        message = "Gluetun requires hwc.paths.storage.hot to be configured";
      }
      {
        assertion = config.sops.secrets.vpn_username.path or null != null;
        message = "Gluetun requires VPN username secret to be configured";
      }
      {
        assertion = config.sops.secrets.vpn_password.path or null != null;
        message = "Gluetun requires VPN password secret to be configured";
      }
    ];
    
    # Environment file generation service
    systemd.services.gluetun-env-setup = {
      description = "Generate Gluetun environment from secrets";
      before = [ "podman-gluetun.service" ];
      wantedBy = [ "podman-gluetun.service" ];
      wants = [ "sops-install-secrets.service" ];
      after = [ "sops-install-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Ensure config directory exists
        mkdir -p ${cfg.configDir}
        
        # Read VPN credentials from secrets
        VPN_USERNAME=$(cat ${config.sops.secrets.vpn_username.path})
        VPN_PASSWORD=$(cat ${config.sops.secrets.vpn_password.path})
        
        # Generate environment file
        cat > ${cfg.configDir}/.env << EOF
VPN_SERVICE_PROVIDER=${cfg.vpnProvider}
VPN_TYPE=${cfg.vpnType}
OPENVPN_USER=$VPN_USERNAME
OPENVPN_PASSWORD=$VPN_PASSWORD
SERVER_COUNTRIES=${lib.concatStringsSep "," cfg.serverCountries}
HEALTH_VPN_DURATION_INITIAL=${cfg.healthCheckDuration}
EOF
        
        # Set secure permissions
        chmod 600 ${cfg.configDir}/.env
        chown root:root ${cfg.configDir}/.env
        
        echo "Gluetun environment file generated successfully"
      '';
    };
    
    # Container service
    virtualisation.oci-containers.containers.gluetun = {
      image = cfg.image;
      autoStart = true;
      
      # Expose ports for services using VPN
      ports = lib.mapAttrsToList (service: port: "127.0.0.1:${toString port}:${toString port}") cfg.exposePorts;
      
      volumes = [
        "${cfg.dataDir}:/gluetun"
      ];
      
      environment = {
        TZ = config.time.timeZone;
      };
      
      environmentFiles = [ "${cfg.configDir}/.env" ];
      
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun:/dev/net/tun"
        "--network=${cfg.networkName}"
        "--network-alias=gluetun"
      ];
    };
    
    # Directory creation
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 gluetun gluetun -"
      "d ${cfg.configDir} 0755 root root -"
    ];
    
    # Create gluetun user and group
    users.users.gluetun = {
      isSystemUser = true;
      group = "gluetun";
      uid = 1000;
    };
    
    users.groups.gluetun = {
      gid = 1000;
    };
    
    # Network creation service
    systemd.services.init-media-network = {
      description = "Create media network for Gluetun";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = let podman = "${pkgs.podman}/bin/podman"; in ''
        if ! ${podman} network ls --format "{{.Name}}" | grep -qx ${cfg.networkName}; then
          ${podman} network create ${cfg.networkName}
          echo "Created ${cfg.networkName} network"
        else
          echo "${cfg.networkName} network already exists"
        fi
      '';
    };
    
    # Ensure proper service ordering
    systemd.services."podman-gluetun" = {
      after = [ "network-online.target" "init-media-network.service" "gluetun-env-setup.service" ];
      wants = [ "network-online.target" ];
    };
    
    # Health check service
    systemd.services.gluetun-health = {
      description = "Gluetun VPN health check";
      after = [ "podman-gluetun.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "gluetun-health" ''
          # Check if Gluetun container is running
          if ${pkgs.podman}/bin/podman ps --format "{{.Names}}" | grep -q "gluetun"; then
            # Check VPN status via Gluetun API
            ${pkgs.curl}/bin/curl -f http://localhost:8000/v1/openvpn/status || exit 1
            echo "Gluetun VPN is healthy"
          else
            echo "Gluetun container is not running"
            exit 1
          fi
        '';
        RemainAfterExit = true;
      };
      
      startAt = "*:0/2"; # Every 2 minutes
    };
    
    # Firewall configuration - only expose VPN-routed services
    networking.firewall.allowedTCPPorts = lib.attrValues cfg.exposePorts;
  };
}

