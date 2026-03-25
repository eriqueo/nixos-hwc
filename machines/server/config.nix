# nixos-hwc/machines/server/config.nix
#
# MACHINE: HWC-SERVER
# Declares machine identity and composes profiles; states hardware reality.

{ config, lib, pkgs, inputs ? null, ... }:
{
  imports = [
    ./hardware.nix

    # Core profile — system/paths/secrets (NO session.nix — headless server)
    ../../profiles/core.nix

    ../../domains/ai/index.nix
    ../../domains/networking/index.nix
    ../../domains/data/index.nix
    ../../domains/media/index.nix
    ../../profiles/monitoring.nix
    ../../domains/business/index.nix  # Direct domain import (no profile wrapper)
    ../../domains/alerts/index.nix    # Direct domain import (no profile wrapper)
    ../../domains/gaming/index.nix    # Retroarch emulation + WebDAV save sync
    ../../domains/webapps/index.nix   # Static web app hosting (hwc-publish, port 14000–14099)
  ];

  assertions = [
    # Server role assertions
    {
      assertion = (
        (config.hwc.paths.hot.root != null && lib.hasPrefix "/mnt" config.hwc.paths.hot.root) ||
        (config.hwc.paths.media.root != null && lib.hasPrefix "/mnt" config.hwc.paths.media.root)
      );
      message = "Server requires dedicated storage mounts (hot or media should use /mnt/* paths)";
    }
    {
      assertion = config.hwc.secrets.enable;
      message = "Server machine requires hwc.secrets.enable = true";
    }
    {
      assertion = config.hwc.system.networking.tailscale.enable;
      message = "Server machine requires Tailscale for secure remote access";
    }
    # CHARTER v9.0: Hard enforcement that server MUST use stable nixpkgs
    {
      # pkgs.lib.trivial.release returns e.g. "25.11" for nixos-25.11 stable
      assertion = lib.hasPrefix "25" (pkgs.lib.trivial.release or "");
      message = ''
        ============================================================
        SERVER NIXPKGS PROVENANCE VIOLATION
        ============================================================
        hwc-server MUST use nixpkgs-stable, not nixpkgs-unstable!

        Current nixpkgs: ${toString pkgs.path}
        Current release: ${pkgs.lib.trivial.release or "unknown"}
        Expected: nixpkgs-stable (25.11 branch)

        Fix in flake.nix:
          hwc-server = nixpkgs-stable.lib.nixosSystem {
            pkgs = pkgs-stable;  # NOT pkgs
          };
        ============================================================
      '';
    }
    {
      # CHARTER v9.0: PostgreSQL MUST be pinned to version 15
      # Data directory is PostgreSQL 15 format - upgrading breaks compatibility
      assertion = !config.services.postgresql.enable || (
        lib.hasPrefix "15." config.services.postgresql.package.version
      );
      message = ''
        ============================================================
        POSTGRESQL VERSION PIN VIOLATION
        ============================================================
        PostgreSQL MUST be pinned to version 15.x!

        Current: ${config.services.postgresql.package.version or "unknown"}
        Expected: 15.x
        Data directory: ${config.services.postgresql.dataDir or "/var/lib/hwc/postgresql"}

        The PostgreSQL data directory was initialized with version 15.
        Upgrading to version 16+ requires data migration:

        1. Backup: pg_dumpall -f /backup/postgresql-pre-upgrade.sql
        2. Stop PostgreSQL: systemctl stop postgresql
        3. Migrate: pg_upgrade (see PostgreSQL docs)
        4. Update pin in domains/server/native/networking/parts/databases.nix
        5. Test thoroughly before production deployment

        See CHARTER.md section 24 "Flake Update Strategy"
        ============================================================
      '';
    }
  ];

  # System identity
  networking.hostName = "hwc-server";
  networking.hostId = "8425e349";

  # Server identity (Charter v10.3 multi-server support)
  hwc.server.enable = true;

  # ZFS support for backup drives
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # Note: boot.initrd.systemd.fido2 doesn't exist in stable 24.05 (added in later versions)

  # ZFS configuration
  boot.zfs.extraPools = [ "backup-pool" ];  # Auto-import backup pool on boot

  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";  # Monthly scrub for data integrity
    };
    trim = {
      enable = true;
      interval = "weekly";  # Weekly TRIM for performance
    };
  };

  # Charter v10.1 path configuration (hostname-based defaults)
  # Server hostname detection provides all correct defaults:
  #   hot.root = "/mnt/hot"          (SSD hot storage, auto-derives .downloads, .surveillance)
  #   media.root = "/mnt/media"      (HDD media storage, auto-derives .music)
  #   cold = "/mnt/media"            (Cold storage, same as media)
  #   photos = "/mnt/photos"         (Photo storage for Immich)
  #   business.root = "/opt/business"
  # No overrides needed - all defaults match server requirements

  # Storage configuration (Charter v6.0 compliant)
  hwc.system.mounts = {
    hot = {
      enable = true;
      device = "/dev/disk/by-uuid/fd7a9820-a3e2-45cb-9c97-9fd904ee459a";
      fsType = "ext4";
    };
    media.enable = true;   # Directory management only (mount defined below)
    backup.enable = true;  # Enable backup drive automation
  };

  # Media storage mount (infrastructure module manages directories only)
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-label/media";
    fsType = "ext4";
  };

  # Time zone (from production)
  time.timeZone = "America/Denver";

  # Production system settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Official NixOS CUDA binary cache (moved from cachix Nov 2025)
    # https://wiki.nixos.org/wiki/CUDA
    substituters = [
      "https://cache.nixos.org"
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };
  # allowUnfree set in flake.nix

  # --- Networking Configuration (Server: DO wait for network) ---
  hwc.system.networking = {
    enable = true;
    networkManager.enable = true;

    # Safest: wait for any NetworkManager connection (no hard-coded iface names).
    waitOnline.mode = "all";
    waitOnline.timeoutSeconds = 30;  # Reduced from 90s for faster boot

    ssh.enable = true;
    tailscale.enable = true;
    tailscale.funnel.enable = false;  # Disabled - using n8n-specific funnel on port 10000
    tailscale.extraUpFlags = [ "--advertise-tags=tag:server" "--accept-routes" ];
    nfs.server = {
      enable = true;
      exports = ''
        ${config.hwc.paths.user.shared} 100.64.0.0/10(rw,sync,no_subtree_check)
      '';
    };
    firewall.level = lib.mkForce "server";
    firewall.extraTcpPorts = [
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
      7359               # Jellyfin discovery (also UDP)
    ];
    firewall.extraUdpPorts = [
      7359   # Jellyfin discovery
      50300  # SLSKD
      8555   # Frigate
      # Game streaming (Sunshine)
      47998 47999 48000 48010
    ];
  };

  # Samba file sharing for RetroArch ROMs (Google TV access)
  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "hwc-server";
        security = "user";
        "map to guest" = "Bad User";
        "guest account" = "nobody";
        # Modern SMB protocols
        "server min protocol" = "SMB2_10";
        "server max protocol" = "SMB3";
      };

      # RetroArch ROMs - read-only guest access
      retroarch = {
        path = "/mnt/media/retroarch";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        comment = "RetroArch ROMs and BIOS";
      };
    };
  };

  # Samba discovery (optional, helps Google TV find the share)
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # MQTT broker for event-driven automation (Frigate -> n8n)
  hwc.automation.mqtt = {
    enable = true;
    webhookBridge = {
      enable = true;
      topic = "frigate/events";
      webhookUrl = "http://127.0.0.1:5678/webhook/frigate-events";
    };
  };

  # ntfy notification system CLI client for server alerts
  # Multi-topic architecture: critical, alerts, backups, media, monitoring, updates, ai
  # See: docs/infrastructure/ntfy-notification-classes.md
  hwc.automation.ntfy = {
    enable = false;
    serverUrl = "https://hwc.ocelot-wahoo.ts.net:2586";  # Self-hosted ntfy via Tailscale port mode
    defaultTopic = "hwc-server-events";  # General server events
    defaultTags = [ "hwc" "server" "production" ];
    defaultPriority = 4;  # Higher priority for server alerts
    hostTag = true;       # Adds "host-hwc-server" tag automatically

    # Authentication disabled for self-hosted (can enable if needed)
    auth.enable = false;
    # To enable auth, add secrets and configure:
    # auth = {
    #   enable = true;
    #   method = "token";
    #   tokenFile = "/run/secrets/ntfy-token";
    # };
  };

  # Centralized alerts via n8n -> Slack (replaces ntfy monitoring)
  # Uses hwc.alerts domain for all system notifications
  hwc.alerts = {
    enable = true;

    # Disk space monitoring
    sources.diskSpace = {
      enable = true;
      frequency = "hourly";
      filesystems = [ "/" "/home" "/mnt/media" "/mnt/hot" ];
      warningThreshold = 80;
      criticalThreshold = 95;
    };

    # Service failure notifications (auto-detect critical services)
    sources.serviceFailures = {
      enable = true;
      autoDetect = true;
    };

    # SMART disk monitoring
    sources.smartd.enable = true;

    # Backup notifications
    sources.backup = {
      enable = true;
      onSuccess = false;  # Don't spam on success
      onFailure = true;   # Always alert on failure
    };

    # CLI tool for manual alerts
    cli.enable = true;
  };

  # Rsync backup DISABLED - using Borg exclusively
  # See hwc.data.borg below for primary backup
  hwc.data.backup.enable = false;

  # Borg Backup - Primary deduplicating backup (daily)
  hwc.data.borg = {
    enable = true;

    repo.path = "/mnt/backup/borg-hwc-server";

    # Same sources as rsync, plus database dumps
    sources = [
      "/mnt/media/photos"                # Immich photos (CRITICAL)
      "/mnt/media/surveillance/frigate"  # Security camera recordings
      "/var/lib/hwc"                     # Service state directories
      "/var/lib/backups"                 # Database dumps
    ];

    excludePatterns = [
      ".cache"
      "*.tmp"
      "*.temp"
      "node_modules"
      "__pycache__"
      "*.log"
    ];

    # Daily at 2 AM (before rsync fallback at 3 AM on its days)
    schedule = {
      frequency = "daily";
      timeOfDay = "02:00";
      randomDelay = "30m";
    };

    # Retention (dedup makes this cheap)
    retention = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };

    # Database dumps before backup
    preBackupScript = ''
      DUMP_DIR="/var/lib/backups"
      mkdir -p "$DUMP_DIR"
      DATE=$(date +%Y-%m-%d)
      JQ=/run/current-system/sw/bin/jq
      CURL=/run/current-system/sw/bin/curl

      echo "Dumping PostgreSQL databases..."
      if systemctl is-active --quiet postgresql; then
        /run/wrappers/bin/su - postgres -s /bin/sh -c "/run/current-system/sw/bin/pg_dumpall" > "$DUMP_DIR/postgresql-$DATE.sql" 2>/dev/null || echo "PostgreSQL dump failed"
      fi

      echo "Dumping CouchDB databases..."
      if systemctl is-active --quiet couchdb; then
        COUCH_USER=$(cat /run/agenix/couchdb-admin-username 2>/dev/null || echo "admin")
        COUCH_PASS_RAW=$(cat /run/agenix/couchdb-admin-password 2>/dev/null || echo "")
        COUCH_PASS=$(printf '%s' "$COUCH_PASS_RAW" | $JQ -sRr @uri)
        if [ -n "$COUCH_PASS" ]; then
          for db in $($CURL -sf "http://$COUCH_USER:$COUCH_PASS@127.0.0.1:5984/_all_dbs" | $JQ -r '.[]' 2>/dev/null | grep -v "^_"); do
            $CURL -sf "http://$COUCH_USER:$COUCH_PASS@127.0.0.1:5984/$db/_all_docs?include_docs=true" > "$DUMP_DIR/couchdb-$db-$DATE.json" 2>/dev/null || echo "CouchDB $db dump failed"
          done
        fi
      fi

      # Cleanup old dumps (keep 14 days - Borg handles long-term retention)
      find "$DUMP_DIR" -name "*.sql" -mtime +14 -delete 2>/dev/null || true
      find "$DUMP_DIR" -name "*.json" -mtime +14 -delete 2>/dev/null || true
      echo "Database dumps complete"
    '';

    monitoring.enable = true;
    notifications.onFailure = true;
  };

  # Machine-specific GPU override for Quadro P1000 (legacy driver required)
  hwc.system.hardware.gpu = {
    enable = lib.mkForce true;
    type = "nvidia";
    nvidia = {
      driver = "stable";  # Use stable as base, override package below
      containerRuntime = true;
      enableMonitoring = true;
    };
  };

  # P1000 (Pascal) with driver 580 - last full-support branch before legacy transition
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;  # 580.95.05
    open = lib.mkForce false;  # Pascal doesn't support open-source modules
    modesetting.enable = true;
    powerManagement.enable = true;
  };

  # CUDA config (cudaSupport + binary cache) set in flake.nix
  # GPU acceleration for Immich handled by hwc.media.immich.gpu.enable

  # GPU acceleration for Immich handled by hwc.media.immich.gpu.enable in server profile

  # AI DOMAIN CONFIGURATION (Server)
  #============================================================================
  # Profile auto-detection: server (GPU: nvidia, RAM: 32GB >= 16GB threshold)
  # Result: Relaxed limits (4 cores, 8GB, 80°C warning, 90°C critical)
  hwc.ai = {
    # Explicit server profile selection
    profiles.selected = "server";

    # AI CLI tools disabled on server (headless environment)
    tools.enable = false;

    # Ollama LLM service with profile-based defaults
    ollama = {
      enable = true;

      # Explicit model list for 4GB VRAM GPU (Quadro P1000)
      # Note: Load one at a time due to VRAM constraints
      models = [
        "qwen2.5-coder:3b"   # 1.9GB - Best coding model
        "phi3:3.8b"          # 2.3GB - General purpose
        "llama3.2:3b"        # 2.0GB - Chat, journaling
      ];

      # Override profile defaults for server (unlimited resources)
      resourceLimits = {
        enable = true;
        maxCpuPercent = null;         # Unlimited CPU
        maxMemoryMB = null;           # Unlimited memory
        maxRequestSeconds = 600;      # 10 minute timeout
      };

      idleShutdown.enable = false;    # Always-on service
      thermalProtection.enable = false; # Datacenter cooling
    };

    # Local AI workflows and automation
    local-workflows = {
      enable = true;

      # AI-powered file cleanup agent
      fileCleanup = {
        enable = true;
        watchDirs = [ "/mnt/hot/inbox" "/home/eric/Downloads" ];
        schedule = "*:0/30";  # Every 30 minutes
        model = "qwen2.5-coder:3b";
        dryRun = false;  # Set to true for testing
      };

      # Automatic daily journaling
      journaling = {
        enable = true;
        outputDir = "/home/eric/Documents/HWC-AI-Journal";
        sources = [ "systemd-journal" "container-logs" "nixos-rebuilds" ];
        schedule = "daily";
        timeOfDay = "02:00";
        model = "llama3.2:3b";
        retentionDays = 90;
      };

      # Auto-documentation generator (CLI tool)
      autoDoc = {
        enable = true;
        model = "qwen2.5-coder:3b";
      };

      # Interactive chat CLI
      chatCli = {
        enable = true;
        model = "llama3:8b";  # Better instruction following than qwen2.5-coder
        # systemPrompt inherited from domain default
      };

      # Workflows HTTP API (Sprint 5.4)
      api = {
        enable = true;
        port = 6021;
        # All other settings use defaults from domain options
      };
    };
  };

  # Open WebUI - Modern web interface for Ollama
  # Access: https://hwc.ocelot-wahoo.ts.net:3443 (via Caddy port mode)
  hwc.ai.open-webui = {
    enable = true;
    enableAuth = false;  # TEMPORARY: Disabled to bypass signup page rendering issue
    healthCheck.enable = false;  # Avoid failing rebuild on unhealthy healthcheck
    # All other settings use defaults:
    # - port: 3001
    # - defaultModel: "phi3:3.8b"
    # - enableRAG: true
  };

  # MCP (Model Context Protocol) server for LLM access
  # Provides filesystem access to ~/.nixos for AI assistants
  # DISABLED: mcp-proxy not available in nixpkgs-stable 24.05
  hwc.ai.mcp.enable = lib.mkForce false;

  # Note: Backup is configured above (hwc.data.backup block at line ~304)
  # NixOS config excluded - it's in git. Databases handled by preBackupScript.

  # Navidrome music streaming (container)
  hwc.media.navidrome.enable = true;
  # Enable AI router and agent on server
  hwc.ai.router = {
    enable = true;
    port = 11435;
  };
  hwc.ai.agent = {
    enable = true;
    port = 6020;
  };

  # NanoClaw AI agent orchestrator
  # Connects to Slack via Socket Mode, spawns agents in containers
  hwc.ai.nanoclaw = {
    enable = true;
    slack.enable = true;  # Inject Slack tokens from agenix
  };

  # CouchDB for Obsidian LiveSync
  hwc.data.couchdb = {
    enable = true;
    settings = {
      port = 5984;
      bindAddress = "127.0.0.1";  # Localhost only for security
    };
    monitoring.enableHealthCheck = true;
    reverseProxy = {
      enable = true;  # Expose via Caddy for remote access
      path = "/sync";  # Match Obsidian's expected path
    };
  };

  # ntfy notification server (alerts domain)
  # Disabled - no longer in use; alerts route via n8n -> Slack
  hwc.alerts.server = {
    enable = false;
    port = 2586;
    dataDir = "/var/lib/hwc/ntfy";
  };

  # Frigate NVR (Config-First Pattern with GPU Acceleration)
  # Access: https://hwc.ocelot-wahoo.ts.net:5443 (via Caddy)
  # Charter v7.0 Section 19 compliant - TensorRT CUDA support
  hwc.media.frigate = {
    enable = true;

    # Internal port 5001 (exposed as 5443 via Caddy)
    port = 5001;

    # GPU acceleration for ONNX object detection (TensorRT + CUDA)
    gpu = {
      enable = true;
      device = 0;  # NVIDIA P1000
    };

    # Storage paths
    storage = {
      configPath = "/opt/surveillance/frigate/config";
      mediaPath = "/mnt/media/surveillance/frigate/media";
      bufferPath = "/mnt/hot/surveillance/frigate/buffer";
    };

    # Firewall settings
    firewall.tailscaleOnly = true;
  };

  # Automated surveillance cleanup (enforce Frigate retention policy)
  systemd.timers.frigate-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  systemd.services.frigate-cleanup = {
    description = "Cleanup old Frigate surveillance recordings";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      # Frigate handles its own cleanup, but this provides backup enforcement
      # Delete recordings older than 7 days (Frigate config retention)
      ${pkgs.findutils}/bin/find /mnt/media/surveillance/frigate/recordings -type f -name "*.mp4" -mtime +7 -delete 2>/dev/null || true

      # Delete clips older than 10 days (event retention)
      ${pkgs.findutils}/bin/find /mnt/media/surveillance/frigate/clips -type f -name "*.mp4" -mtime +10 -delete 2>/dev/null || true

      # Delete empty directories
      ${pkgs.findutils}/bin/find /mnt/media/surveillance/frigate -type d -empty -delete 2>/dev/null || true

      # Log cleanup stats
      RECORDINGS_SIZE=$(${pkgs.coreutils}/bin/du -sh /mnt/media/surveillance/frigate/recordings 2>/dev/null | ${pkgs.coreutils}/bin/cut -f1)
      CLIPS_SIZE=$(${pkgs.coreutils}/bin/du -sh /mnt/media/surveillance/frigate/clips 2>/dev/null | ${pkgs.coreutils}/bin/cut -f1)
      echo "Frigate cleanup complete - Recordings: $RECORDINGS_SIZE, Clips: $CLIPS_SIZE"
    '';
  };

  # Native Media Services now handled by Charter-compliant domain modules
  # - hwc.media.jellyfin via server profile
  # - hwc.media.immich via server profile (NOT AVAILABLE in stable 24.05 - module disabled)
  # - hwc.media.navidrome via server profile

  # Navidrome configuration handled by server profile native service

  # Reverse proxy domain handled by server profile

  # Monitoring enabled via profiles/monitoring.nix import (direct enablement, no hwc.features gate)

  # Enhanced SSH configuration for server
  services.openssh.settings = {
    X11Forwarding = lib.mkForce false;  # Headless server doesn't need X11 forwarding
    PasswordAuthentication = lib.mkForce true;  # Temporary - for SSH key update
  };

  # Session config for headless server (no login manager, just sudo)
  hwc.system.core.session = {
    enable = true;
    sudo.enable = true;
    sudo.wheelNeedsPassword = false;  # Passwordless sudo for wheel group
    sudo.extraRules = [
      {
        users = [ "eric" ];
        commands = [
          { command = "/run/current-system/sw/bin/podman"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/systemctl"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/journalctl"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
    # Enable lingering so rootless podman containers run when not logged in
    linger.enable = true;
    linger.users = [ "eric" ];
  };
  services.tailscale.permitCertUid = lib.mkIf config.services.caddy.enable "caddy";
  # X11 services disabled for headless server
  # services.xserver.enable = true;

  # Server-specific packages
  hwc.system.core.packages.server.enable = true;

  #============================================================================
  # SHARED DIRECTORY (NFS export for laptop access over Tailscale)
  #============================================================================
  systemd.tmpfiles.rules = [
    "d ${config.hwc.paths.user.shared} 0755 eric users -"
  ];

  #============================================================================
  # STORAGE PATHS
  #============================================================================
  hwc.paths = {
    hot.root = "/mnt/hot";      # SSD hot storage
    media.root = "/mnt/media";  # HDD media storage
  };

  #============================================================================
  # CONTAINER RUNTIME
  #============================================================================
  virtualisation = {
    docker.enable = lib.mkForce false;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers.backend = "podman";
  };

  #============================================================================
  # PERFORMANCE TUNING
  #============================================================================
  boot.kernel.sysctl = {
    "vm.dirty_ratio" = lib.mkDefault 15;
    "vm.dirty_background_ratio" = lib.mkDefault 5;
    "vm.swappiness" = lib.mkDefault 10;
  };

  # I/O scheduler optimizations for server workloads
  services.udev.extraRules = lib.mkAfter ''
    ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd*", ENV{ID_BUS}=="ata", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd*", ENV{ID_BUS}=="ata", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
  '';

  # SMART disk monitoring
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
    defaults.monitored = "-a -o on -s (S/../.././02|L/../../6/03)";
  };

  # Enhanced logging for server
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    RuntimeMaxUse=200M
    SystemMaxFileSize=100M
    MaxRetentionSec=1month
  '';

  # Log rotation for container logs
  services.logrotate.settings.docker = {
    files = [ "/var/lib/docker/containers/*/*.log" ];
    frequency = "daily";
    rotate = 7;
    compress = true;
    missingok = true;
    notifempty = true;
    sharedscripts = true;
  };

  #============================================================================
  # REVERSE PROXY
  #============================================================================
  hwc.networking.reverseProxy = {
    enable = lib.mkDefault true;
    domain = "hwc.ocelot-wahoo.ts.net";
  };

  #============================================================================
  # SERVICE ENABLEMENT
  #============================================================================

  # Download stack (VPN + clients)
  hwc.networking.gluetun = {
    enable = lib.mkDefault true;
    portForwarding = {
      enable = lib.mkDefault true;
      syncToQbittorrent = lib.mkDefault true;
      checkInterval = 60;
    };
  };
  hwc.media.qbittorrent.enable = lib.mkDefault true;
  hwc.media.sabnzbd.enable = lib.mkDefault true;
  hwc.media.mousehole.enable = lib.mkDefault true;

  # *arr stack
  hwc.media.prowlarr.enable = lib.mkDefault true;
  hwc.media.sonarr.enable = lib.mkDefault true;
  hwc.media.radarr.enable = lib.mkDefault true;
  hwc.media.lidarr.enable = lib.mkDefault true;
  hwc.media.readarr.enable = lib.mkDefault true;
  hwc.media.books.enable = lib.mkDefault true;
  hwc.media.calibre.enable = lib.mkDefault true;
  hwc.media.audiobookshelf.enable = lib.mkDefault true;
  hwc.media.orchestration.audiobookCopier.enable = lib.mkDefault true;

  # Beets music organizer (using native installation)
  hwc.media.beets.enable = false;

  # Media discovery + download management
  hwc.media.jellyseerr.enable = lib.mkDefault true;
  hwc.media.slskd.enable = lib.mkDefault true;
  hwc.media.soularr.enable = lib.mkDefault true;

  # Video transcoding (disabled — high resource usage)
  hwc.media.tdarr.enable = false;
  hwc.media.recyclarr = {
    enable = lib.mkDefault true;
    services.lidarr.enable = false;
  };
  hwc.media.organizr.enable = lib.mkDefault true;
  hwc.media.pinchflat.enable = lib.mkDefault true;

  # Native media services
  hwc.media.jellyfin = {
    enable = lib.mkDefault true;
    openFirewall = false;
    reverseProxy = {
      enable = true;
      path = "/media";
      upstream = "localhost:8096";
    };
    gpu.enable = true;
    apiKey = "26d513d02f27467aa94d70e4b43688f8";
    users.eric.maxActiveSessions = 0;
  };

  # RetroArch emulation with Sunshine game streaming
  hwc.gaming.retroarch = {
    enable = lib.mkDefault true;
    gpu.enable = true;
    cores = {
      dosbox-pure = true;
      snes9x = true;
      mgba = true;
      mupen64plus = true;
      genesis-plus-gx = true;
      nestopia = true;
      beetle-psx-hw = true;
      flycast = true;
    };
    sunshine = {
      enable = true;
      openFirewall = true;
      capSysAdmin = true;
    };
  };

  # WebDAV for RetroArch save sync
  hwc.gaming.webdav = {
    enable = lib.mkDefault true;
    auth = {
      usernameFile = config.hwc.secrets.api.webdavUsernameFile;
      passwordFile = config.hwc.secrets.api.webdavPasswordFile;
    };
    retroarch = {
      enable = true;
      syncSaves = true;
      syncStates = true;
    };
    reverseProxy = {
      enable = true;
      path = "/retroarch-sync";
    };
  };

  # Firefly III personal finance
  hwc.business.firefly = {
    enable = lib.mkDefault true;
  };

  #============================================================================
  # WEB APPS DOMAIN
  #============================================================================
  # hwc-publish: deploy static apps instantly, no rebuild needed.
  # Reserved range: 14000–14099 (on tailscale0)
  # Usage: hwc-publish <name> <dist/> [--port N]
  hwc.webapps.enable = true;

  # Heartwood Estimate Assembler — React PWA
  # Port 13443 is pre-allocated outside the hwc-publish range (intentional —
  # the estimator is a first-class named app, not an ad-hoc published slot).
  # Access: https://hwc.ocelot-wahoo.ts.net:13443
  # Build:  cd ~/.nixos/workspace/business/estimator-pwa && npm install && npm run build
  hwc.business.estimator = {
    enable  = true;
    distDir = "/home/eric/.nixos/workspace/business/estimator-pwa/dist";
    port    = 13443;
  };

  # Immich photo management (container-based)
  hwc.media.immich = {
    enable = lib.mkDefault true;
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
      host = "127.0.0.1";
      port = 5432;
      name = "immich";
      user = "eric";
    };
    redis = {
      enable = true;
      host = "127.0.0.1";
      port = 6380;
    };
    gpu.enable = true;
    machineLearning.enable = true;
    observability.metrics.enable = true;
    network.mode = "host";
  };

  # YouTube services
  hwc.media.youtube.legacyApi = {
    enable = lib.mkDefault true;
    port = 8099;
    dataDir = "/home/eric/01-documents/01-vaults/04-transcripts";
  };
  hwc.media.youtube.transcripts = {
    enable = lib.mkDefault false;
    port = 8100;
    workers = 4;
    outputDirectory = "/mnt/hot/youtube-transcripts";
  };
  hwc.media.youtube.videos = {
    enable = lib.mkDefault false;
    port = 8101;
    workers = 2;
    outputDirectory = "/mnt/media/youtube";
  };

  # PostgreSQL (always enabled — used by many services)
  # Version pinned to 15 in domains/data/databases/index.nix (data format lock)
  hwc.data.databases.postgresql = {
    enable = lib.mkDefault true;
    version = "15";
    backup.perDatabase = {
      enable = true;
      databases = [ "hwc" ];
      # outputDir = "/home/eric/backups/postgres";  # default
      # retentionDays = 30;  # default
      # schedule = "*-*-* 02:30:00";  # default (2:30 AM)
    };
  };

  # CloudBeaver - web-based database manager (access via port 12443)
  hwc.data.cloudbeaver.enable = lib.mkDefault true;

  # Storage automation
  hwc.data.storage = {
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

  # Headless server — minimal Home Manager (CLI only, no GUI)
  # Server does NOT import session.nix, so no GUI defaults are inherited.
  # Only CLI tools needed for server administration.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.eric = {
      imports = [ ../../domains/home/index.nix ];
      home.stateVersion = "24.05";

      hwc.home = {
        # CLI tools only
        shell = {
          enable = true;
          modernUnix = true;
          git.enable = true;
          zsh = {
            enable = true;
            starship = true;
            autosuggestions = true;
            syntaxHighlighting = true;
          };
        };

        development.enable = true;

        # No GUI, no mail, no theme
        mail.enable = false;
        theme.fonts.enable = false;

        # CLI-only apps
        apps = {
          gpg.enable = true;
          codex.enable = true;
          aider.enable = true;
          gemini-cli.enable = true;
        };
      };

      # Disable desktop services
      targets.genericLinux.enable = false;
      dconf.enable = lib.mkForce false;
      services.mako.enable = lib.mkForce false;
    };
  };

  system.stateVersion = "24.05";
}
