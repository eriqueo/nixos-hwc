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

{ lib, pkgs, ... }: {

  #============================================================================
  # CHARTER V3 SERVICE IMPORTS
  #============================================================================
  
  imports = [
    # Media services (Charter v3 modules from Phase 2.1)
    ../modules/services/media/arr-stack.nix
    ../modules/services/media/networking.nix
    ../modules/services/media/downloaders.nix
    
    # Business services (Charter v3 modules from Phase 2.2)
    ../modules/services/business/database.nix
    ../modules/services/business/api.nix
    ../modules/services/business/monitoring.nix
    
    # Infrastructure services
    ../modules/infrastructure/gpu.nix
    ../modules/services/media/jellyfin.nix
    ../modules/services/media/immich.nix
    
    # AI services (existing)
    ../modules/services/ai/ollama.nix
    
    # Monitoring services
    ../modules/services/monitoring/prometheus.nix
    ../modules/services/monitoring/grafana.nix
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
  # SECURITY AND SECRETS (Server needs all secret categories)
  #============================================================================
  
  hwc.security.secrets = {
    # Base secrets (already enabled in base.nix):
    # user = true;  # User account secrets
    # vpn = true;   # VPN credentials
    
    # Server-specific secrets:
    database = true;     # PostgreSQL credentials for business services
    couchdb = true;      # CouchDB credentials for Obsidian sync
    services = true;     # Service API keys and admin credentials
    surveillance = true; # Surveillance system credentials
    arr = true;          # ARR stack API keys
    ntfy = true;         # NTFY notification tokens
  };

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
  
  # Server user configuration extends base profile
  hwc.home.groups.hardware = true;  # Access to hardware devices

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
      extraOptions = "--log-driver=journald --log-opt max-size=10m --log-opt max-file=3";
    };
    
    oci-containers.backend = "podman";  # Use Podman for system containers
  };

  #============================================================================
  # SYSTEM PACKAGES (Server-specific)
  #============================================================================
  
  environment.systemPackages = with pkgs; [
    # Server monitoring and management
    htop iotop nvtop
    lsof netstat ss
    tcpdump nmap
    
    # Container management
    docker-compose
    podman-compose
    
    # File management for media
    rsync rclone
    unzip p7zip
    
    # Database tools
    postgresql  # Client tools
    redis       # CLI tools
    
    # Media processing
    ffmpeg imagemagick
    
    # AI/ML tools (basic)
    python3
    
    # Backup and archival
    borgbackup restic
  ];

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
  # CHARTER V3 SERVICE ENABLEMENT
  #============================================================================
  
  # Media services (from Phase 2.1)
  hwc.services.media = {
    # ARR Stack
    arr = {
      enable = true;
      sonarr.enable = true;
      radarr.enable = true; 
      lidarr.enable = true;
      prowlarr.enable = true;
      gpu.enable = true;  # Enable GPU acceleration
    };
    
    # Media networking and VPN
    networking = {
      enable = true;
      vpn.enable = true;
      healthMonitoring.enable = true;
    };
    
    # Download clients
    downloaders = {
      enable = true;
      qbittorrent.enable = true;
      sabnzbd.enable = true;
      slskd.enable = true;
      soularr.enable = true;
      useVpn = true;  # Route through VPN
    };
  };
  
  # Business services (from Phase 2.2)
  hwc.services.business = {
    # Database services
    database = {
      enable = true;
      postgresql.enable = true;
      redis.enable = true;
      backup.enable = true;
      packages.enable = true;
    };
    
    # API development environment
    api = {
      enable = true;
      development.enable = true;
      packages.enable = true;
      # service.enable = false;  # Keep disabled for development
    };
    
    # Business intelligence monitoring
    monitoring = {
      enable = true;
      dashboard.enable = true;
      metrics.enable = true;
      analytics = {
        enable = true;
        storageAnalysis = true;
        processingAnalysis = true;
        costEstimation = true;
      };
    };
  };
  
  # Infrastructure services
  hwc.infrastructure = {
    gpu = {
      enable = true;
      nvidia.enable = true;
      cuda.enable = true;
    };
  };
  
  # AI services
  hwc.services.ai.ollama = {
    enable = true;
    acceleration = "cuda";
    hostAddress = "0.0.0.0";
  };
  
  # Media applications
  services.jellyfin.enable = true;
  services.immich.enable = true;

  #============================================================================
  # ASSERTIONS AND VALIDATION
  #============================================================================
  
  assertions = [
    {
      assertion = config.hwc.paths.hot != null && config.hwc.paths.media != null;
      message = "Server profile requires hwc.paths.hot and hwc.paths.media to be configured";
    }
    {
      assertion = config.hwc.security.enable;
      message = "Server profile requires hwc.security.enable = true";
    }
    {
      assertion = config.hwc.networking.tailscale.enable;
      message = "Server profile requires Tailscale for secure remote access";
    }
  ];
}