# profiles/server/sys.nix — server role, NixOS lane
#
# Infra-serving bundle shared by all serving machines (containers, CouchDB,
# ZFS hygiene, passwordless service management, server
# firewall posture). Anything one machine diverges on is overridden in its
# machine file (role values use mkDefault where override is expected).
#
# USED BY: see the machines table in flake.nix

{ config, lib, ... }:

{
  imports = [
    ../../domains/data/index.nix
    ../../domains/notifications/index.nix
    ../../domains/automation/index.nix
    # Failure alerting (alerts/), exporters and heartbeat live in the
    # monitoring domain; the central Prometheus/Grafana stack is the
    # monitoring ROLE. Every serving host alerts on its own units.
    ../../domains/monitoring/index.nix
  ];

  # Notifications: every serving host sends through hwc-alert to the one
  # dispatcher at hwc.notifications.notify.url (the dispatcher itself is
  # enabled on its host's machine config).
  hwc.notifications = {
    enable = lib.mkDefault true;
    send.cli.enable = lib.mkDefault true;
  };

  # SMART disk monitoring on every serving host (was a single machine's
  # one-off, so the other serving hosts had none). Short test daily 02:00,
  # long test Saturdays 03:00.
  services.smartd = {
    enable = lib.mkDefault true;
    autodetect = lib.mkDefault true;
    notifications.wall.enable = lib.mkDefault true;
    defaults.monitored = lib.mkDefault "-a -o on -s (S/../.././02|L/../../6/03)";
  };

  # Service-failure, SMART and backup alerts for this host's own units. The
  # unit list is gated on each owning module's enable, so it follows the
  # apps (domains/monitoring/alerts). Disk space is owned by Prometheus.
  hwc.monitoring.alerts = {
    enable = lib.mkDefault true;
    sources.serviceFailures = {
      enable = lib.mkDefault true;
      autoDetect = lib.mkDefault true;
    };
    sources.smartd.enable = lib.mkDefault config.services.smartd.enable;
    sources.backup = {
      enable = lib.mkDefault true;
      onSuccess = lib.mkDefault false;
      onFailure = lib.mkDefault true;
    };
  };

  # Server identity (Charter v10.3 multi-server support) — flips path
  # defaults in domains/paths to server layout.
  hwc.server.enable = true;

  # ZFS data integrity (pools themselves are machine hardware concerns)
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";
    };
    trim = {
      enable = true;
      interval = "weekly";
    };
  };

  # CouchDB for Obsidian LiveSync
  hwc.data.couchdb = {
    enable = lib.mkDefault true;
    settings = {
      port = lib.mkDefault 5984;
      bindAddress = lib.mkDefault "127.0.0.1";  # Localhost only for security
    };
    monitoring.enableHealthCheck = lib.mkDefault true;
    reverseProxy = {
      enable = lib.mkDefault true;  # Expose via Caddy for remote access
      path = lib.mkDefault "/sync"; # Match Obsidian's expected path
    };
  };

  # Nightly Builds — unattended overnight gauntlet-card runner. Lives on the
  # server role because the always-on machine is the one that runs overnight.
  hwc.automation.nightlyBuilds.enable = lib.mkDefault true;

  # Refinery — read-only Kanban board for the gauntlet hopper (port 8060,
  # behind Caddy as refinery.hwc.iheartwoodcraft.com).
  hwc.automation.refinery.enable = lib.mkDefault true;
  # 2026-09-04: the Refinery runs as the eriqueo/refinery container image (one
  # artifact for this host and a droplet). Native mode remains selectable.
  hwc.automation.refinery.mode = lib.mkDefault "container";

  # Passwordless service management for eric (waybar/agent tooling).
  # Lingering keeps eric's user units (rootless podman, the Proton Bridge,
  # T3 serve) running on a serving host with nobody logged in.
  hwc.system.core.session = {
    enable = true;
    linger.enable = lib.mkDefault true;
    linger.users = [ "eric" ];
    sudo.enable = true;
    sudo.wheelNeedsPassword = lib.mkDefault false;
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
  };

  # Caddy fetches tailnet certs via tailscaled
  services.tailscale.permitCertUid = lib.mkIf config.services.caddy.enable "caddy";

  # Server firewall posture (base sets "strict"; serving machines open up)
  hwc.system.networking.firewall.level = lib.mkForce "server";

  # Server CLI package set
  hwc.system.core.packages.server.enable = true;

  # Container runtime — Podman only, Docker force-disabled
  virtualisation = {
    docker.enable = lib.mkForce false;
    podman = {
      enable = true;
      dockerCompat = lib.mkDefault true;
      defaultNetwork.settings.dns_enabled = lib.mkDefault true;
      # Old :latest pulls accumulate ~1GB/week without this (2026-06-09 audit
      # found 19GB unused). Superseded :latest layers go UNTAGGED on re-pull, so
      # a plain prune still reclaims them — which is what that audit measured.
      #
      # --all was removed 2026-08-16: it drops any image no *running* container
      # references, so a container stopped across the timer loses its image and
      # the next `--pull missing` start silently fetches current :latest. It ate
      # recyclarr's image on 2026-08-10; with the arrs on :latest that path is a
      # forward-only DB migration (Radarr 6.3.0) against zero backups.
      autoPrune = {
        enable = lib.mkDefault true;
        flags = [ ];
        dates = lib.mkDefault "weekly";
      };
    };
    oci-containers.backend = lib.mkDefault "podman";
  };
}
