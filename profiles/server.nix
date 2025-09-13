# profiles/server.nix - Server Profile for Production Migration
#
# Charter v3 Server Configuration Profile
# Extends base profile with server-specific features and service enablement
#
# DEPENDENCIES:
#   Upstream: profiles/base.nix (core system configuration)
#
# USED BY:
#   Downstream: machines/hwc-server.nix (production server)
#   Downstream: Future server machine configurations
#
# IMPORTS REQUIRED IN:
#   - machines/hwc-server.nix: ../../profiles/server.nix
#
# USAGE:
#   Provides complete server environment with:
#   - All security secrets enabled
#   - Server storage and filesystem structure
#   - Hardware acceleration ready
#   - Service directories prepared
#
# VALIDATION:
#   - Requires agenix secrets to be configured
#   - Assumes server hardware (storage, GPU)

{ lib, pkgs, config, ... }: {

  #============================================================================
  # CHARTER V3 SERVICE IMPORTS
  #============================================================================
  
  imports = [
    # Core system modules only (legacy services disabled until Charter v6 migration complete)
    ../modules/infrastructure/index.nix
    # Server packages now in modules/system/packages/server.nix (auto-imported via base.nix)
  ];
  
  #============================================================================
  # SERVER STORAGE AND FILESYSTEM
  #============================================================================
  
  # Enable complete server filesystem structure
  hwc.filesystem = {
    enable = true;
    serverStorage.enable = true;        # Hot/cold storage directories
    businessDirectories.enable = true;  # Business intelligence and AI directories  
    serviceDirectories.enable = true;   # *ARR service configuration directories
    securityDirectories.enable = true;  # Security and secrets directories (from base)
    userDirectories.enable = true;      # PARA structure (from base, but needed for server admin)
  };

  #============================================================================
  # SECURITY AND SECRETS (Server extends base secrets)
  #============================================================================
  
  # Server uses the base hwc.system.secrets configuration from base.nix
  # Individual services will configure their own specific secrets as needed
  # No additional server-specific secrets configuration required here

  #============================================================================
  # NETWORKING (Server-specific configuration)
  #============================================================================
  
  # Server networking extends base configuration
  hwc.networking = {
    # Base networking already enabled in base.nix
    ssh.x11Forwarding = true;  # For remote GUI applications
    
    # Server-specific Tailscale configuration
    tailscale = {
      permitCertUid = "caddy";  # Allow Caddy to access certificates
      extraUpFlags = [ 
        "--advertise-tags=tag:server"
        "--accept-routes" 
      ];
    };
    
    # Server firewall allows additional service ports
    firewall = {
      services.web = true;  # Enable HTTP/HTTPS for Caddy
      extraTcpPorts = [
        # Media services
        5000   # Frigate
        8080   # qBittorrent (via Gluetun)
        7878   # Radarr
        8989   # Sonarr  
        8686   # Lidarr
        9696   # Prowlarr
        4533   # Navidrome
        8096   # Jellyfin
        2283   # Immich
        8081   # SABnzbd
        5030   # SLSKD
        
        # Business services
        8888   # Receipt API
        8501   # Streamlit apps
        5432   # PostgreSQL (internal)
        6379   # Redis (internal)
        
        # Monitoring services
        3000   # Grafana
        9090   # Prometheus
        9093   # Alertmanager
        
        # AI services
        11434  # Ollama
      ];
      extraUdpPorts = [
        7359   # Jellyfin discovery
        50300  # SLSKD
        8555   # Frigate
      ];
    };
  };

  #============================================================================
  # USER ENVIRONMENT (Server additions)
  #============================================================================
  
  # Server user configuration extends base profile - add hardware access groups
  hwc.system.users.groups = [ "wheel" "networkmanager" "video" "input" "audio" "lp" "scanner" "docker" "podman" "kvm" "libvirtd" ];

  #============================================================================
  # STORAGE CONFIGURATION
  #============================================================================
  
  # Server storage paths (to be set in machine-specific config)
  hwc.paths = {
    hot = "/mnt/hot";      # SSD hot storage
    media = "/mnt/media";  # HDD media storage
    # cold and backup can be set per-machine
  };

  #============================================================================
  # CONTAINER RUNTIME (Server-specific)
  #============================================================================
  
  # Enhanced container configuration for server workloads
  virtualisation = {
    # Disable Docker from base profile since we want Podman
    docker.enable = lib.mkForce false;
    
    # Enable Podman for rootless containers
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    
    oci-containers.backend = "podman";  # Use Podman for system containers
  };

  #============================================================================
  # SYSTEM PACKAGES - Moved to modules/system/server-packages.nix
  #============================================================================
  
  hwc.system.serverPackages.enable = true;

  #============================================================================
  # PERFORMANCE OPTIMIZATIONS
  #============================================================================
  
  # Server performance tuning
  boot.kernel.sysctl = {
    # Network performance
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
    
    # File system performance
    "vm.dirty_ratio" = 15;
    "vm.dirty_background_ratio" = 5;
    "vm.swappiness" = 10;
  };

  # I/O scheduler optimization for server workloads
  services.udev.extraRules = ''
    # Use mq-deadline for SSDs (better for mixed workloads)
    ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd*", ENV{ID_BUS}=="ata", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
    
    # Use bfq for HDDs (better for mixed workloads on servers)
    ACTION=="add|change", KERNEL=="sd*", ENV{ID_BUS}=="ata", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
  '';

  #============================================================================
  # LOGGING AND MONITORING
  #============================================================================
  
  # Enhanced logging for server environment
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    RuntimeMaxUse=200M
    SystemMaxFileSize=100M
    MaxRetentionSec=1month
  '';

  # Log rotation for container logs
  services.logrotate = {
    enable = true;
    settings = {
      docker = {
        files = [ "/var/lib/docker/containers/*/*.log" ];
        frequency = "daily";
        rotate = 7;
        compress = true;
        missingok = true;
        notifempty = true;
        sharedscripts = true;
      };
    };
  };

  #============================================================================
  # SERVICE ENABLEMENT (Legacy services temporarily disabled)
  #============================================================================
  
  # Infrastructure services (minimal GPU configuration)
  hwc.infrastructure.hardware.gpu = {
    enable = true;
    type = "nvidia";
    nvidia = {
      driver = "stable";
      containerRuntime = true;
      enableMonitoring = true;
    };
  };
  
  # Legacy services disabled until Charter v6 migration complete:
  # - Media services (ARR stack, downloaders, etc.)
  # - Business services (database, API, monitoring)
  # - AI services (Ollama)
  # - Application services (Jellyfin, Immich)

  #============================================================================
  # ASSERTIONS AND VALIDATION
  #============================================================================
  
  assertions = [
    {
      assertion = config.hwc.paths.hot != null && config.hwc.paths.media != null;
      message = "Server profile requires hwc.paths.hot and hwc.paths.media to be configured";
    }
    {
      assertion = config.hwc.system.secrets.enable;
      message = "Server profile requires hwc.system.secrets.enable = true";
    }
    {
      assertion = config.hwc.networking.tailscale.enable;
      message = "Server profile requires Tailscale for secure remote access";
    }
  ];
}
