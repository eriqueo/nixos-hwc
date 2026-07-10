# nixos-hwc/machines/server/config.nix
#
# MACHINE: HWC-SERVER
# Declares machine identity and composes profiles; states hardware reality.
{
  config,
  lib,
  pkgs,
  inputs ? null,
  ...
}: {
  imports = [
    ./hardware.nix

    # Roles (base, server, business, monitoring, mail) are supplied by the
    # flake.nix machines table — membership lives there, not here.

    ../../domains/ai/index.nix
    ../../domains/networking/index.nix
    ../../domains/data/index.nix
    ../../domains/media/index.nix
    ../../domains/notifications/index.nix # Notification delivery (webhooks, CLI)
    ../../domains/gaming/index.nix # Retroarch emulation + WebDAV save sync
    ../../domains/server/containers/_shared/directories.nix
    ../../domains/server/native/ai/lead-scout/index.nix # Lead Scout MCP + HTTP
    ../../domains/server/native/ai/brain-mcp/index.nix # Brain MCP Server (Deno)
    ../../domains/server/native/ai/hermes/index.nix # Hermes Agent (Nous Research)
    ../../domains/server/native/ai/market-intelligence/index.nix # Market Intelligence (earnings signals + dashboard)
    ../../domains/server/native/ai/llama-cpp/index.nix # llama.cpp inference (GPU + CPU + embed)
    ../../domains/server/native/ai/persona-daemon/index.nix # Persona-aware HTTP daemon + SQLite memory
    ../../domains/server/services/inbox-processor/index.nix # Phone capture processor (Whisper + Tesseract)
    ../../domains/server/services/bloxels-cv/index.nix # Bloxels grid photo classifier (path watcher)
    ../../domains/server/services/radicale/index.nix # Self-hosted CalDAV (tasks.hwc.*)
    ../../domains/server/deploy/index.nix # `deploy` — one-step deploy CLI for 600_apps
  ];

  assertions = [
    # Server role assertions
    {
      assertion = (
        (config.hwc.paths.hot.root != null && lib.hasPrefix "/mnt" config.hwc.paths.hot.root)
        || (config.hwc.paths.media.root != null && lib.hasPrefix "/mnt" config.hwc.paths.media.root)
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
      assertion =
        !config.services.postgresql.enable
        || (
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

  # Lead Scout — Facebook group lead scraper/classifier, MCP + HTTP on port 8420
  hwc.server.ai.leadScout.enable = true;

  # `deploy` — interactive one-step deploy CLI; auto-discovers ~/600_apps/*/deploy.sh
  hwc.server.deploy.enable = true;

  # Brain MCP Server — vault filesystem tools (read/write/search/lint) on port 9876
  hwc.server.ai.brainMcp.enable = true;

  # Phone Capture Processor (Phase 10: Whisper STT + Tesseract OCR)
  # Watches inbox-mobile/{audio,screenshots} and writes markdown to brain/inbox/
  hwc.server.services.inboxProcessor = {
    enable = true;
    audioInboxPath = "${config.hwc.paths.brain."inbox-mobile"}/audio";
    screenshotsInboxPath = "${config.hwc.paths.brain."inbox-mobile"}/screenshots";
    brainInboxPath = "${config.hwc.paths.brain."server-replica"}/inbox";
    processedPath = "${config.hwc.paths.brain."inbox-mobile"}/processed";
    whisperModel = "base.en";
  };

  # Bloxels CV — classify phone photos of the printed 13x13 Bloxels grid.
  # Watches inbox-mobile/bloxels; writes results/<photo>/{grid.json,debug.png}
  # back into the share so Syncthing returns them to the phone.
  hwc.server.services.bloxelsCv = {
    enable = true;
    package = inputs.bloxels-cv.packages.${pkgs.system}.default;
    watchPath = "${config.hwc.paths.brain."inbox-mobile"}/bloxels";
  };

  # Radicale — self-hosted CalDAV for two-way task sync with list creation
  # (todui N key). Behind Caddy at tasks.hwc.iheartwoodcraft.com. Requires the
  # radicale-htpasswd agenix secret (domains/secrets/parts/services/).
  hwc.server.services.radicale = {
    enable = true;
    reverseProxy.enable = true;
  };

  # ZFS support for backup drives
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # Note: boot.initrd.systemd.fido2 doesn't exist in stable 24.05 (added in later versions)

  # ZFS configuration (scrub/trim hygiene comes from the server role)
  boot.zfs.extraPools = ["backup-pool"]; # Auto-import backup pool on boot

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
    media.enable = true; # Directory management only (mount defined below)
    backup.enable = true; # Enable backup drive automation
  };

  # Media storage mount (infrastructure module manages directories only)
  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-label/media";
    fsType = "ext4";
  };

  # Time zone (from production)
  time.timeZone = "America/Denver";

  # CUDA binary cache comes from the gpu module (nvidia machines only);
  # experimental-features and cache.nixos.org come from the base role.
  # allowUnfree set in flake.nix

  # --- Networking Configuration (Server: DO wait for network) ---
  hwc.system.networking = {
    enable = true;
    networkManager.enable = true;

    # Safest: wait for any NetworkManager connection (no hard-coded iface names).
    waitOnline.mode = "all";
    waitOnline.timeoutSeconds = 30; # Reduced from 90s for faster boot

    ssh.enable = true;
    tailscale.enable = true;
    tailscale.extraUpFlags = ["--advertise-tags=tag:server" "--accept-routes"];
    # firewall.level = "server" comes from the server role
    firewall.extraTcpPorts = [
      22000 # Syncthing sync
      # Media services
      5000 # Frigate
      8080 # qBittorrent (via Gluetun)
      7878 # Radarr
      8989 # Sonarr
      8686 # Lidarr
      8787 # Readarr
      9696 # Prowlarr
      5055 # Jellyseerr
      4533 # Navidrome
      8096 # Jellyfin
      2283 # Immich
      8081 # SABnzbd
      5030 # SLSKD
      # Business services
      8888 # Receipt API
      8501 # Streamlit apps
      5432 # PostgreSQL (internal)
      6379 # Redis (internal)
      # Monitoring services
      3000 # Grafana
      9090 # Prometheus
      9093 # Alertmanager
      # Calibre VNC
      5909 # Calibre desktop VNC
      # YouTube
      8943 # Pinchflat (YouTube subscriptions)
      # Game streaming (Sunshine)
      47984
      47989
      47990 # Sunshine HTTPS, Web UI, RTSP
      48010 # Sunshine video stream
      7359 # Jellyfin discovery (also UDP)
    ];
    firewall.extraUdpPorts = [
      22000 # Syncthing sync (QUIC)
      21027 # Syncthing local discovery
      7359 # Jellyfin discovery
      50300 # SLSKD
      8555 # Frigate
      # Game streaming (Sunshine)
      47998
      47999
      48000
      48010
    ];
  };

  # Syncthing — bidirectional home folder sync with hwc-laptop
  hwc.data.syncthing = {
    enable = true;
    devices."hwc-laptop".id = "H3EVGHN-DTDTMWS-INSC2RH-PBRABJX-M3FW7AM-3P2NY3M-X5XLYCK-JD2YRQG";
    devices."hwc-phone".id = "ROLZBPO-HN33OQP-E4DV5PD-34ZVSIP-I5USNNW-NHHOPKC-APNQNSH-BX7OMQN";
    folders = {
      "000_inbox" = {
        path = "/home/eric/000_inbox";
        devices = ["hwc-laptop"];
      };
      "100_hwc" = {
        path = "/home/eric/100_hwc";
        devices = ["hwc-laptop"];
      };
      "200_personal" = {
        path = "/home/eric/200_personal";
        devices = ["hwc-laptop"];
      };
      "300_tech" = {
        path = "/home/eric/300_tech";
        devices = ["hwc-laptop"];
      };
      "700_datax" = {
        path = "/home/eric/700_datax";
        devices = ["hwc-laptop"];
      };
      # 600_apps: removed from Syncthing 2026-06-16. Each app inside is now its
      # own git repo (server hub for workbench/todui/khalt; GitHub for
      # kidpix/lead_scout/sr_analyzer) — bidirectional sync over live .git trees
      # was producing .sync-conflict corruption in lead_scout/sr_analyzer. git is
      # the only sync now; the dir stays on disk, just unsynced.
      "brain" = {
        path = "/home/eric/900_vaults/brain";
        # Tier-2: git is the only laptop<->server vault sync (see
        # hwc.automation.vaultSync). Syncthing's sole remaining job here is to
        # feed the receive-only phone mirror, so the server is the sole sender
        # (sendonly) and the laptop is NOT a peer. sendonly guarantees a stale
        # phone can never push vault changes back and clobber the source.
        devices = ["hwc-phone"];
        type = "sendonly";
        # Vault is a git repo: .git MUST be excluded or Syncthing replicates
        # git internals and a stale peer can clobber committed history.
        ignores = [
          ".git"
          ".obsidian/workspace.json"
          ".obsidian/workspace-mobile.json"
          ".obsidian/plugins/*/data.json"
          ".trash/"
          ".DS_Store"
        ];
      };
      "screenshots" = {
        path = "/home/eric/500_media/510_pictures/screenshots";
        devices = ["hwc-laptop"];
      };
      # Phone capture inbox (Phase 9: Mobius Sync). Phone device added after pairing.
      "inbox-mobile" = {
        path = "/mnt/vaults/inbox-mobile";
        devices = ["hwc-phone"];
      };
    };
  };

  # MQTT broker (Frigate -> n8n bridge) comes from the business role.

  # Notifications delivery infrastructure
  hwc.notifications = {
    enable = true;
    send.cli.enable = true; # CLI tool for manual alerts

    # hwc-notify — hexagonal TS dispatcher (Phase 1 complete 2026-05-31).
    # Primary alert / lead notification path. Replaces the n8n
    # home:admin:alert-manager workflow. See README.md in
    # domains/notifications/notify and the architecture note in
    # wiki/nixos/hwc-notify-architecture.md.
    notify.enable = true;
    canary.enable = true;  # daily deadman probe over Discord + SMTP
  };

  # README freshness — weekly Law-12 drift report (Mon 09:00) → #nightly-builds
  # Discord channel. Lives here (not the server profile) because it POSTs to
  # hwc-notify, which is a hwc-server one-off enabled just above.
  hwc.automation.readmeFreshness.enable = true;

  # SR Gauntlet — daily (06:30, 7d/wk) read-only investigation of open DataX
  # SRs → per-SR REPORT.md + Discord delivery. Lives here (not the server
  # profile) because the pipeline checkout (~/700_datax/sr_gauntlet) and its
  # credential sources only exist on hwc-server.
  hwc.automation.srGauntlet.enable = true;

  # Brain vault git sync — Tier-2 transport. Every 15 min: commit local vault
  # changes, pull the hub (laptop's commits), push server changes up. Replaces
  # Syncthing as the laptop<->server vault path. Serialized with brain-mcp via
  # an flock on <vault>/.git/.sync.lock.
  hwc.automation.vaultSync.enable = true;

  # Inbox janitor — every 30 min, drain loose files at the root of
  # ~/000_inbox/downloads per ~/000_inbox/_inbox-routing.yaml (datax stays,
  # business/tech/personal drain to the home PARA dirs, secrets/junk quarantine,
  # unmatched → _review). Server-only by design: ~/000_inbox is a multi-writer
  # Syncthing tree, so a single host owns the routing pass (same rationale as
  # vaultSync's single-writer hub). Ships dryRun=true — watch the journal, then
  # set hwc.automation.inboxJanitor.dryRun = false.
  hwc.automation.inboxJanitor.enable = true;
  hwc.automation.inboxJanitor.dryRun = false;

  # mail-janitor — weekly age-aware Gmail anti-buildup sweep. Trashes NOISE
  # (promo/streaming/social/bot) at any age + TRANSACTIONAL (receipts/orders)
  # older than 1yr; PRESERVE (people/history/finance) and the Family-Friends
  # label are never touched. Ships dryRun=true — watch the Discord report +
  # journal, then set hwc.automation.mailJanitor.dryRun = false to let it act.
  hwc.automation.mailJanitor.enable = true;
  hwc.automation.mailJanitor.dryRun = false;  # active after dry-run verified 2026-06-24
  # Unified lead pipeline comes from the business role.

  # Alert sources — what to monitor (thresholds, triggers)
  hwc.monitoring.alerts = {
    enable = true;

    # Disk-space monitoring is owned by Prometheus alerts
    # (domains/monitoring/prometheus/parts/alerts.nix). The legacy script-based
    # diskSpace source was retired 2026-06-04.

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
      onSuccess = false; # Don't spam on success
      onFailure = true; # Always alert on failure
    };
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
      "/mnt/media/photos" # Immich photos (CRITICAL)
      "/var/lib/hwc" # Service state directories
      "/var/lib/backups" # Database dumps
    ];

    excludePatterns = [
      ".cache"
      "*.tmp"
      "*.temp"
      "node_modules"
      "__pycache__"
      "*.log"
      # Immich regenerable data — rebuilt automatically from originals
      "/mnt/media/photos/thumbs"
      "/mnt/media/photos/encoded-video"
      # Live PostgreSQL data files — already backed up via pg_dumpall in preHook
      # Backing up raw PG files causes "file changed" warnings that fail the job
      "/var/lib/hwc/postgresql"
      # Prometheus TSDB — regenerable from scrape targets, churns heavily
      "/var/lib/hwc/prometheus"
      # Jellyfin metadata/logs — regenerated from library scan
      "/var/lib/hwc/jellyfin/metadata"
      "/var/lib/hwc/jellyfin/log"
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
        # --rsyncable keeps borg dedup effective across daily compressed dumps
        /run/wrappers/bin/su - postgres -s /bin/sh -c "/run/current-system/sw/bin/pg_dumpall 2>/dev/null" | /run/current-system/sw/bin/gzip --rsyncable > "$DUMP_DIR/postgresql-$DATE.sql.gz" || echo "PostgreSQL dump failed"
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
      # *.sql matches legacy uncompressed dumps until they age out
      find "$DUMP_DIR" -name "*.sql" -mtime +14 -delete 2>/dev/null || true
      find "$DUMP_DIR" -name "*.sql.gz" -mtime +14 -delete 2>/dev/null || true
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
      driver = "stable"; # Use stable as base, override package below
      containerRuntime = true;
      enableMonitoring = true;
    };
  };

  # P1000 (Pascal) with driver 580 - last full-support branch before legacy transition
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable; # 580.95.05
    open = lib.mkForce false; # Pascal doesn't support open-source modules
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
  };

  # MCP (Model Context Protocol) server infrastructure
  # Parent MCP disabled (mcp-proxy not in nixpkgs-stable), but heartwood is self-contained
  hwc.ai.mcp.enable = lib.mkForce false;
  hwc.system.mcp.enable = true;
  hwc.system.mcp.jt.enable = true;
  hwc.system.mcp.host = "0.0.0.0"; # Arka containers need access via 10.89.1.1

  # Note: Backup is configured above (hwc.data.backup block at line ~304)
  # NixOS config excluded - it's in git. Databases handled by preBackupScript.

  # Navidrome music streaming (container)
  hwc.media.navidrome.enable = true;
  hwc.ai.agent = {
    enable = true;
    port = 6020;
  };

  # NanoClaw AI agent orchestrator
  # Connects to Slack via Socket Mode, spawns agents in containers
  # NanoClaw — disabled 2026-05-29; superseded by hwc.server.ai.hermes (below).
  # Module moved to domains/ai/.nanoclaw-disabled/; secret declarations remain
  # (nanoclaw-anthropic-key.age is reused by Hermes via re-named logical secret).
  # hwc.ai.nanoclaw = { enable = false; slack.enable = false; };

  # llama.cpp inference — three services share one binary
  # GPU:   LFM2-2.6B Q4 (~1.5 GB)  on  26443 -> 127.0.0.1:11500
  # CPU:   LFM2-24B-A2B Q4 (~14 GB) on  27443 -> 127.0.0.1:11501
  # Embed: nomic-embed-text-v1.5 Q5 (~270 MB)        127.0.0.1:11502
  hwc.server.ai.llamaCpp = {
    enable = true;
    # Local llama-cpp rebuild with sm_61 added — required because the cached
    # CUDA binary at cache.nixos-cuda.org targets sm_75+ only and aborts on
    # the Quadro P1000 (compute 6.1) with "no kernel image is available".
    cudaCapabilities = ["6.1"];
    gpu.enable = true;
    cpu = {
      enable = true;
      threads = 6; # one per physical core on i7-8700K; HT rarely helps memory-bound inference
      # Hermes Agent rejects models with n_ctx < 64K with a ValueError
      # ("below the minimum 64,000 required"). LFM2-24B-A2B's n_ctx_train
      # is 128K (per the GGUF metadata), and its hybrid attention keeps
      # KV cache near-constant: at 8K context the KV buffer was 161 MB,
      # so 64K only adds ~1.3 GB — well within the 38 GB free here.
      contextSize = 65536;
      # --jinja enables OpenAI-compatible tool/function calling (llama.cpp
      # returns 500 "tools param requires --jinja flag" without it). --alias
      # gives the endpoint a stable model name instead of the raw GGUF path,
      # so Hermes' chat completions request can use model="lfm2-24b".
      extraArgs = ["--jinja" "--alias" "lfm2-24b"];
    };
    embed.enable = true; # powers RAG retrieval over /mnt/vaults/brain (persona-daemon, Phase 2.5)
  };

  # hwc-llm — persona CLI that wraps the llama-server endpoints with a
  # curated system-prompt library. Stateless by default; --conversation
  # routes through persona-daemon below. See domains/ai/personas/README.md.
  hwc.ai.personas.enable = true;

  # persona-daemon (Deno) — OpenAI-compatible HTTP on 127.0.0.1:11550 plus
  # SQLite conversation memory. Commit 2 ships conversations only;
  # RAG over /mnt/vaults/brain arrives in Commit 3. Caddy + MCP in Commit 4.
  hwc.server.ai.personaDaemon.enable = true;

  # Hermes Agent — official nousresearch/hermes-agent Podman container.
  # Re-architected 2026-06-03 from a bespoke native multi-unit deployment to
  # the supported container: gateway + dashboard supervised together by s6 in
  # one writable /opt/data, so the in-app controls (chat tab, restart) work as
  # designed. Model is DeepSeek V4 via OPENAI_BASE_URL/HERMES_MODEL; the API
  # key + Discord token are injected from agenix at container start.
  hwc.server.ai.hermes = {
    enable = true;
    gateway.enable = true;
    gateway.discord.enable = true;
    gateway.discord.allowedUsers = "1501391621521150075"; # Eric's Discord snowflake
    model.provider = "deepseek"; # native Hermes provider; base URL built in
    model.modelName = "deepseek-v4-pro";
  };

  # Market Intelligence — construction-sector earnings research. Static dashboard
  # on :25445 + daily/weekly timers. Reuses the hermes DeepSeek key; FRED/FMP keys
  # are agenix secrets (market-intelligence-{fred,fmp}-key). App code lives in
  # /var/lib/hwc/market-intelligence (managed outside nix, like hermes-agent/scripts).
  hwc.server.ai.marketIntelligence = {
    enable = true;
  };

  # CouchDB for Obsidian LiveSync comes from the server role.

  # Frigate NVR (Config-First Pattern with GPU Acceleration)
  # Access: https://hwc-server.ocelot-wahoo.ts.net:5443 (via Caddy)
  # Charter v7.0 Section 19 compliant - TensorRT CUDA support
  hwc.media.frigate = {
    enable = true;

    # Internal port 5001 (exposed as 5443 via Caddy)
    port = 5001;

    # GPU acceleration for ONNX object detection (TensorRT + CUDA)
    gpu = {
      enable = true;
      device = 0; # NVIDIA P1000
    };

    # Storage paths
    storage = {
      configPath = "/opt/surveillance/frigate/config";
      mediaPath = "/mnt/media/surveillance/frigate/media";
      bufferPath = "/mnt/hot/surveillance/frigate/buffer";
    };

    # Firewall settings
    firewall.tailscaleOnly = true;

    exporter.enable = true;   # frigate-prometheus-exporter → Grafana "Cameras" dashboard

    # Automated surveillance cleanup (backup enforcement for Frigate retention)
    cleanup.enable = true;
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
    X11Forwarding = lib.mkForce false; # Headless server doesn't need X11 forwarding
  };

  # Session/sudo/permitCertUid come from the server role. This machine only
  # enables lingering so rootless podman containers run when not logged in.
  hwc.system.core.session = {
    linger.enable = true;
    linger.users = ["eric"];
  };
  # X11 services disabled for headless server
  # services.xserver.enable = true;

  #============================================================================
  # STORAGE PATHS
  #============================================================================
  hwc.paths = {
    hot.root = "/mnt/hot"; # SSD hot storage
    media.root = "/mnt/media"; # HDD media storage
  };

  # Container runtime (podman + autoPrune) comes from the server role.

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

  #============================================================================
  # CLOUDFLARE TUNNEL (public webhook ingress)
  #============================================================================
  # Exposes webhooks.heartwoodcraft.me → n8n for external services (Quo, etc.).
  # Parallel *.api.iheartwoodcraft.com hostnames are configured below for the
  # Phase 4.6 backend-ingress migration; they activate when DNS is provisioned.
  # Setup: cloudflared tunnel login → cloudflared tunnel create hwc-server
  #        then encrypt credentials JSON with agenix and set tunnelId below
  hwc.networking.cloudflared = {
    enable = true; # Enable after: tunnel created + credentials encrypted + DNS CNAME set
    tunnelId = "1536327b-2641-4706-8ad9-48c94d0b11f9";
    credentialsFile = config.age.secrets.cloudflared-tunnel-credentials.path;
    # n8n.heartwoodcraft.me handled by `domain` option default → localhost:n8nPort.
    #
    # Phase 4.6 outcome (2026-07-07): the planned *.api.iheartwoodcraft.com
    # subzone is impossible on the free plan (Cloudflare subdomain zones are
    # Enterprise-only) and proxied two-level names aren't covered by
    # Universal SSL. Production-domain ingress instead rides the ONE-level
    # hostname api.iheartwoodcraft.com (proxied CNAME → tunnel, created
    # 2026-07-07) with PATH routing: only /webhook/* reaches n8n; all other
    # paths fall through to the tunnel's 404 default, so the n8n UI is not
    # publicly exposed. mcp/leads/brain can join later as path routes.
    # See wiki/nixos/iheartwoodcraft-com-backend-migration.md.
    extraIngress = {
      "mcp.heartwoodcraft.me" = "http://localhost:6200";
      "leads.heartwoodcraft.me" = "http://localhost:8420";
      "brain.heartwoodcraft.me" = "http://localhost:9876";

      # datax-monitor dashboard — shared with external DataX collaborators
      # off-tailnet. Public DNS CNAME + Cloudflare Access policy ("datax",
      # email allow-list) gate it; the tunnel only proxies; the app has no
      # auth of its own. Local target is hwc.business.dataxMonitor on :4400.
      "monitor.heartwoodcraft.me" = "http://localhost:4400";

      # Production-domain webhook ingress (calculator lead/appointment).
      "api.iheartwoodcraft.com" = { service = "http://localhost:5678"; path = "^/webhook/"; };

      # Umami analytics — script.js + /api/send must be visitor-reachable.
      "stats.iheartwoodcraft.com" = "http://localhost:3009";

      # hwc-crm public contact intake — the website's JobTread web-form embed
      # mirrors submissions here so they land on the funnel board. PATH-locked
      # to /hooks/contact ONLY; the rest of hwc-crm (board UI, transitions)
      # stays tailnet-private (unmatched paths fall through to the 404 default).
      "crm.iheartwoodcraft.com" = { service = "http://localhost:11660"; path = "^/hooks/(contact|appointment|availability)"; };

      # hwc-leads report viewer API — public so customers can open the report
      # link emailed to them off-tailnet. PATH-locked to the read-only, already
      # sanitised GET /api/reports/<id> (no email/phone/full name/attribution);
      # the leads capture POST + admin stay tailnet-private. Needs DNS CNAME
      # reports → tunnel. hwc-leads listens on :11650.
      "reports.iheartwoodcraft.com" = { service = "http://localhost:11650"; path = "^/api/reports/"; };

      # hwc-mcp-gateway origins — internal hostnames the OAuth gateway Worker
      # proxies to (machine-to-machine via an Access service token). Distinct
      # from the bare brain./leads./mcp. names above, which stay owned by the
      # live MCP Portal during the parallel cutover. See ~/600_apps/hwc-mcp-gateway/ORIGINS.md.
      "brain-origin.heartwoodcraft.me" = "http://localhost:9876";
      "leads-origin.heartwoodcraft.me" = "http://localhost:8420";
      "hwc-origin.heartwoodcraft.me" = "http://localhost:6200";
    };
  };

  # n8n webhook URL still points at the .me hostname because that's where
  # callers expect to reach it. Flip to n8n.api.iheartwoodcraft.com after
  # DNS is provisioned and any external integrations (Quo, Slack, etc.)
  # are updated.
  hwc.automation.n8n.webhookUrl = "https://n8n.heartwoodcraft.me";

  #============================================================================
  # REVERSE PROXY
  #============================================================================
  hwc.networking.reverseProxy = {
    enable = lib.mkDefault true;
    # domain defaults to this host's own tailnet FQDN (networking.hostName +
    # hwc.networking.hosts.tailnetSuffix) — no override needed.
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
    healthCheck = {
      enable = lib.mkDefault true;
      checkInterval = 300; # every 5 minutes
      failuresBeforeRestart = 3; # auto-restart after 15 min down
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
  hwc.media.scripts.sweep.enable = lib.mkDefault true;

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
  hwc.media.organizr.enable = false;
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
    # apiKey + users policy removed 2026-06-11: the only consumer
    # (jellyfin-apply-policies) enforced MaxActiveSessions=0, which is the
    # Jellyfin default. Key was plaintext in git history — rotate it in the
    # Jellyfin UI. If policy management is wanted later, convert the module
    # option to an agenix apiKeyFile first.
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
      usernameFile = config.hwc.secrets.api."webdav-username" or null;
      passwordFile = config.hwc.secrets.api."webdav-password" or null;
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

  # Vaultwarden password manager — https://hwc-server.ocelot-wahoo.ts.net:15443
  hwc.secrets.vaultwarden.enable = lib.mkDefault true;

  # Authentik SSO/Identity Provider — https://hwc-server.ocelot-wahoo.ts.net:15543
  hwc.system.core.authentik.enable = lib.mkDefault true;

  # Business subdomains (firefly, databases, datax, paperless, morning
  # briefing, webapps, estimator, leads, website) come from the business role.

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
    observability.metrics.enable = false;
    network.mode = "host";
  };

  # YouTube services (legacy transcript API removed 2026-07-05 — superseded by
  # yt-transcripts-api v2; its scriptDir had pointed at a nonexistent path)
  hwc.media.youtube.transcripts = {
    enable = lib.mkDefault true;
    port = 8100;
    outputDirectory = "/mnt/media/transcripts";
  };

  # PostgreSQL (always enabled — used by many services)
  # Version pinned to 15 in domains/data/databases/index.nix (data format lock)
  hwc.data.databases.postgresql = {
    enable = lib.mkDefault true;
    version = "15";
    package = pkgs.postgresql_15; # Cluster on-disk format is v15 — do not bump without pg_upgrade

    # Server-only: Immich vector search + Podman media-network integration
    containerNetwork.enable = true;
    extensions = ps: [ps.pgvector ps.vectorchord];
    sharedPreloadLibraries = ["vchord"];

    backup.perDatabase = {
      enable = true;
      # Per-database list managed by consumer modules (e.g. hwc.business.databases)
      # outputDir = "/home/eric/backups/postgres";  # default
      # retentionDays = 30;  # default
      # schedule = "*-*-* 02:30:00";  # default (2:30 AM)
    };
  };

  # Redis (used by Paperless-NGX for async task queue)
  hwc.data.databases.redis.enable = lib.mkDefault true;

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

  # Home Manager (CLI only, no GUI) — ./home.nix is wired by the flake glue
  # for both nixos-rebuild and standalone hms.

  system.stateVersion = "24.05";
}
