# hwc-work — staged MS-02 work server. Production service ownership remains
# on hwc-server until a service is migrated with its state and callers.
{ config, pkgs, ... }: {
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

  # Syncthing — the work folders, peered with hwc-server only (the server is
  # the hub; the laptop reaches these through it). 700_datax carries the
  # gauntlet trees the moved timers write into; 000_inbox carries the agent
  # handoffs. Personal and media folders stay off this host.
  hwc.data.syncthing = {
    enable = true;
    devices."hwc-server" = {
      id = "5UCUDT4-CUUGX7U-F2XVLET-SE3QGCA-JRYGXK3-45MQOBP-SYMQZM7-O653IAA";
      addresses = [ "tcp://${config.hwc.networking.hosts.ips.main}:22000" ];
    };
    folders = {
      "000_inbox" = { path = "/home/eric/000_inbox"; devices = [ "hwc-server" ]; };
      "100_hwc"   = { path = "/home/eric/100_hwc";   devices = [ "hwc-server" ]; };
      "300_tech"  = { path = "/home/eric/300_tech";  devices = [ "hwc-server" ]; };
      "700_datax" = { path = "/home/eric/700_datax"; devices = [ "hwc-server" ]; };
    };
  };

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
    # Same verified release hwc-server ran (eriqueo/refinery 39846f5), built
    # on this host with deploy/build-image.sh from that commit; no registry pull.
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

  #==========================================================================
  # CLOUDFLARE TUNNEL (public ingress) — service split wave 2, step 1
  #==========================================================================
  # The one tunnel moved here from hwc-server with the same credential; every
  # hostname, path lock and Access policy is unchanged. Apps still on
  # hwc-server are reached over the tailnet: directly where they bind on all
  # interfaces (n8n, the hwc-sys gateway, datax-monitor), otherwise through
  # the server's Caddy vhost by IP with the vhost's Host/SNI (crm, lead-scout,
  # umami bind 127.0.0.1). Caddy passes CF-Connecting-IP through, which is the
  # header hwc-crm rate-limits on.
  # TEMPORARY (each server target): flips to http://localhost:<port> in the
  # commit that moves that app to this host; removal condition = the app's
  # unit is disabled on hwc-server.
  hwc.networking.cloudflared =
    let
      server = config.hwc.networking.hosts.ips.main;
      viaServerCaddy = vhost: path: {
        service = "https://${server}";
        originRequest = {
          httpHostHeader = "${vhost}.hwc.iheartwoodcraft.com";
          originServerName = "${vhost}.hwc.iheartwoodcraft.com";
        };
      } // (if path == null then { } else { inherit path; });
    in {
      enable = true;
      tunnelId = "1536327b-2641-4706-8ad9-48c94d0b11f9";
      credentialsFile = config.age.secrets.cloudflared-tunnel-credentials.path;
      # n8n.heartwoodcraft.me → n8n (hwc-server until wave 4).
      n8nHost = server;
      extraIngress = {
        "mcp.heartwoodcraft.me" = "http://${server}:6200";
        "mcp.iheartwoodcraft.com" = "http://${server}:6200";
        "hwc-origin.heartwoodcraft.me" = "http://${server}:6200";

        # brain-mcp is local (wave 1).
        "brain.heartwoodcraft.me" = "http://localhost:9876";
        "brain.iheartwoodcraft.com" = "http://localhost:9876";
        "brain-origin.heartwoodcraft.me" = "http://localhost:9876";

        # datax-monitor — Cloudflare Access ("datax" allow-list) gates it; the
        # app has no auth of its own.
        "monitor.heartwoodcraft.me" = "http://${server}:4400";
        "monitor.iheartwoodcraft.com" = "http://${server}:4400";

        # Production-domain webhook ingress (calculator lead/appointment):
        # only /webhook/* reaches n8n; other paths hit the 404 default.
        "api.iheartwoodcraft.com" = {
          service = "http://${server}:5678";
          path = "^/webhook/";
        };

        # Umami — script.js + /api/send must be visitor-reachable.
        "stats.iheartwoodcraft.com" = viaServerCaddy "umami" null;

        # hwc-crm public intake, PATH-locked to /hooks/*; the board stays
        # tailnet-private. /hooks/jt is JobTread's webhook (hwc-crm D45).
        "crm.iheartwoodcraft.com" =
          viaServerCaddy "crm" "^/hooks/(contact|calculator|appointment|availability|jt)";

        # Calculator report viewer — read-only sanitised GET /api/reports/<id>.
        "reports.iheartwoodcraft.com" = viaServerCaddy "crm" "^/api/reports/";

        # hwc-mcp-gateway origin for lead-scout (Access service token).
        "leads-origin.heartwoodcraft.me" = viaServerCaddy "lead-scout" null;
      };
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
