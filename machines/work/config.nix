# hwc-work — staged MS-02 work server. Production service ownership remains
# on hwc-server until a service is migrated with its state and callers.
{ config, pkgs, ... }:
{
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
    # Service split wave 2 (fused window): scouts, control bot, Radicale and
    # the DX2 facts research-scout reads — machine-imported, as on hwc-server
    # before. The business apps come from the business role (flake.nix).
    ../../domains/server/native/ai/lead-scout/index.nix
    ../../domains/server/native/ai/hwc-control-bot/index.nix
    ../../domains/server/native/ai/home-scout/index.nix
    ../../domains/server/native/ai/research-scout/index.nix
    ../../domains/server/native/ai/event-scout/index.nix
    ../../domains/server/native/ai/dx2/index.nix
    ../../domains/server/services/radicale/index.nix
  ];

  networking.hostName = "hwc-work";
  system.stateVersion = "25.11";

  # The server role supplies Podman, CLI tools and server path defaults.
  # CouchDB and the Proton bridge stay on hwc-server until their own waves.
  hwc.data.couchdb.enable = false;
  # The cert exporter requires a system bridge unit no host runs, and nothing
  # reads its pem; the mail role's user-unit bridge serves plaintext loopback.
  hwc.mail.protonmailBridgeCert.enable = false;

  # Service split wave 2: the Proton Bridge session (mail role, HM user unit)
  # runs here. Expose its loopback-only SMTP/IMAP on the tailnet address for
  # hwc-server's consumers (crm, hwc-notify, paperless receipts, its mbsync),
  # which reach it through that host's own 127.0.0.1 relay.
  # TEMPORARY: removal = no Proton Bridge consumer left on hwc-server.
  hwc.mail.bridge.relay = {
    enable = true;
    listenAddress = config.hwc.networking.hosts.ips.work;
    targetAddress = "127.0.0.1";
  };

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
    # eriqueo/refinery dc1c39f: sourced DataX handoffs, built and checked locally
    # with deploy/build-image.sh from that commit; no registry pull.
    image = "localhost/refinery:dc1c39f-docker";
    imagePull = "never";
  };
  hwc.automation.nightlyBuilds = {
    enable = true;
  };
  hwc.automation.srGauntlet.enable = true;
  hwc.automation.dx1Gauntlet.enable = true;
  hwc.automation.vaultSync.enable = true;
  hwc.automation.brainSweep = {
    enable = true;
  };
  # hwc-notify — the one dispatcher (service split wave 3; was hwc-server).
  # Every sender on every host reaches it at hwc.notifications.notify.url.
  # The canary stays off (2026-08-29): it was loud when fine and quiet when
  # broken; rebuild it the other way round before re-enabling.
  hwc.notifications.notify.enable = true;
  hwc.notifications.canary.enable = false;

  # README freshness — weekly Law-12 drift report (Mon 09:00) → #nightly-builds.
  # Moved from hwc-server in wave 3 (it only stayed there because it asserted
  # a local dispatcher); it scans this host's ~/.nixos.
  hwc.automation.readmeFreshness.enable = true;

  # mail-janitor — weekly age-aware Gmail anti-buildup sweep (Sun 04:00).
  # Trashes NOISE at any age + TRANSACTIONAL older than 1yr; PRESERVE and the
  # Family-Friends label are never touched. Live since the 2026-06-24 dry run.
  # Moved from hwc-server in wave 3 with its triage-clock state.
  hwc.automation.mailJanitor.enable = true;
  hwc.automation.mailJanitor.dryRun = false;
  hwc.server.ai.brainMcp.enable = true;
  hwc.server.ai.brainvec.enable = true;
  # nomic-embed-text on CPU: the only inference this host runs. gpuLayers = 0
  # is what exempts it from the NVIDIA assertion; this host has an Intel iGPU.
  hwc.server.ai.llamaCpp = {
    enable = true;
    embed.enable = true;
    embed.gpuLayers = 0;
  };
  #==========================================================================
  # Service split wave 2 — business apps (business role since the fused
  # window; DataX monitor moved first in step 3b). Databases were restored
  # here from hwc-server's final pg_dumps. hwc-notify stays on hwc-server, so
  # every notifier posts to its tailnet port route.
  #==========================================================================
  # Role members that move in later waves stay off here until then.
  # TEMPORARY: each line goes in the commit that moves that app (waves 3/4).
  hwc.automation.n8n.enable = false;        # wave 4
  # Mosquitto stays with Frigate on hwc-server (roadmap end state), so the
  # role's mqtt membership is not for this host; revisit when the role moves (wave 5).
  hwc.automation.mqtt.enable = false;
  hwc.business.paperless.enable = false;    # wave 3
  hwc.business.firefly.enable = false;      # wave 3

  # The briefing keeps reporting the media/storage host's health: its
  # systemctl/disk/journal/VPN/backup sections run on hwc-server over ssh.
  # (Its Prometheus is the local central one since wave 3.)
  # TEMPORARY: removal = those sections read the central Prometheus instead.
  hwc.business.morningBriefing.hostHealthFrom = "main";

  # The hwc-sys gateway (+ JT tools). Binds all interfaces for tailnet
  # callers (laptop workbench, hwc-server Prometheus); tailscale0 is trusted.
  hwc.system.mcp.enable = true;
  hwc.system.mcp.jt.enable = true;
  hwc.system.mcp.host = "0.0.0.0";

  # Lead Scout — Facebook group lead scraper/classifier, MCP + HTTP on port 8420
  hwc.server.ai.leadScout.enable = true;
  hwc.server.ai.homeScout.enable = true;
  # Both scouts run from the scout monorepo (eriqueo/scout) as of 2026-07-19;
  # the old standalone clones are retained temporarily as rollback.
  hwc.server.ai.homeScout.projectDir = "/home/eric/600_apps/scout/apps/home-scout";
  hwc.server.ai.homeScout.workspaceRoot = "/home/eric/600_apps/scout";
  hwc.server.ai.leadScout.projectDir = "/home/eric/600_apps/scout/apps/lead-scout";
  hwc.server.ai.leadScout.workspaceRoot = "/home/eric/600_apps/scout";
  # Research Scout is paused because its scheduled research workload exceeds
  # its current use. Keep the module imported and its data/config intact so
  # resuming it is one explicit switch plus a rebuild.
  hwc.server.ai.researchScout.enable = false;
  # HWC classifier profiles post to #lead-scout;
  # DataX profiles stay on the default datax-discord-webhook (#jt-pros).
  hwc.server.ai.leadScout.channelMap = {
    hwc_bozeman_v1 = "discord-webhook-lead-scout";
    hwc_network_v1 = "discord-webhook-lead-scout";
  };
  # Each review program owns a private bot identity. DataX keeps its own
  # Gateway unit; the HWC bot's Gateway is consumed by hwc-control-bot (one
  # `/next` surface over Lead Scout, CRM, Research, Home). HWC approvals
  # remain review-only in the app and cannot publish a reply.
  hwc.server.ai.leadScout.controlTokenSecret = "hwc-control-lead-scout-token";
  hwc.server.ai.researchScout.controlTokenSecret = "hwc-control-research-scout-token";
  hwc.server.ai.hwcControlBot = {
    enable = true;
    # Research reviews: the one lane with a human review queue today.
    targets.researchScout = {
      # Must move with researchScout.enable: the adapter asserts its target is
      # live and would otherwise keep a dead dependency in /next.
      enable = false;
      profile = "llm_engineering_v1";
    };
    # CRM next actions: note, snooze, disqualify only (no sends, no JT).
    targets.crm.enable = true;
    # Home listing reviews: interested / pass / wrong tier on Eric's BUYING
    # lens. The remodel lens is a business signal, not a preference to record.
    targets.homeScout = {
      enable = true;
      profile = "home_buy_bozeman";
    };
    # Curated Bozeman event cards and Add / Ignore actions live in #events.
    # n8n owns the ledger and calendar effect; this bot owns Discord transport.
    targets.events = {
      enable = true;
      channelId = "1545506587815313560";
    };
    # One post at 07:30, only when the counts moved since the last one.
    summary.enable = true;
  };
  hwc.business.crm.controlTokenSecretRef = "hwc-control-crm-token";
  # Calendars outside Radicale that also make Eric busy for website bookings.
  hwc.business.crm.calendar.busyFeeds = {
    "ContractorCTO" = "cto-ical-link";
    "Proton work" = "proton-ical-link";
    "Google family" = "hwcmt-ical-link";
  };
  hwc.server.native.ai.event-scout = {
    enable = true;
    reviewerId = config.hwc.server.ai.leadScout.discordApprovalBots.hwc.allowedUserId;
  };
  hwc.server.ai.homeScout.controlTokenSecret = "hwc-control-home-scout-token";
  hwc.server.ai.leadScout.discordApprovalBots = {
    datax-jtpros = {
      enable = true;
      botTokenSecret = "hermes-discord-bot-token";
      guildId = "1503422144829460592";
      channelId = "1503607114042576936";
      allowedUserId = "1501391621521150075";
      profileIds = ["datax_jtpros"];
    };
    hwc = {
      enable = true;
      botTokenSecret = "hwc-lead-scout-bot-token";
      guildId = "1503422144829460592";
      channelId = "1545506724750958602";
      allowedUserId = "1501391621521150075";
      profileIds = [
        "hwc_bozeman_v1"
        "hwc_network_v1"
      ];
      gateway = "hwc-control-bot";
    };
  };


  # Radicale — self-hosted CalDAV for two-way task sync with list creation
  # (todui N key). Behind Caddy at tasks.hwc.iheartwoodcraft.com. Requires the
  # radicale-htpasswd agenix secret (domains/secrets/parts/services/).
  hwc.server.services.radicale = {
    enable = true;
    reverseProxy.enable = true;
    # Outside calendars mirrored read-only into Radicale every 15 min, so the
    # phone's one CalDAV account and khal show them. Same three secrets the
    # CRM's busyFeeds read above; the ids are pinned on each khal machine in
    # hwc.mail.calendar.radicale.extraCollections.
    mirrors = {
      cto           = { secret = "cto-ical-link";    displayName = "ContractorCTO"; color = "#FF9F0A"; };
      proton-work   = { secret = "proton-ical-link"; displayName = "Proton work";   color = "#BF5AF2"; };
      google-family = { secret = "hwcmt-ical-link";  displayName = "Google family"; color = "#30D158"; };
    };
  };


  # Workbench hub served from here; hwc-server keeps the module on for its
  # own refinery areas.json but proxies the vhost to this host.
  hwc.business.workbench = {
    enable = true;
    # Areas whose apps are still on hwc-server (wave 2/3). Remove each name
    # from this list in the commit that moves its app here.
    remoteRoutes = [ "firefly-explorer" ];
  };

  #==========================================================================
  # CLOUDFLARE TUNNEL (public ingress) — service split wave 2, step 1
  #==========================================================================
  # The one tunnel moved here from hwc-server with the same credential; every
  # hostname, path lock and Access policy is unchanged. Since the wave 2
  # fused window every origin is local except n8n, which stays on hwc-server
  # until wave 4 and is reached over the tailnet (it binds all interfaces).
  # TEMPORARY (n8n targets): flip to localhost when n8n moves (wave 4).
  #
  # History carried from hwc-server: Phase 4.6 (2026-07-07) found the planned
  # *.api.iheartwoodcraft.com subzone impossible on the free plan (subdomain
  # zones are Enterprise-only; proxied two-level names lack Universal SSL), so
  # production ingress rides the one-level api.iheartwoodcraft.com with PATH
  # routing (wiki/nixos/iheartwoodcraft-com-backend-migration.md). The .com
  # twins of .me names (2026-07-19) run in parallel until callers flip, then
  # the .me entries drop (brain: tech/development/builds/heartwoodcraft_me_retirement.md).
  # *-origin names are what the hwc-mcp-gateway OAuth Worker proxies to with an
  # Access service token (~/600_apps/hwc-mcp-gateway/ORIGINS.md).
  hwc.networking.cloudflared =
    let
      server = config.hwc.networking.hosts.ips.main;
    in {
      enable = true;
      tunnelId = "1536327b-2641-4706-8ad9-48c94d0b11f9";
      credentialsFile = config.age.secrets.cloudflared-tunnel-credentials.path;
      # n8n.heartwoodcraft.me → n8n (hwc-server until wave 4).
      n8nHost = server;
      extraIngress = {
        "mcp.heartwoodcraft.me" = "http://localhost:6200";
        "mcp.iheartwoodcraft.com" = "http://localhost:6200";
        "hwc-origin.heartwoodcraft.me" = "http://localhost:6200";

        # brain-mcp is local (wave 1).
        "brain.heartwoodcraft.me" = "http://localhost:9876";
        "brain.iheartwoodcraft.com" = "http://localhost:9876";
        "brain-origin.heartwoodcraft.me" = "http://localhost:9876";

        # datax-monitor — Cloudflare Access ("datax" allow-list) gates it; the
        # app has no auth of its own.
        "monitor.heartwoodcraft.me" = "http://localhost:4400";
        "monitor.iheartwoodcraft.com" = "http://localhost:4400";

        # Production-domain webhook ingress (calculator lead/appointment):
        # only /webhook/* reaches n8n; other paths hit the 404 default.
        "api.iheartwoodcraft.com" = {
          service = "http://${server}:5678";
          path = "^/webhook/";
        };

        # Umami — script.js + /api/send must be visitor-reachable.
        "stats.iheartwoodcraft.com" = "http://localhost:3009";

        # hwc-crm public intake, PATH-locked to /hooks/*; the board stays
        # tailnet-private. /hooks/jt is JobTread's webhook (hwc-crm D45).
        "crm.iheartwoodcraft.com" = {
          service = "http://localhost:11660";
          path = "^/hooks/(contact|calculator|appointment|availability|jt)";
        };

        # Calculator report viewer — read-only sanitised GET /api/reports/<id>.
        "reports.iheartwoodcraft.com" = {
          service = "http://localhost:11660";
          path = "^/api/reports/";
        };

        # hwc-mcp-gateway origin for lead-scout (Access service token).
        "leads-origin.heartwoodcraft.me" = "http://localhost:8420";
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

  # PostgreSQL 15 matches the server cluster so per-database dumps restore
  # without a version step. The container network binding (10.89.0.1) is on
  # since Umami (a container) moved here in wave 2; refinery keeps the media
  # network's bridge up, so the module's wait for the gateway IP resolves.
  hwc.data.databases.postgresql = {
    enable = true;
    version = "15";
    package = pkgs.postgresql_15;
    containerNetwork.enable = true;
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
      # Service split wave 2 (fused window). hwc-server's borg never covered
      # these three; the databases ride the pg_dumpall above.
      "/var/lib/radicale"    # CalDAV/CardDAV collections (CRITICAL)
      "/var/lib/estimator"   # built estimator bundle (REPLACEABLE, small)
      "/opt/business"        # CMS app, website repo working tree, jt-mcp
      "/home/eric/600_apps/sr_analyzer/data" # SR board SQLite (CRITICAL)
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
