# nixos-hwc/machines/server/config.nix
#
# MACHINE: HWC-SERVER
# Declares machine identity and composes profiles; states hardware reality.

{ config, lib, pkgs, inputs ? null, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/system.nix
    ../../profiles/home.nix
    ../../profiles/server.nix
    ../../profiles/security.nix
    ../../profiles/ai.nix
    ../../domains/server/native/routes.nix
    ../../domains/server/native/frigate/index.nix  # Config-first pattern NVR with GPU acceleration
    ../../profiles/monitoring.nix   # Monitoring enabled: Prometheus + Grafana
    # ../../profiles/media.nix         # TODO: Fix sops/agenix conflict in orchestrator
    ../../profiles/business.nix
    ../../profiles/alerts.nix        # Centralized alert routing to Slack via n8n
  ];

  # CHARTER v9.0: Hard enforcement that server MUST use stable nixpkgs
  assertions = [
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
  hwc.server = {
    enable = true;
    role = "primary";  # Main production server - all services enabled
  };

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

  # Storage infrastructure configuration (Charter v6.0 compliant)
  hwc.infrastructure.storage = {
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
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
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
    firewall.level = lib.mkForce "server";
    firewall.extraTcpPorts = [ 8096 7359 2283 4533 ];  # Jellyfin, Immich, Navidrome
    firewall.extraUdpPorts = [ 7359 ];  # Jellyfin discovery
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

  # ntfy notification system CLI client for server alerts
  # Multi-topic architecture: critical, alerts, backups, media, monitoring, updates, ai
  # See: docs/infrastructure/ntfy-notification-classes.md
  hwc.system.services.ntfy = {
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

  # Backup configuration for server
  # Backs up IRREPLACEABLE data to ZFS mirror every 3 days
  # NixOS config excluded - it's a git repo (github.com)
  hwc.system.services.backup = {
    enable = true;

    # Local backup to ZFS mirror (sdd/sde)
    local = {
      enable = true;
      mountPoint = "/mnt/backup";
      keepDaily = 10;   # ~1 month at 3-day intervals
      keepWeekly = 4;   # 1 month of weekly snapshots
      keepMonthly = 6;  # 6 months of monthly snapshots
      minSpaceGB = 100; # Require 100GB free before backup

      # IRREPLACEABLE data only - config is in git
      sources = lib.mkForce [
        "/mnt/media/surveillance/frigate"  # Security camera recordings
        "/mnt/media/photos"                # Immich photos (CRITICAL)
        "/var/lib/hwc"                     # Service state directories
      ];

      excludePatterns = [
        ".cache"
        "*.tmp"
        "*.temp"
        "node_modules"
        "__pycache__"
      ];
    };

    # Database dumps before backup (PostgreSQL + CouchDB)
    # Uses /run/current-system/sw/bin paths for tools (always available)
    preBackupScript = ''
      DUMP_DIR="/mnt/backup/hwc-server/database-dumps"
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
        # URL-encode special characters in password
        COUCH_PASS=$(printf '%s' "$COUCH_PASS_RAW" | $JQ -sRr @uri)
        if [ -n "$COUCH_PASS" ]; then
          for db in $($CURL -sf "http://$COUCH_USER:$COUCH_PASS@127.0.0.1:5984/_all_dbs" | $JQ -r '.[]' 2>/dev/null | grep -v "^_"); do
            $CURL -sf "http://$COUCH_USER:$COUCH_PASS@127.0.0.1:5984/$db/_all_docs?include_docs=true" > "$DUMP_DIR/couchdb-$db-$DATE.json" 2>/dev/null || echo "CouchDB $db dump failed"
          done
        fi
      fi

      # Cleanup old dumps (keep 30 days)
      find "$DUMP_DIR" -name "*.sql" -mtime +30 -delete 2>/dev/null || true
      find "$DUMP_DIR" -name "*.json" -mtime +30 -delete 2>/dev/null || true
      echo "Database dumps complete"
    '';

    # Cloud backup disabled
    cloud.enable = false;
    protonDrive.enable = false;

    # Every 3 days at 3 AM (Mon, Thu, Sun)
    schedule = {
      enable = true;
      frequency = lib.mkForce "Mon,Thu,Sun";
      timeOfDay = lib.mkForce "03:00";
      onlyOnAC = lib.mkForce false;
    };

    # Notifications via alerts domain (Slack)
    notifications = {
      enable = false;
      ntfy.enable = false;
    };
  };

  # Borg Backup - Primary deduplicating backup (daily)
  # Rsync above is fallback (Mon/Thu/Sun)
  hwc.system.services.borg = {
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
  hwc.infrastructure.hardware.gpu = {
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
    # Note: gsp option doesn't exist in NixOS 24.05 (added in later versions for newer GPUs)
  };

  # NVIDIA license acceptance handled in flake.nix

  # GPU acceleration for Immich handled by hwc.server.native.immich.gpu.enable in server profile

  # AI DOMAIN CONFIGURATION (Server)
  #============================================================================
  # Profile auto-detection: server (GPU: nvidia, RAM: 32GB >= 16GB threshold)
  # Result: Relaxed limits (4 cores, 8GB, 80°C warning, 90°C critical)
  hwc.ai = {
    enable = true;

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

  # Server-backup DISABLED - NixOS config is in git, databases handled by backup-local preBackupScript
  # Container volumes (music) too large and replaceable - not worth backing up
  hwc.server.native.backup.enable = false;

  # TEMPORARY: Disable navidrome due to pkg-config build failure in NixOS 25.11
  # Error: github.com/navidrome/navidrome/adapters/taglib: invalid flag in pkg-config --cflags: --define-prefix
  hwc.server.native.navidrome.enable = lib.mkForce false;
  hwc.server.containers.navidrome.enable = true;
  # Enable AI router and agent on server
  hwc.ai.router = {
    enable = true;
    port = 11435;
  };
  hwc.ai.agent = {
    enable = true;
    port = 6020;
  };
  # CouchDB for Obsidian LiveSync
  hwc.server.native.couchdb = {
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
  # Provides push notification server for alerts and webhooks
  hwc.alerts.server = {
    enable = true;  # ENABLED - provides notification capabilities
    port = 2586;    # Match routes.nix and Tailscale expectations
    dataDir = "/var/lib/hwc/ntfy";
  };

  # Frigate NVR (Config-First Pattern with GPU Acceleration)
  # Access: https://hwc.ocelot-wahoo.ts.net:5443 (via Caddy)
  # Charter v7.0 Section 19 compliant - TensorRT CUDA support
  hwc.server.native.frigate = {
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
  # - hwc.server.native.jellyfin via server profile
  # - hwc.server.native.immich via server profile (NOT AVAILABLE in stable 24.05 - module disabled)
  # - hwc.server.native.navidrome via server profile

  # Navidrome configuration handled by server profile native service

  # Reverse proxy domain handled by server profile

  # Feature enablement
  hwc.features = {
    monitoring.enable = true;     # Prometheus + Grafana monitoring stack
    # media.enable = true;        # TODO: Fix sops/agenix conflict
    # business.enable = true;     # TODO: Enable when business containers are implemented
  };

  # Enhanced SSH configuration for server
  services.openssh.settings = {
    X11Forwarding = lib.mkForce false;  # Headless server doesn't need X11 forwarding
    PasswordAuthentication = lib.mkForce true;  # Temporary - for SSH key update
  };

  # Passwordless sudo for ai-chat tool commands and grebuild workflow
  hwc.system.services.session.sudo.extraRules = [
    {
      users = [ "eric" ];
      commands = [
        { command = "/run/current-system/sw/bin/podman"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/journalctl"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];
  services.tailscale.permitCertUid = lib.mkIf config.services.caddy.enable "caddy";
  # X11 services disabled for headless server
  # services.xserver.enable = true;

  # Server-specific packages moved to modules/system/server-packages.nix
  hwc.system.core.packages.server.enable = true;

  # I/O scheduler and journald configuration moved to profiles/server.nix to avoid duplication
  # This eliminates conflicts between machine and profile configurations

  # Emergency access via security domain (safer than machine-level overrides)
  # hwc.secrets.emergency.enable is handled by security profile

  # Override home profile for headless server - only CLI/shell tools
  home-manager.users.eric = {
    # Disable all GUI applications for headless server
    hwc.home.apps = {
      # Desktop Environment (disable all)
      hyprland.enable = lib.mkForce false;
      waybar.enable = lib.mkForce false;
      swaync.enable = lib.mkForce false;
      kitty.enable = lib.mkForce false;

      # File Management (disable GUI, disable CLI to avoid cross-version issues)
      thunar.enable = lib.mkForce false;
      yazi.enable = lib.mkForce false;  # Disabled: cross-version poppler package issue

      # Web Browsers (disable all)
      chromium.enable = lib.mkForce false;
      librewolf.enable = lib.mkForce false;

      # Mail Clients (disable CLI to avoid cross-version issues, disable GUI)
      aerc.enable = lib.mkForce false;  # Disabled: cross-version poppler package issue
      # neomutt.enable remains true (CLI tool)
      betterbird.enable = lib.mkForce false;
      proton-mail.enable = lib.mkForce false;
      thunderbird.enable = lib.mkForce false;

      # Security (keep CLI tools)
      # gpg.enable remains true

      # Proton Suite (disable GUI)
      proton-authenticator.enable = lib.mkForce false;
      proton-pass.enable = lib.mkForce false;

      # Productivity & Office (disable all)
      obsidian.enable = lib.mkForce false;
      onlyoffice-desktopeditors.enable = lib.mkForce false;

      # Creative & Media (disable all GUI)
      blender.enable = lib.mkForce false;
      freecad.enable = lib.mkForce false;  # Build fails on 24.05 - patch issue

      # Development & Automation (keep CLI)
      n8n.enable = lib.mkForce false;
      opencode.enable = lib.mkForce false;  # Not available in stable 24.05
      # gemini-cli.enable remains true (CLI tool)
      codex.enable = lib.mkForce true;  # Pinned via flake input (openai/codex rust-v0.101.0)
      aider.enable = lib.mkForce true;  # AI pair-programming CLI for cloud and local Ollama models

      # Utilities (disable GUI)
      wasistlos.enable = lib.mkForce false;
      bottles-unwrapped.enable = lib.mkForce false;
      localsend.enable = lib.mkForce false;
    };

    # Keep shell/CLI configuration enabled
    hwc.home.shell.enable = true;
    hwc.home.development.enable = true;

    # Disable mail for server (no GUI mail needed)
    hwc.home.mail.enable = lib.mkForce false;

    # Disable desktop features for headless server
    hwc.home.theme.fonts.enable = lib.mkForce false;

    # Disable desktop services that try to use dconf
    targets.genericLinux.enable = false;
    dconf.enable = lib.mkForce false;

    # Disable Wayland notification daemon (version incompatibility with stable)
    # Mako module from HM unstable expects APIs not in nixpkgs-stable 24.05
    services.mako.enable = lib.mkForce false;
  };

  system.stateVersion = "24.05";
}
