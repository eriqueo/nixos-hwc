# profiles/server/sys.nix — server role, NixOS lane
#
# Infra-serving bundle shared by all serving machines (containers, CouchDB,
# gotify server, ZFS hygiene, passwordless service management, server
# firewall posture). Anything one machine diverges on is overridden in its
# machine file (role values use mkDefault where override is expected).
#
# USED BY: see the machines table in flake.nix

{ config, lib, ... }:

{
  imports = [
    ../../domains/data/index.nix
    ../../domains/notifications/index.nix
  ];

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

  # Gotify notification server — machine files add token/admin wiring
  hwc.notifications.gotify = {
    enable = lib.mkDefault true;
    port = lib.mkDefault 2586;
    dataDir = lib.mkDefault "/var/lib/hwc/gotify";
  };

  # Passwordless service management for eric (waybar/agent tooling)
  hwc.system.core.session = {
    enable = true;
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
      # found 19GB unused); --all removes any image no container references
      autoPrune = {
        enable = lib.mkDefault true;
        flags = [ "--all" ];
        dates = lib.mkDefault "weekly";
      };
    };
    oci-containers.backend = lib.mkDefault "podman";
  };
}
