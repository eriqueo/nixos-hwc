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

    # Roles (base, server) are supplied by the
    # flake.nix machines table — membership lives there, not here.

    ../../domains/ai/index.nix
    ../../domains/networking/index.nix
    ../../domains/data/index.nix
    ../../domains/media/index.nix
    ../../domains/notifications/index.nix # Notification delivery (webhooks, CLI)
    ../../domains/gaming/index.nix # Retroarch emulation + WebDAV save sync
    ../../domains/business/index.nix # Phone receipt forwarding; apps stay disabled
    ../../domains/server/native/ai/brain-mcp/index.nix # Brain MCP Server (Deno)
    ../../domains/server/native/ai/brainvec/index.nix # brainvec semantic-index ingest (vault embeddings)
    ../../domains/server/native/ai/dx2/index.nix # DX2 endpoint facts (URL, model, key) for research-scout + inbox-processor
    ../../domains/server/native/ai/llama-cpp/index.nix # llama.cpp inference (embed only on this host)
    ../../domains/server/native/ai/whisper/index.nix # whisper.cpp speech-to-text server (GPU)
    ../../domains/server/services/inbox-processor/index.nix # Phone capture processor (Whisper + Tesseract)
    ../../domains/server/services/bloxels-cv/index.nix # Bloxels grid photo classifier (path watcher)
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
      # Compare with the flake's stable source so a future release update does
      # not leave this assertion pinned to the previous release.
      assertion = (pkgs.lib.trivial.release or "") == inputs.nixpkgs-stable.lib.trivial.release;
      message = ''
        ============================================================
        SERVER NIXPKGS PROVENANCE VIOLATION
        ============================================================
        hwc-server MUST use nixpkgs-stable, not nixpkgs-unstable!

        Current nixpkgs: ${toString pkgs.path}
        Current release: ${pkgs.lib.trivial.release or "unknown"}
        Expected: nixpkgs-stable (${inputs.nixpkgs-stable.lib.trivial.release} branch)

        Fix in flake.nix:
          machines.server.nixosPkgs = pkgs-stable-cuda;
        ============================================================
      '';
    }
    {
      # CHARTER v9.0: PostgreSQL MUST be pinned to version 15
      # Data directory is PostgreSQL 15 format - upgrading breaks compatibility
      assertion =
        !config.services.postgresql.enable
        || (lib.hasPrefix "15." config.services.postgresql.package.version);
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

  # Migrated application state remains for recovery until archive restore
  # checks pass. Application ownership is explicit on hwc-work; the server
  # role now supplies infrastructure only.

  # `deploy` — interactive one-step deploy CLI; auto-discovers ~/600_apps/*/deploy.sh
  hwc.server.deploy.enable = true;

  # Brain MCP Server + brainvec — moved to hwc-work (service split wave 1,
  # 2026-09-25). The tunnel names below now target hwc-work's tailnet address.
  hwc.server.ai.brainMcp.enable = false;
  hwc.server.ai.brainvec.enable = false;

  # Phone Capture Processor (Phase 10: Whisper STT + Tesseract OCR)
  # Watches inbox-mobile/{audio,screenshots} and writes markdown to the vault's
  # global capture inbox, `_inbox/`. It wrote to `inbox/` until 2026-09-19: the
  # vault's reorganisation renamed the inbox and this path was never moved, so
  # captures landed in a directory nothing reads.
  hwc.server.services.inboxProcessor = {
    enable = true;
    audioInboxPath = "${config.hwc.paths.brain."inbox-mobile"}/audio";
    screenshotsInboxPath = "${config.hwc.paths.brain."inbox-mobile"}/screenshots";
    brainInboxPath = "${config.hwc.paths.brain."server-replica"}/_inbox";
    processedPath = "${config.hwc.paths.brain."inbox-mobile"}/processed";
    # DX2 adds a title, summary and action items above the verbatim
    # transcript; fail-open to the raw note when DX2 is unreachable.
    cleanup.enable = true;
  };

  # Bloxels CV — classify phone photos of the printed 13x13 Bloxels grid.
  # Watches inbox-mobile/bloxels; writes results/<photo>/{grid.json,debug.png}
  # back into the share so Syncthing returns them to the phone.
  hwc.server.services.bloxelsCv = {
    enable = true;
    package = inputs.bloxels-cv.packages.${pkgs.system}.default;
    watchPath = "${config.hwc.paths.brain."inbox-mobile"}/bloxels";
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
    # Registration is declarative: the secret holds a Tailscale OAuth *client
    # secret* (tskey-client-…) with the single scope `auth_keys: write` bound to
    # tag:server. The node mints its own registration key and comes up tagged,
    # and tagged devices have node-key expiry disabled — the fix for the
    # 2026-08-07 outage, where the untagged node hit the tailnet's 6-month key
    # expiry and dropped off (ssh failed "Network is unreachable"; recovered
    # over LAN). Unlike an auth key, which caps at 90 days, a client secret has
    # no expiry, so re-registration stays unattended indefinitely. This is why
    # it replaced the tagged auth key that briefly lived here.
    #
    # This only ever fires when the backend is NeedsLogin / NeedsMachineAuth /
    # Stopped — a logout, a reinstall, a rebuilt box. A healthy node never
    # touches it.
    tailscale.authKeyFile = config.age.secrets."tailscale-authkey".path;
    # NOT cosmetic. Per tailscale.com/kb/1215, on the OAuth path `ephemeral`
    # defaults to TRUE and `preauthorized` to FALSE — so omitting these would
    # register hwc-server as an ephemeral node (deleted by Tailscale whenever it
    # goes offline) that is also awaiting manual approval. Both must be stated.
    tailscale.authKeyParameters = {
      preauthorized = true; # usable immediately, no manual device approval
      ephemeral = false; # persists across reboots and offline periods
    };
    # --reset makes this config authoritative rather than merging into whatever
    # prefs the last interactive `tailscale up` happened to leave behind.
    # --advertise-tags is REQUIRED on the OAuth path, not belt-and-braces: the
    # client's auth_keys scope is bound to a tag set, and kb/1215 states you
    # must pass one of those tags to --advertise-tags. Dropping it breaks
    # registration outright.
    tailscale.extraUpFlags = [
      "--reset"
      "--advertise-tags=tag:server"
      "--accept-routes"
      "--hostname=hwc-server"
    ];
    # firewall.level = "server" comes from the server role
    # Audited 2026-09-25 (service split wave 3): dropped ports with no
    # listener (5030 slskd web, 8888 receipt API, 8501 Streamlit, 5909 Calibre
    # VNC) and the monitoring ports that moved to hwc-work (3000/9090/9093).
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
      # Business services
      5432 # PostgreSQL (internal)
      6379 # Redis (internal)
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

  # Syncthing — bidirectional home folder sync with hwc-laptop and, since the
  # service split, hwc-work (inbox/hwc/tech/datax only; this host stays the hub).
  hwc.data.syncthing = {
    enable = true;
    devices."hwc-laptop".id = "H3EVGHN-DTDTMWS-INSC2RH-PBRABJX-M3FW7AM-3P2NY3M-X5XLYCK-JD2YRQG";
    devices."hwc-phone".id = "ROLZBPO-HN33OQP-E4DV5PD-34ZVSIP-I5USNNW-NHHOPKC-APNQNSH-BX7OMQN";
    devices."hwc-work" = {
      id = "D235HNY-GMD6CNM-MEDAB6A-IAGCUZL-YHZMCDI-FNMUNDZ-SIJK6UU-FQ6BGQS";
      addresses = [ "tcp://${config.hwc.networking.hosts.ips.work}:22000" ];
    };
    folders = {
      "000_inbox" = {
        path = "/home/eric/000_inbox";
        devices = ["hwc-laptop" "hwc-work"];
      };
      "100_hwc" = {
        path = "/home/eric/100_hwc";
        devices = ["hwc-laptop" "hwc-work"];
      };
      "200_personal" = {
        path = "/home/eric/200_personal";
        devices = ["hwc-laptop"];
      };
      "300_tech" = {
        path = "/home/eric/300_tech";
        devices = ["hwc-laptop" "hwc-work"];
      };
      "700_datax" = {
        path = "/home/eric/700_datax";
        devices = ["hwc-laptop" "hwc-work"];
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

  # Mosquitto is Frigate's event bus and lives with the cameras. The bridge
  # forwards `end` events to n8n on whichever host owns it (service split
  # wave 4: hwc-work) — plain HTTP inside the tailnet, no cert dependency.
  hwc.automation.mqtt = {
    enable = true;
    webhookBridge = {
      enable = true;
      topic = "frigate/events";
      eventTypes = [ "end" ]; # Intermediate updates cannot notify; avoid n8n executions.
      webhookUrl = config.hwc.networking.hosts.url {
        server = config.hwc.networking.shared.routeOwners.n8n.owner;
        scheme = "http";
        port = config.hwc.automation.n8n.port;
        path = "/webhook/frigate-events";
      };
    };
  };


  # SR Gauntlet — moved to hwc-work with its checkout and credential dirs
  # (service split wave 1, 2026-09-25). Kept off here so one host investigates.
  hwc.automation.srGauntlet.enable = false;

  # DX1 Gauntlet — case-ledger investigations, sr-gauntlet's sibling.
  # Enabled 2026-08-17 after the flip conditions were met and verified:
  #   1. ~/700_datax/dx1_gauntlet on this host (Syncthing; node_modules is
  #      sync-ignored and was npm-ci'd here by hand — redo after a
  #      package.json change),
  #   2. /var/lib/sr-gauntlet/{datax,jt-mcp,datax.env} present (shared with
  #      sr-gauntlet),
  #   3. run.sh allowlists CLAUDE_CONFIG_DIR/CLAUDE_CODE_OAUTH_TOKEN through
  #      its env -i scrub (the unit-supplied agenix token would otherwise be
  #      stripped and headless auth would fail).
  # Moved to hwc-work with sr-gauntlet (service split wave 1, 2026-09-25).
  hwc.automation.dx1Gauntlet.enable = false;

  # Brain vault git sync — Tier-2 transport. Every 15 min: commit local vault
  # changes, pull the hub (laptop's commits), push server changes up. Replaces
  # Syncthing as the laptop<->server vault path. Serialized with brain-mcp via
  # an flock on <vault>/.git/.sync.lock.
  hwc.automation.vaultSync.enable = true;

  # Brain janitor — nightly mechanical sweep of the vault (brain sweep --report,
  # CLI at ~/600_apps/brain). Detector, not fixer: writes a dated drift report to
  # _inbox/janitor/ under the shared .git/.sync.lock flock; pings hwc-notify only
  # on alert-level drift or failure. vault-sync carries the report to the hub.
  # Runs on hwc-work with the rest of the brain stack (service split wave 1).
  hwc.automation.brainSweep.enable = false;

  # The phone's receipts folder is Syncthing ingest on this host; its watcher
  # forwards drops into Paperless's consume dir on hwc-work.
  hwc.business.paperless.receipts.enable = true;

  # Inbox janitor — every 30 min, drain loose files at the root of
  # ~/000_inbox/downloads per ~/000_inbox/_inbox-routing.yaml (datax stays,
  # business/tech/personal drain to the home PARA dirs, secrets/junk quarantine,
  # unmatched → _review). Server-only by design: ~/000_inbox is a multi-writer
  # Syncthing tree, so a single host owns the routing pass (same rationale as
  # vaultSync's single-writer hub). Ships dryRun=true — watch the journal, then
  # set hwc.automation.inboxJanitor.dryRun = false.
  hwc.automation.inboxJanitor.enable = true;
  hwc.automation.inboxJanitor.dryRun = false;

  # Unified lead pipeline comes from the business role.

  # Off-host dead-man's switch: healthchecks.io check "hwc-server" (5 min
  # period, 10 min grace). It alerts when these pings stop.
  hwc.monitoring.heartbeat = {
    enable = true;
    pingUrlFile = config.age.secrets.heartbeat-ping-url.path;
  };

  # Alert sources — what to monitor (thresholds, triggers)

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
      config.hwc.business.paperless.storage.mediaDir # Paperless originals/archive (CRITICAL)
      "/var/lib/hwc" # Service state directories
      "/var/lib/backups" # Database dumps
      # T3 Code state (CRITICAL). Holds the event-sourced SQLite store — every
      # project, thread and turn — plus the server signing key and the pairing
      # credentials. Losing the key invalidates every paired client, and the
      # store is not regenerable from anything. Only userdata/ is listed:
      # ~/.t3/caches and ~/.t3/worktrees are REPLACEABLE.
      #
      # The store is copied live, so a WAL-torn snapshot is possible; the
      # -shm/-wal siblings travel with it, which is what makes recovery likely
      # rather than certain. Stop t3-serve.service before a restore-critical run.
      "/home/eric/.t3/userdata"
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

      # Dumping *arr SQLite databases...
      #
      # Retention class: CRITICAL. These hold every library mapping, quality
      # profile, indexer, history and blocklist for the media stack, and until
      # 2026-08-16 they were in ZERO borg archives — /opt is not a source, and
      # each app's own Backups/ zips sit on the same NVMe as the DB they would
      # restore. That gap is the gate on the arr upgrade window: Radarr 6.3.0 /
      # Sonarr 4.0.19 migrations are forward-only, and "restore the DB and
      # revert the tag" is their only rollback.
      #
      # Dumped via `.backup` rather than adding /opt to sources: the DBs are
      # WAL-mode, so a file-level copy can capture a torn page whose WAL is
      # missing, and borg runs with failOnWarnings=false — a "file changed
      # while reading" warning records the job as SUCCESS. `.backup` takes a
      # read lock and emits a checkpointed, self-consistent single file.
      # /var/lib/backups IS a borg source, so the dumps ride the existing job.
      SQLITE=/run/current-system/sw/bin/sqlite3
      for app in radarr sonarr lidarr prowlarr readarr; do
        SRC="/opt/$app/config/$app.db"
        [ -f "$SRC" ] || continue
        # logs.db and cache.db are deliberately skipped — regenerable, and the
        # log DB churns every scrape, which poisons borg dedup for no recovery value.
        if $SQLITE "$SRC" ".backup '$DUMP_DIR/$app-$DATE.db'" 2>/dev/null; then
          # Trust the dump only if it reads back as a valid database.
          if [ "$($SQLITE "$DUMP_DIR/$app-$DATE.db" 'PRAGMA integrity_check;' 2>/dev/null)" != "ok" ]; then
            echo "$app dump failed integrity_check - removing"
            rm -f "$DUMP_DIR/$app-$DATE.db"
          fi
        else
          echo "$app dump failed"
        fi
      done

      # Cleanup old dumps (keep 14 days - Borg handles long-term retention)
      # *.sql matches legacy uncompressed dumps until they age out
      find "$DUMP_DIR" -name "*.sql" -mtime +14 -delete 2>/dev/null || true
      find "$DUMP_DIR" -name "*.sql.gz" -mtime +14 -delete 2>/dev/null || true
      find "$DUMP_DIR" -name "*.json" -mtime +14 -delete 2>/dev/null || true
      find "$DUMP_DIR" -name "*.db" -mtime +14 -delete 2>/dev/null || true
      echo "Database dumps complete"
    '';

    monitoring.enable = true;
    notifications.onFailure = true;
  };

  # hwc-work backs up to this host's DAS. The NixOS repos module creates the
  # `borg` user and pins its key to `borg serve --restrict-to-repository`, so
  # the work host can only touch its own repository. The private half is the
  # agenix secret `borg-work-ssh-key` mounted on hwc-work; the client job is
  # `hwc.data.borg.repo.remote` in machines/work/config.nix. Traversal bit on
  # /mnt/backup lets the borg user reach its subdirectory without exposing the
  # server's own repository, which stays root-only.
  # Retention class: AUTO-MANAGED — bounded by the client's prune policy
  # (7 daily / 4 weekly / 6 monthly) and compacted by the same job.
  services.borgbackup.repos.hwc-work = {
    path = "/mnt/backup/borg-hwc-work";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEnjV1K+7pHtjsFJKKm07ty4fTayNLQ+lOPoUhTkEP50 root@hwc-work borg-to-server"
    ];
  };
  systemd.tmpfiles.rules = [ "z /mnt/backup 0751 root root -" ];

  # hwc-work's eric key. It clones and syncs the brain vault and claude-config
  # hubs on this host and pulls the app checkouts the service split moved
  # there (vault-sync, t3-update, nightly-builds all use SSH remotes). mkAfter
  # keeps the fleet keys from hwc.system.users; same shape as the laptop.
  users.users.eric.openssh.authorizedKeys.keys = lib.mkAfter [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIcfkt1xgKBQbL9kuc1x2h/F3HjK+pDU5j/I9Q74e8xE eric@hwc-work"
  ];

  # Machine-specific GPU settings for Quadro P1000 (legacy driver required)
  hwc.system.hardware.gpu = {
    enable = lib.mkForce true;
    type = "nvidia";
    nvidia = {
      driver = "legacy_580"; # Last branch supporting Quadro P1000 (Pascal)
      containerRuntime = true;
      enableMonitoring = true;
    };
  };

  # P1000 (Pascal) requires the proprietary driver. The GPU domain selects
  # hardware.nvidia.package from the stable driver value above.
  hardware.nvidia = {
    open = lib.mkForce false; # Pascal doesn't support open-source modules
    modesetting.enable = true;
    powerManagement.enable = true;
  };

  # CUDA config (cudaSupport + binary cache) set in flake.nix
  # GPU acceleration for Immich handled by hwc.media.immich.gpu.enable

  # GPU acceleration for Immich handled by hwc.media.immich.gpu.enable in server profile

  # MCP (Model Context Protocol) server infrastructure
  # Parent MCP disabled (mcp-proxy not in nixpkgs-stable), but heartwood is self-contained
  hwc.ai.mcp.enable = lib.mkForce false;
  # The hwc-sys gateway (+ JT tools) runs on hwc-work since service split
  # wave 2; hwc.system.mcp.serverAlias points every host's URL there.

  # Server-only additions to the generated ~/.nixos/.mcp.json (agent-harness):
  # the services these reach exist only here.
  hwc.system.apps.agent-harness.projectMcp.extraServers = {
    filesystem = {
      command = "npx";
      args = [
        "-y"
        "@modelcontextprotocol/server-filesystem"
        config.hwc.paths.nixos
        "/etc/nixos"
        "${config.hwc.paths.user.home}/.config"
      ];
    };
    postgres = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-postgres" "postgresql://localhost:5432/postgres" ];
    };
    puppeteer = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-puppeteer" ];
    };
  };

  # Note: Backup is configured above (hwc.data.backup block at line ~304)
  # NixOS config excluded - it's in git. Databases handled by preBackupScript.

  # Navidrome music streaming (container)
  hwc.media.navidrome.enable = true;

  # NanoClaw AI agent orchestrator
  # Connects to Slack via Socket Mode, spawns agents in containers
  # NanoClaw — disabled 2026-05-29; its successor Hermes was retired 2026-09-25.
  # Module moved to domains/ai/.nanoclaw-disabled/; secret declarations remain
  # (nanoclaw-anthropic-key.age is reused by Hermes via re-named logical secret).
  # hwc.ai.nanoclaw = { enable = false; slack.enable = false; };

  # Embeddings run on work with brainvec, brain MCP and the mail classifier.

  # whisper.cpp speech-to-text — resident whisper-server on 127.0.0.1:11503,
  # OpenAI-compatible /v1/audio/transcriptions, vhost `whisper` on the tailnet.
  # Same sm_61 rebuild as llama-cpp: the cached binary has no Pascal kernels
  # and every model above base.en died with "IM2COL failed" (2026-09-05).
  # Shares the 4 GB P1000 with llama-embed and Frigate.
  hwc.server.ai.whisper = {
    enable = true;
    cudaCapabilities = ["6.1"];
  };

  # Phone LiveSync is storage owned by this machine, not every serving host.
  hwc.data.couchdb = {
    enable = true;
    settings = { port = 5984; bindAddress = "127.0.0.1"; };
    monitoring.enableHealthCheck = true;
    reverseProxy = { enable = true; path = "/sync"; };
  };

  # Frigate NVR (Config-First Pattern with GPU Acceleration)
  # Access: https://hwc-server.ocelot-wahoo.ts.net:5443 (via Caddy)
  # Charter v7.0 Section 19 compliant - TensorRT CUDA support
  hwc.media.frigate = {
    enable = true;

    # Host-networked HTTP listener, proxied by the Frigate Caddy vhost.
    port = 5000;

    # GPU acceleration for ONNX object detection (TensorRT + CUDA)
    gpu = {
      enable = true;
      device = 0; # NVIDIA P1000
    };

    # Storage paths
    storage = {
      configPath = "/opt/surveillance/frigate/config";
      mediaPath = "/mnt/media/surveillance/frigate/media";
    };

    # Firewall settings
    firewall.tailscaleOnly = true;

    # Native metrics → Prometheus; native retention owns footage deletion.
    # This timer only prunes empty directories.
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

  # Session/sudo/lingering/permitCertUid come from the server role.
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

  # SMART disk monitoring comes from the server role.

  # *arr metrics (Sonarr/Radarr/Lidarr/Prowlarr) — the apps run here; the
  # central Prometheus on hwc-work scrapes them over the tailnet.
  hwc.monitoring.exportarr.enable = true;

  # Enhanced logging for server.
  # SystemMaxUse and MaxRetentionSec are both ceilings and journald evicts on
  # whichever binds first — at 1G the size cap won every time, leaving ~2 days
  # of history and making the 1month retention target unreachable. That gap
  # cost us the forensic window when files vanished from hot storage. 8G is
  # ~1.7% of the 468G root and lets the retention target actually govern.
  services.journald.extraConfig = ''
    SystemMaxUse=8G
    RuntimeMaxUse=200M
    SystemMaxFileSize=100M
    MaxRetentionSec=1month
  '';

  #============================================================================
  # CLOUDFLARE TUNNEL — runs on hwc-work since service split wave 2
  #============================================================================
  # The tunnel process and its full ingress table live in
  # machines/work/config.nix; it reaches the apps still on this host over the
  # tailnet (n8n, gateway, datax-monitor directly; crm, lead-scout, umami via
  # their Caddy vhosts here). Phase 4.6 history (api.iheartwoodcraft.com path
  # routing, .me retirement twins, hwc-mcp-gateway origins) moved with it.

  # Mail and its consumers run on work; phone receipts use SSH forwarding.

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
  hwc.networking.gluetun.instances.gluetun = {
    enable = lib.mkDefault true;
    privateKeySecret = "vpn-wireguard-private-key";

    # US-VA#1 (Ashburn), port-forward capable. Handshake verified 2026-08-19,
    # replacing US-CO#243 / 95.173.221.158 after it stopped answering handshakes
    # on 2026-08-18 19:20 and took the download stack down for ~33h.
    wireguard = {
      serverLabel = "US-VA#1 (Ashburn)";
      publicKey = "zAIZj//t14xuriUMSlWk4/J2jox6I/JMzHL1Y3D/WUE=";
      endpointIp = "185.156.46.33";
      addresses = "10.2.0.2/32";
    };

    controlPort = 8000;

    # Published on behalf of the containers living in this netns; they cannot
    # publish their own.
    ports = [
      "127.0.0.1:8080:8080" # qBittorrent UI (Caddy proxies to localhost)
      "127.0.0.1:8081:8085" # SABnzbd (container uses 8085 internally)
      "127.0.0.1:5010:5010" # Mousehole (MAM IP updater)
    ];

    portForwarding = {
      enable = lib.mkDefault true;
      syncTo = "qbittorrent";
      checkInterval = 60;
    };
    healthCheck = {
      enable = lib.mkDefault true;
      checkInterval = 300; # every 5 minutes
      failuresBeforeRestart = 3; # first auto-restart after 15 min down
    };
  };

  # Second tunnel, for slskd only. Proton forwards exactly one port per
  # WireGuard SESSION, so slskd cannot share the tunnel above and still hold an
  # inbound Soulseek port. Both facts were measured live on 2026-08-20: a second
  # session does get its own port, and two sessions sharing ONE key make the
  # NAT-PMP leases fight until neither port is stable. Hence its own key.
  hwc.networking.gluetun.instances.gluetun-slskd = {
    enable = lib.mkDefault true;
    privateKeySecret = "vpn-wireguard-private-key-slskd";

    wireguard = {
      serverLabel = "US-UT#52";
      publicKey = "fDSDNxB7yfHbaemo7cAFMWBsEm31bVAAradL4hbBEG0=";
      endpointIp = "74.63.204.210";
      # IPv4 only, though the Proton config also lists 2a07:b944::2:2/128. The
      # media podman network carries no IPv6, and the working tunnel above drops
      # the v6 address the same way. 10.2.0.2/32 duplicating the other tunnel's
      # address is expected — Proton assigns it per config, and the two live in
      # separate network namespaces, so they never meet.
      addresses = "10.2.0.2/32";
    };

    controlPort = 8001; # 8000 belongs to the qBittorrent tunnel

    # slskd cannot publish its own ports from inside this netns.
    # Host side is 5031, not 5030: domains/networking/routes.nix already sends the
    # slskd vhost to http://127.0.0.1:5031. Publishing on 5030 leaves that upstream
    # with nothing listening, which is exactly what happened on 2026-08-25.
    ports = [
      "127.0.0.1:5031:5030" # slskd web UI -> Caddy vhost upstream
    ];

    portForwarding = {
      enable = lib.mkDefault true;
      syncTo = "slskd";
      checkInterval = 60;
    };
    healthCheck = {
      enable = lib.mkDefault true;
      checkInterval = 300;
      failuresBeforeRestart = 3;
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
  # slskd was held OFF from 2026-08-20 to 2026-08-24 because it egressed on the
  # real IP: network.mode used to default to "media", so it held its own
  # SandboxKey and moved ~29.4 GB out / 15.5 GB in over six weeks while every
  # sibling downloader was tunnelled. The hold's REMOVE WHEN condition is now
  # met — gluetun-slskd exists above with its own Proton key. The leak itself
  # can no longer recur by configuration: network.mode defaults to "vpn" and
  # clearnet is a build failure (domains/media/slskd/index.nix).
  #
  # STILL UNVERIFIED, carried forward from that investigation: that two DISTINCT
  # keys hold two STABLE forwarded ports. Per-session allocation was proven live,
  # and the port churn was tied to two sessions sharing ONE key — so distinct
  # keys are the well-supported case, but they have never been measured. Watch
  # the first day of gluetun-slskd-port-sync logs for the 42384 → 43212 → 56838
  # walk before trusting it. Churn is survivable; it just means inbound keeps
  # moving, which is most of what the port was for.
  #
  # soularr follows slskd: it asserts slskd is enabled, and with slskd down it
  # has nothing to hand a grab to.
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
    network = {
      # Android TV clients are on this LAN. Without this declaration Jellyfin
      # classified them as remote and forced an unnecessary 8 Mbit transcode.
      localSubnets = ["192.168.0.0/24"];
      # Caddy reaches Jellyfin through the loopback upstream below.
      knownProxies = ["127.0.0.1"];
    };
    # Policy management revived 2026-07-16 via the agenix apiKeyFile the
    # 2026-06-11 removal note asked for (plaintext apiKey option is gone).
    apiKeyFile = config.age.secrets.jellyfin-api-key.path;
    users = {
      # Jellyfin forbids passwordless admins, so admin lives in a dedicated
      # hidden account and the two profiles are regular tap-to-sign-in users.
      admin = {
        ensure = true;
        passwordFile = config.age.secrets.jellyfin-admin-password.path;
        admin = true;
        hidden = true;
      };
      eric = {
        admin = false;
        passwordless = true;
        hidden = false;
      };
      Kids = {
        admin = false;
        passwordless = true;
        hidden = false;
      };
    };
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

  # Vaultwarden runs on hwc-work since service split wave 3.

  # Authentik retired: zero configured SSO providers. Its database and files
  # remain for recovery. Immich owns Redis :6380 and must keep running.

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
    extensions = ps: [
      ps.pgvector
      ps.vectorchord
    ];
    sharedPreloadLibraries = ["vchord"];

    # RETIRED 2026-08-26. Law 15: exactly one mechanism per backup concern.
    #
    # This job dumped three of the fourteen databases (lead_scout,
    # datax_monitor, hwc) into /home/eric/backups/postgres — a path that is in
    # NO borg source. Borg carries /mnt/media/photos, /var/lib/hwc and
    # /var/lib/backups, so 445 MB across 94 files sat on the exact drive whose
    # loss it existed to survive. The 2026-06-09 server audit already flagged
    # the same directory at 31 MB and 61 files; nothing acted, and it grew.
    #
    # The surviving mechanism is strictly better on every axis: the borg job's
    # own pre-hook runs `pg_dumpall` into /var/lib/backups, which IS a borg
    # source. It covers EVERY database, not three, and the archive is
    # deduplicated and off-drive. Verified before retiring this one —
    # `CREATE DATABASE research_scout` and `home_scout` are both present in
    # /var/lib/backups/postgresql-2026-08-26.sql.gz, and that file is inside
    # archive hwc-server-hwc-backup-2026-08-26T02:19:57.
    #
    # What is lost: restoring ONE database now means extracting it from a
    # ~509 MB pg_dumpall rather than opening an 8 MB per-database file. That is
    # a real ergonomic cost, accepted deliberately. The alternative — pointing
    # outputDir at /var/lib/backups — would put two mechanisms on one concern
    # and write the same rows into borg twice.
    #
    # /home/eric/backups/postgres is left in place; the 445 MB already there is
    # Eric's to delete. Nothing reads it programmatically (searched: only docs
    # and this comment reference the path).
    backup.perDatabase.enable = false;
  };

  # Redis moved with Paperless (its only consumer) to hwc-work in wave 3.

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
