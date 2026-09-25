# hwc-work — staged MS-02 work server. Production service ownership remains
# on hwc-server until a service is migrated with its state and callers.
{ pkgs, ... }: {
  imports = [
    ./hardware.nix
    # Notification routes need the networking domain's shared vocabulary,
    # even while this host's reverse proxy remains disabled.
    ../../domains/networking/index.nix
  ];

  networking.hostName = "hwc-work";
  system.stateVersion = "25.11";

  # The server role supplies Podman, CLI tools and server path defaults. These
  # three role defaults would otherwise create a second live stateful writer.
  hwc.data.couchdb.enable = false;
  hwc.automation.nightlyBuilds.enable = false;
  hwc.automation.refinery.enable = false;
  hwc.mail.protonmailBridgeCert.enable = false;

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
