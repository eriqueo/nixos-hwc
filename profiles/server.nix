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

  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  # CHARTER V3 SERVICE IMPORTS
  #============================================================================
  
  imports = [
    # Core system modules only (legacy services disabled until Charter v6 migration complete)
    ../domains/infrastructure/index.nix
    # Server domain modules (includes containers and other server services)
    ../domains/server/index.nix
    # CouchDB for Obsidian LiveSync
    ../domains/server/couchdb
    # Server packages now in modules/system/packages/server.nix (auto-imported via base.nix)
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  # Enable complete server filesystem structure
  hwc.filesystem = {
    enable = true;
    structure.dirs = [
      # Business intelligence and AI directories
      { path = "/opt/business"; }
      { path = "/opt/ai"; }

      # Service configuration directories
      { path = "/opt/arr"; }
      { path = "/opt/media"; }
      { path = "/opt/monitoring"; }
      { path = "/opt/downloads"; }  # Container base directory

      # Container-specific directories
      { path = "/opt/downloads/jellyfin"; }
      { path = "/mnt/hot/downloads"; }  # Already exists, keep for safety
      { path = "/mnt/hot/downloads/incomplete"; }  # SLSKD incomplete downloads
      { path = "/mnt/hot/downloads/complete"; }  # SLSKD completed downloads
      { path = "/mnt/hot/events"; }  # Critical for SABnzbd automation
      { path = "/mnt/hot/processing"; }  # Already exists, keep for safety
      { path = "/mnt/hot/processing/sonarr-temp"; }
      { path = "/mnt/hot/processing/radarr-temp"; }
      { path = "/mnt/hot/processing/lidarr-temp"; }
      { path = "/opt/downloads/scripts"; }  # Post-processing scripts

      # HWC standard directories
      { path = "/var/lib/hwc"; }
      { path = "/var/cache/hwc"; }
      { path = "/var/log/hwc"; }
      { path = "/var/tmp/hwc"; }

      # Security directories
      { path = "/var/lib/hwc/secrets"; mode = "0700"; }
    ];
  };

  #============================================================================
  # SECURITY AND SECRETS (Server extends base secrets)
  #============================================================================
  
  # Server uses the base hwc.secrets configuration from base.nix
  # Individual services will configure their own specific secrets as needed
  # No additional server-specific secrets configuration required here

  #============================================================================
  # NETWORKING (Server-specific configuration)
  #============================================================================
  
  # Server networking extends base configuration
  hwc.networking = {
    # Base networking already enabled in base.nix
    #ssh.x11Forwarding = true;  # For remote GUI applications
    
    # Server-specific Tailscale configuration
    tailscale = {
      #permitCertUid = lib.mkIf config.services.caddy.enable "caddy";  # Allow Caddy to access certificates only if Caddy is enabled
      extraUpFlags = [ 
        "--advertise-tags=tag:server"
        "--accept-routes" 
      ];
    };
    
    # Server firewall allows additional service ports
    firewall = {
      #services.web = true;  # Enable HTTP/HTTPS for Caddy
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
  
  # User groups now managed in modules/system/users/ domain (Charter compliance)
  # Hardware access groups are included in the user definition

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
  
  hwc.system.packages.server.enable = true;

  #============================================================================
  # PERFORMANCE OPTIMIZATIONS
  #============================================================================
  
  # Server performance tuning
  boot.kernel.sysctl = {
    # Network performance handled by system domain - removed duplicates
    
    # File system performance
    "vm.dirty_ratio" = lib.mkDefault 15;
    "vm.dirty_background_ratio" = lib.mkDefault 5;
    "vm.swappiness" = lib.mkDefault 10;
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
  # SERVICE ENABLEMENT (Charter v6 migration in progress)
  #============================================================================

  # Infrastructure services (minimal GPU configuration)
  hwc.infrastructure.hardware.gpu = {
    enable = true;
    type = "nvidia";
    nvidia = {
      driver = "stable";
      containerRuntime = true;   # Re-enabled after nixpkgs update
      enableMonitoring = true;
    };
  };

  # Container services (Charter v6 migration test)
  hwc.services.containers.gluetun.enable = true;
  hwc.services.containers.qbittorrent.enable = true;
  hwc.services.containers.sabnzbd.enable = true;

  # Phase 3: Media Management (*arr Stack)
  hwc.services.containers.prowlarr.enable = true;
  hwc.services.containers.sonarr.enable = true;
  hwc.services.containers.radarr.enable = true;
  hwc.services.containers.lidarr.enable = true;

  # Phase 4: Specialized Services (Soulseek integration)
  hwc.services.containers.slskd.enable = true;
  hwc.services.containers.soularr.enable = true;  # Now that Lidarr is enabled
  # hwc.services.containers.navidrome.enable = true;  # Disabled - using native service
  # hwc.services.containers.jellyfin.enable = true;  # Disabled - using native service

  # Native Media Services (Charter compliant)
  hwc.server.navidrome = {
    enable = true;
    settings = {
      initialAdminUser = "admin";
      initialAdminPassword = "il0wwlm?";
      baseUrl = "/navidrome";  # Required for reverse proxy
    };
    reverseProxy.enable = true;
  };

  hwc.server.jellyfin = {
    enable = true;
    openFirewall = false;  # Manual firewall management
    reverseProxy = {
      enable = true;
      path = "/media";
      upstream = "localhost:8096";
    };
  };

  hwc.server.immich = {
    enable = true;
    settings = {
      host = "0.0.0.0";
      port = 2283;
      mediaLocation = "/mnt/photos";
    };
    database = {
      createDB = false;  # Use existing database
      name = "immich";
      user = "immich";
    };
    redis.enable = true;
    gpu.enable = true;  # Enable GPU acceleration
  };

  # Phase 5: Infrastructure Services
  hwc.services.reverseProxy = {
    enable = true;
    domain = "hwc.ocelot-wahoo.ts.net";
  };

  # Phase 6: Support Services - Storage Automation
  hwc.services.storage = {
    enable = true;
    cleanup = {
      enable = true;
      schedule = "daily";
      retentionDays = 7;
    };
    monitoring = {
      enable = true;
      alertThreshold = 85;
    };
  };

  # Legacy services disabled until Charter v6 migration complete:
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
      assertion = config.hwc.secrets.enable;
      message = "Server profile requires hwc.secrets.enable = true";
    }
    {
      assertion = config.hwc.networking.tailscale.enable;
      message = "Server profile requires Tailscale for secure remote access";
    }
  ];
}
