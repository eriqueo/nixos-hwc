# hwc-work — staged MS-02 work server. Production service ownership remains
# on hwc-server until a service is migrated with its state and callers.
{ pkgs, ... }: {
  imports = [
    ./hardware.nix
    # Notification routes need the networking domain's shared vocabulary,
    # even while this host's reverse proxy remains disabled.
    ../../domains/networking/index.nix
    # Service split wave 1 — the brain stack and the workbench hub. These are
    # machine-imported on hwc-server too (not role-supplied), so the same
    # explicit imports move here with the services.
    ../../domains/server/native/ai/brain-mcp/index.nix
    ../../domains/server/native/ai/brainvec/index.nix
    ../../domains/server/native/ai/llama-cpp/index.nix
    ../../domains/business/workbench/index.nix
  ];

  networking.hostName = "hwc-work";
  system.stateVersion = "25.11";

  # The server role supplies Podman, CLI tools and server path defaults.
  # CouchDB and the Proton bridge stay on hwc-server until their own waves.
  hwc.data.couchdb.enable = false;
  hwc.mail.protonmailBridgeCert.enable = false;

  #==========================================================================
  # Service split wave 1 (2026-09-25): development apps + brain stack.
  # Refinery, nightly builds and both gauntlets moved here with their state
  # (/var/lib/refinery, /var/lib/sr-gauntlet, ~/700_datax/*_gauntlet). The
  # brain stack (brain-mcp, brainvec, llama-embed on CPU, brain-sweep) runs
  # here against this host's clone of the vault hub. hwc-notify still lives
  # on hwc-server, so every notifier posts to its tailnet vhost.
  #==========================================================================
  hwc.automation.refinery = {
    enable = true;
    mode = "container";
    # Same verified release hwc-server ran (eriqueo/refinery 39846f5), loaded
    # from `podman save` on the server; no registry pull.
    image = "localhost/refinery:39846f5-docker";
    imagePull = "never";
  };
  hwc.automation.nightlyBuilds = {
    enable = true;
    notifyUrl = "https://hwc-notify.hwc.iheartwoodcraft.com:29443/notify";
  };
  hwc.automation.srGauntlet.enable = true;
  hwc.automation.dx1Gauntlet.enable = true;
  hwc.automation.vaultSync.enable = true;
  hwc.automation.brainSweep = {
    enable = true;
    notifyUrl = "https://hwc-notify.hwc.iheartwoodcraft.com:29443";
  };
  # readme-freshness stays on hwc-server: it asserts a local hwc-notify, which
  # moves with the notifications stack in a later wave.
  hwc.server.ai.brainMcp.enable = true;
  hwc.server.ai.brainvec.enable = true;
  # nomic-embed-text on CPU: the only inference this host runs. gpuLayers = 0
  # is what exempts it from the NVIDIA assertion; this host has an Intel iGPU.
  hwc.server.ai.llamaCpp = {
    enable = true;
    embed.enable = true;
    embed.gpuLayers = 0;
  };
  # Workbench hub served from here; hwc-server keeps the module on for its
  # own refinery areas.json but proxies the vhost to this host.
  hwc.business.workbench = {
    enable = true;
    routeOwner = "work";
    # Areas whose apps are still on hwc-server (wave 2/3). Remove each name
    # from this list in the commit that moves its app here.
    remoteRoutes = [ "crm" "firefly-explorer" "lead-scout" "home-scout" "research-scout" "event-scout" ];
  };

  # First work-owned route: the static calculator. Other app routes stay on
  # hwc-server until each app, its data, and its callers have migrated.
  hwc.networking.reverseProxy.enable = true;
  hwc.networking.reverseProxy.routeOwner = "work";

  # Storage tiers and scheduled business services remain disabled until the
  # drives and ownership for each service are established.
  hwc.system.networking.waitOnline.mode = "all";
  hwc.system.networking.waitOnline.timeoutSeconds = 30;

  # Data plane for the apps that will migrate here. PostgreSQL 15 matches the
  # server cluster so per-database dumps restore without a version step. No
  # container network binding yet: the 10.89.0.1 gateway only exists once a
  # container is attached, and the module's wait would otherwise stall boot
  # for two minutes on a host with zero containers. Enable it with the first
  # container that needs the database.
  hwc.data.databases.postgresql = {
    enable = true;
    version = "15";
    package = pkgs.postgresql_15;
    containerNetwork.enable = false;
  };

  # Backups push to the server's DAS over the tailnet rather than to a local
  # disk: this host has one SSD and no backup pool. The server declares the
  # matching restricted `services.borgbackup.repos.hwc-work`. Runs after the
  # server's own 02:00 job so the two do not contend for the pool.
  hwc.data.borg = {
    enable = true;
    repo.remote = {
      enable = true;
      path = "ssh://borg@100.77.195.118/mnt/backup/borg-hwc-work";
      sshKeySecret = "borg-work-ssh-key";
    };
    sources = [
      "/var/lib/hwc"      # Service state directories
      "/var/lib/backups"  # Database dumps from preBackupScript
      "/var/lib/refinery"    # Refinery board items, specs, reviews, spools
      "/var/lib/sr-gauntlet" # Gauntlet checkouts, datax.env, headless Claude config
      # T3 Code state (CRITICAL): event-sourced SQLite store + this host's own
      # signing key and pairing credentials. Copied live; see the same note on
      # hwc-server. caches/ and worktrees/ are replaceable and not listed.
      "/home/eric/.t3/userdata"
    ];
    excludePatterns = [
      ".cache"
      "*.tmp"
      "*.temp"
      "node_modules"
      "__pycache__"
      "*.log"
      # Live PostgreSQL data files — covered by the pg_dumpall in preBackupScript
      "/var/lib/hwc/postgresql"
    ];
    schedule = {
      frequency = "daily";
      timeOfDay = "03:00";
      randomDelay = "30m";
    };
    retention = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };
    preBackupScript = ''
      DUMP_DIR="/var/lib/backups"
      mkdir -p "$DUMP_DIR"
      DATE=$(date +%Y-%m-%d)

      echo "Dumping PostgreSQL databases..."
      if systemctl is-active --quiet postgresql; then
        # --rsyncable keeps borg dedup effective across daily compressed dumps
        /run/wrappers/bin/su - postgres -s /bin/sh -c "/run/current-system/sw/bin/pg_dumpall 2>/dev/null" | /run/current-system/sw/bin/gzip --rsyncable > "$DUMP_DIR/postgresql-$DATE.sql.gz" || echo "PostgreSQL dump failed"
      fi

      # Keep 14 days locally; borg holds the long-term retention.
      find "$DUMP_DIR" -name "*.sql.gz" -mtime +14 -delete 2>/dev/null || true
      echo "Database dumps complete"
    '';
    monitoring.enable = true;
    notifications.onFailure = true;
  };
}
