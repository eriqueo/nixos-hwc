# nixos-hwc/modules/services/utility/qbittorrent.nix
#
# qBittorrent Download Client
# Provides torrent downloading with VPN integration
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.storage.hot (modules/system/paths.nix)
#   Upstream: config.hwc.services.gluetun (modules/services/network/gluetun.nix)
#   Upstream: config.hwc.paths.cache.media (modules/system/paths.nix)
#
# USED BY:
#   Downstream: profiles/media.nix (enables this service)
#   Downstream: modules/services/media/sonarr.nix (uses as download client)
#   Downstream: modules/services/media/radarr.nix (uses as download client)
#   Downstream: machines/server/config.nix (may override settings)
#
# IMPORTS REQUIRED IN:
#   - profiles/media.nix: ../modules/services/utility/qbittorrent.nix
#   - Any machine using qBittorrent
#
# USAGE:
#   hwc.services.qbittorrent.enable = true;
#   hwc.services.qbittorrent.useVpn = true;
#   hwc.services.qbittorrent.webPort = 8080;
#
# VALIDATION:
#   - Requires hwc.paths.storage.hot to be configured
#   - VPN mode requires gluetun service to be enabled

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.qbittorrent;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.services.qbittorrent = {
    enable = lib.mkEnableOption "qBittorrent torrent client";
    
    # Core settings
    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Web interface port";
    };
    
    useVpn = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Route traffic through VPN (requires gluetun)";
    };
    
    # Path settings (use centralized paths)
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/qbittorrent";
      description = "Data directory for qBittorrent";
    };
    
    downloadsDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.storage.hot}/downloads";
      description = "Downloads directory";
    };
    
    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.cache.media}/qbittorrent";
      description = "Cache directory for incomplete downloads";
    };
    
    # Container settings
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/qbittorrent";
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
        message = "qBittorrent requires hwc.paths.storage.hot to be configured";
      }
      {
        assertion = cfg.useVpn -> config.hwc.services.gluetun.enable or false;
        message = "qBittorrent VPN mode requires hwc.services.gluetun.enable = true";
      }
    ];
    
    # Container service
    virtualisation.oci-containers.containers.qbittorrent = {
      image = cfg.image;
      autoStart = true;
      
      # Only expose ports if not using VPN (gluetun handles port exposure)
      ports = lib.optionals (!cfg.useVpn) [ "127.0.0.1:${toString cfg.webPort}:8080" ];
      
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.downloadsDir}:/downloads"
        "${cfg.cacheDir}:/incomplete-downloads"
        "${paths.storage.media}:/cold-media"
      ];
      
      environment = {
        TZ = config.time.timeZone;
        PUID = "1000";
        PGID = "1000";
        WEBUI_PORT = toString cfg.webPort;
      };
      
      extraOptions = [
        "--memory=${cfg.memory}"
        "--cpus=${cfg.cpus}"
        "--memory-swap=${cfg.memory}"
      ] ++ (if cfg.useVpn then [
        "--network=container:gluetun"
      ] else [
        "--network=${cfg.networkName}"
      ]);
      
      # Depend on gluetun if using VPN
      dependsOn = lib.optionals cfg.useVpn [ "gluetun" ];
    };
    
    # Directory creation
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 qbittorrent qbittorrent -"
      "d ${cfg.downloadsDir} 0755 qbittorrent qbittorrent -"
      "d ${cfg.cacheDir} 0755 qbittorrent qbittorrent -"
    ];
    
    # Create qbittorrent user and group
    users.users.qbittorrent = {
      isSystemUser = true;
      group = "qbittorrent";
      uid = 1000;
    };
    
    users.groups.qbittorrent = {
      gid = 1000;
    };
    
    # Configuration seeding service
    systemd.services.qbittorrent-config = {
      description = "Seed qBittorrent configuration";
      before = [ "podman-qbittorrent.service" ];
      wantedBy = [ "podman-qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Ensure qBittorrent config directory exists
        mkdir -p ${cfg.dataDir}/qBittorrent/config
        
        # Create basic qBittorrent.conf
        if [ ! -f ${cfg.dataDir}/qBittorrent/config/qBittorrent.conf ]; then
          cat > ${cfg.dataDir}/qBittorrent/config/qBittorrent.conf << 'CONFIG_EOF'
[Application]
FileLogger\Enabled=true
FileLogger\Path=/config/qBittorrent/logs
FileLogger\Backup=true
FileLogger\MaxSizeBytes=66560
FileLogger\DeleteOld=true
FileLogger\MaxOldFiles=99

[BitTorrent]
Session\DefaultSavePath=/downloads
Session\TempPath=/incomplete-downloads
Session\Port=6881
Session\Interface=
Session\InterfaceName=
Session\UseOSCache=true
Session\DiskWriteCacheSize=64
Session\DiskWriteCacheTTL=60

[Preferences]
WebUI\Port=${toString cfg.webPort}
WebUI\Address=*
WebUI\LocalHostAuth=false
WebUI\AuthSubnetWhitelistEnabled=false
WebUI\Username=admin
WebUI\Password_PBKDF2="@ByteArray(ARQ77eY1NUZaQsuDHbIMCA==:0WMRkYTUWVT9wVvdDtHAjU9b3b7uB8NR1Gur2hmQCvCDpm39Q+PsJRJPaCU51dEiz+dTzh8qbPsL8WkFljQYFQ==)"
WebUI\CSRFProtection=true
WebUI\ClickjackingProtection=true
WebUI\SecureCookie=true
WebUI\MaxAuthenticationFailCount=5
WebUI\BanDuration=3600
WebUI\SessionTimeout=3600
WebUI\AlternativeUIEnabled=false
WebUI\RootFolder=
WebUI\HTTPS\Enabled=false
Downloads\SavePath=/downloads
Downloads\TempPath=/incomplete-downloads
Downloads\ScanDirsV2=@Variant(\0\0\0\x1c\0\0\0\0)
Downloads\TorrentExportDir=
Downloads\FinishedTorrentExportDir=
General\Locale=en
MailNotification\enabled=false
CONFIG_EOF
        fi
        
        # Set proper ownership and permissions
        chown -R qbittorrent:qbittorrent ${cfg.dataDir}
        chmod -R 755 ${cfg.dataDir}
        
        echo "qBittorrent configuration seeded successfully"
      '';
    };
    
    # Firewall configuration (only if not using VPN)
    networking.firewall.allowedTCPPorts = lib.mkIf (!cfg.useVpn) [ cfg.webPort ];
    
    # Health check service
    systemd.services.qbittorrent-health = {
      description = "qBittorrent health check";
      after = [ "podman-qbittorrent.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.webPort}/api/v2/app/version";
        RemainAfterExit = true;
      };
      
      startAt = "*:0/5"; # Every 5 minutes
    };
  };
}

