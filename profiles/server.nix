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

{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.server;
  isPrimary = cfg.role == "primary";
in
{

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
    ../domains/server/native/couchdb/index.nix
  # Server packages now in domains/system/core/packages.nix (auto-imported via base.nix)
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  # NOTE: Filesystem structure creation disabled with paths refactor (Charter v10.1)
  # The new minimal materializer only creates /var/lib/hwc, /var/cache/hwc, /var/log/hwc
  # Services should create their own directories as needed via systemd.tmpfiles
  #
  # TODO: If these directories are needed, add tmpfiles rules to individual services
  # or restore filesystem.structure options in domains/system/core/filesystem.nix
  #
  # hwc.filesystem = {
  #   enable = true;
  #   structure.dirs = [
  #     # Business intelligence and AI directories
  #     { path = "/opt/business"; }
  #     { path = "/opt/ai"; }
  #
  #     # Service configuration directories
  #     { path = "/opt/arr"; }
  #     { path = "/opt/media"; }
  #     { path = "/opt/monitoring"; }
  #     { path = "/opt/downloads"; }  # Container base directory
  #
  #     # Container-specific directories
  #     { path = "/opt/downloads/jellyfin"; }
  #     { path = "/opt/downloads/jellyseerr"; }
  #     { path = "/mnt/hot/downloads"; }  # Already exists, keep for safety
  #     { path = "/mnt/hot/downloads/incomplete"; }  # SLSKD incomplete downloads
  #     { path = "/mnt/hot/downloads/complete"; }  # SLSKD completed downloads
  #     { path = "/mnt/hot/events"; }  # Critical for SABnzbd automation
  #     { path = "/mnt/hot/processing"; }  # Already exists, keep for safety
  #     { path = "/mnt/hot/processing/sonarr-temp"; }
  #     { path = "/mnt/hot/processing/radarr-temp"; }
  #     { path = "/mnt/hot/processing/lidarr-temp"; }
  #     { path = "/opt/downloads/scripts"; }  # Post-processing scripts
  #
  #     # HWC standard directories
  #     { path = "/var/lib/hwc"; }
  #     { path = "/var/cache/hwc"; }
  #     { path = "/var/log/hwc"; }
  #     { path = "/var/tmp/hwc"; }
  #
  #     # Security directories
  #     { path = "/var/lib/hwc/secrets"; mode = "0700"; }
  #   ];
  # };

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
  hwc.system.networking = {
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
        8787   # Readarr
        9696   # Prowlarr
        5055   # Jellyseerr
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

        # Calibre VNC
        5909   # Calibre desktop VNC

        # YouTube
        8943   # Pinchflat (YouTube subscriptions)

        # Game streaming (Sunshine)
        47984 47989 47990  # Sunshine HTTPS, Web UI, RTSP
        48010              # Sunshine video stream
      ];
      extraUdpPorts = [
        7359   # Jellyfin discovery
        50300  # SLSKD
        8555   # Frigate

        # Game streaming (Sunshine)
        47998 47999 48000 48010  # Sunshine control, video, audio
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
    hot.root = "/mnt/hot";      # SSD hot storage (auto-derives .downloads, .surveillance)
    media.root = "/mnt/media";  # HDD media storage (auto-derives .music, .surveillance)
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
  
  hwc.system.core.packages.server.enable = true;

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

  # SMART disk monitoring for early failure detection
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications = {
      mail = {
        enable = false; # TODO: Configure email notifications when SMTP is set up
        sender = "smartd@hwc-server";
        recipient = "root";
      };
      wall.enable = true; # Send wall messages to all logged in users
    };
    defaults.monitored = "-a -o on -s (S/../.././02|L/../../6/03)";
  };

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
  # Role-based defaults:
  # - primary: All services enabled (main production server)
  # - secondary: Core services only, override to enable more

  # Infrastructure services (minimal GPU configuration)
  # GPU enabled only if present - machines should override type
  hwc.infrastructure.hardware.gpu = {
    enable = lib.mkDefault true;
    type = "nvidia";
    nvidia = {
      driver = "stable";
      containerRuntime = true;   # Re-enabled after nixpkgs update
      enableMonitoring = true;
    };
  };

  # -------------------------------------------------------------------------
  # CORE SERVICES - Always enabled for any server
  # -------------------------------------------------------------------------
  hwc.server.reverseProxy = {
    enable = lib.mkDefault true;
    domain = "hwc.ocelot-wahoo.ts.net";
  };

  # -------------------------------------------------------------------------
  # MEDIA SERVICES - Primary server only by default
  # -------------------------------------------------------------------------

  # Download stack (VPN + clients)
  hwc.server.containers.gluetun = {
    enable = lib.mkDefault isPrimary;
    portForwarding = {
      enable = lib.mkDefault isPrimary;
      syncToQbittorrent = lib.mkDefault true;
      checkInterval = 60;  # Check every 60 seconds
    };
  };
  hwc.server.containers.qbittorrent.enable = lib.mkDefault isPrimary;
  hwc.server.containers.sabnzbd.enable = lib.mkDefault isPrimary;
  hwc.server.containers.mousehole.enable = lib.mkDefault isPrimary;  # MAM IP updater

  # *arr Stack (media management)
  hwc.server.containers.prowlarr.enable = lib.mkDefault isPrimary;
  hwc.server.containers.sonarr.enable = lib.mkDefault isPrimary;
  hwc.server.containers.radarr.enable = lib.mkDefault isPrimary;
  hwc.server.containers.lidarr.enable = lib.mkDefault isPrimary;
  hwc.server.containers.readarr.enable = lib.mkDefault isPrimary;  # Readarr for ebooks and audiobooks
  hwc.server.containers.books.enable = lib.mkDefault isPrimary;  # LazyLibrarian for ebooks and audiobooks
  hwc.server.containers.calibre.enable = lib.mkDefault isPrimary;  # Calibre for ebook library management
  hwc.server.containers.audiobookshelf.enable = lib.mkDefault isPrimary;  # Audiobookshelf for audiobooks

  # Audiobook copier (copies MAM downloads to Audiobookshelf library)
  hwc.server.native.orchestration.audiobookCopier.enable = lib.mkDefault isPrimary;

  # Beets music organizer - INTENTIONALLY DISABLED (using native installation)
  hwc.server.containers.beets.enable = false;

  hwc.server.containers.jellyseerr.enable = lib.mkDefault isPrimary;

  # Soulseek integration
  hwc.server.containers.slskd.enable = lib.mkDefault isPrimary;
  hwc.server.containers.soularr.enable = lib.mkDefault isPrimary;

  # Tdarr video transcoding - INTENTIONALLY DISABLED (high resource usage)
  hwc.server.containers.tdarr.enable = false;
  hwc.server.containers.recyclarr = {
    enable = lib.mkDefault isPrimary;
    services.lidarr.enable = false;  # Disable Lidarr sync (not supported in current Recyclarr version)
  };
  hwc.server.containers.organizr.enable = lib.mkDefault isPrimary;
  hwc.server.containers.pinchflat.enable = lib.mkDefault isPrimary;  # YouTube subscription manager

  # Native Media Services (Charter compliant)
  hwc.server.native.navidrome = {
    enable = lib.mkDefault isPrimary;
    settings = {
      initialAdminUser = "admin";
      # Password now securely loaded from agenix secret
      initialAdminPasswordFile = config.hwc.secrets.api.navidromeAdminPasswordFile;
      baseUrl = "/music";  # Required - Navidrome receives full path from Caddy
    };
    reverseProxy.enable = true;
  };

  hwc.server.native.jellyfin = {
    enable = lib.mkDefault isPrimary;
    openFirewall = false;  # Manual firewall management
    reverseProxy = {
      enable = true;
      path = "/media";
      upstream = "localhost:8096";
    };
    gpu.enable = true;  # Enable NVIDIA GPU acceleration for transcoding

    # User policy management via API
    apiKey = "26d513d02f27467aa94d70e4b43688f8";
    users.eric = {
      maxActiveSessions = 0;  # Unlimited sessions
    };
  };

  # RetroArch Emulation with Sunshine Game Streaming
  hwc.server.native.retroarch = {
    enable = lib.mkDefault isPrimary;
    # ROMs and BIOS at /mnt/media/retroarch/ (defaults)
    gpu.enable = true;  # Enable GPU acceleration for emulation

    # Enable cores for the game library
    cores = {
      dosbox-pure = true;    # DOS/Windows games (educational games, etc.)
      snes9x = true;         # SNES
      mgba = true;           # GBA
      mupen64plus = true;    # N64
      genesis-plus-gx = true; # Sega Genesis
      nestopia = true;       # NES
      beetle-psx-hw = true;  # PlayStation (hardware renderer)
      flycast = true;        # Dreamcast
    };

    # Sunshine for remote game streaming (Moonlight client compatible)
    sunshine = {
      enable = true;
      openFirewall = true;
      capSysAdmin = true;  # Required for mouse/keyboard emulation
    };
  };

  # WebDAV server for RetroArch save state sync (iOS/iPad/TV)
  # Access: https://hwc.ocelot-wahoo.ts.net/retroarch-sync/
  hwc.server.native.webdav = {
    enable = lib.mkDefault isPrimary;

    # Credentials from agenix secrets
    auth = {
      usernameFile = config.hwc.secrets.api.webdavUsernameFile;
      passwordFile = config.hwc.secrets.api.webdavPasswordFile;
    };

    # RetroArch save directories
    retroarch = {
      enable = true;
      syncSaves = true;   # .srm files
      syncStates = true;  # save states
    };

    # Expose via Caddy reverse proxy (Tailscale only)
    reverseProxy = {
      enable = true;
      path = "/retroarch-sync";
    };
  };

  # -------------------------------------------------------------------------
  # PERSONAL FINANCE - Primary server only by default
  # -------------------------------------------------------------------------

  # Firefly III Personal Finance (Containerized)
  hwc.server.containers.firefly = {
    enable = lib.mkDefault isPrimary;
    # Uses defaults from options.nix:
    # - Firefly III at port 10443, Firefly-Pico at port 11443
    # - PostgreSQL databases: firefly, firefly_pico
    # - APP_KEY from agenix secret
  };

  # -------------------------------------------------------------------------
  # PHOTO MANAGEMENT - Primary server only by default
  # -------------------------------------------------------------------------

  # Immich Photo Management (Native NixOS module - DISABLED)
  # Native module requires compiling from source which takes 24+ hours and crashes the system
  hwc.server.native.immich.enable = lib.mkForce false;

  # Immich Photo Management (Container - uses pre-built Docker images)
  # Storage layout (Immich's required structure):
  #   /mnt/media/photos/immich/library/       - Phone uploads (Immich's naming convention)
  #   /mnt/media/photos/immich/thumbs/        - Thumbnail cache
  #   /mnt/media/photos/immich/encoded-video/ - Transcoded videos
  #   /mnt/media/photos/immich/profile/       - Profile pictures
  #   /mnt/media/pictures/                    - External library (read-only)
  hwc.server.containers.immich = {
    enable = lib.mkDefault isPrimary;
    settings = {
      host = "0.0.0.0";
      port = 2283;
      mediaLocation = "/mnt/media/photos/immich";
    };
    storage = {
      enable = true;
      basePath = "/mnt/media/photos/immich";
      locations = {
        library = "/mnt/media/photos/immich/library";
        thumbs = "/mnt/media/photos/immich/thumbs";
        encodedVideo = "/mnt/media/photos/immich/encoded-video";
        profile = "/mnt/media/photos/immich/profile";
      };
    };
    database = {
      host = "127.0.0.1";  # Host network mode - access PostgreSQL directly
      port = 5432;
      name = "immich";
      user = "eric";  # Use eric user for peer auth compatibility
    };
    redis = {
      enable = true;   # Dedicated Redis for Immich
      host = "127.0.0.1";
      port = 6380;     # Different port to avoid conflict with redis-main
    };
    gpu.enable = true;
    machineLearning.enable = true;
    observability.metrics.enable = true;
    network.mode = "host";  # Simplest for accessing host PostgreSQL
  };

  # -------------------------------------------------------------------------
  # YOUTUBE & TRANSCRIPT SERVICES - Primary server only by default
  # -------------------------------------------------------------------------

  # YouTube Transcript API
  hwc.server.transcriptApi = {
    enable = lib.mkDefault isPrimary;
    port = 8099;
    dataDir = "/home/eric/01-documents/01-vaults/04-transcripts";
  };

  # PostgreSQL database (required by YouTube services and Immich)
  hwc.server.databases.postgresql = {
    enable = lib.mkDefault true;  # Always enabled for database needs
    version = "16";
  };

  # YouTube Transcripts API (new job-based service with worker)
  # DISABLED: Python packages not ready yet (workspace files untracked)
  hwc.services.ytTranscriptsApi = {
    enable = lib.mkDefault false;
    port = 8100;
    workers = 4;
    outputDirectory = "/mnt/hot/youtube-transcripts";
  };

  # YouTube Videos API (video download and archiving)
  # DISABLED: Python packages not ready yet (workspace files untracked)
  hwc.services.ytVideosApi = {
    enable = lib.mkDefault false;
    port = 8101;
    workers = 2;
    outputDirectory = "/mnt/media/youtube";
    # Note: stagingDirectory is deprecated and auto-derived as <outputDirectory>/.staging
  };

  # -------------------------------------------------------------------------
  # STORAGE AUTOMATION - All servers
  # -------------------------------------------------------------------------
  hwc.server.storage = {
    enable = lib.mkDefault true;
    cleanup = {
      enable = lib.mkDefault true;
      schedule = "daily";
      retentionDays = 7;
    };
    monitoring = {
      enable = lib.mkDefault true;
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
      # Storage paths: primary requires /mnt paths, secondary can have null paths
      assertion = !isPrimary || (
        (config.hwc.paths.hot.root != null && lib.hasPrefix "/mnt" config.hwc.paths.hot.root) ||
        (config.hwc.paths.media.root != null && lib.hasPrefix "/mnt" config.hwc.paths.media.root)
      );
      message = "Primary server requires dedicated storage mounts (hot or media should use /mnt/* paths)";
    }
    {
      assertion = config.hwc.secrets.enable;
      message = "Server profile requires hwc.secrets.enable = true";
    }
    {
      assertion = config.hwc.system.networking.tailscale.enable;
      message = "Server profile requires Tailscale for secure remote access";
    }
  ];
}
