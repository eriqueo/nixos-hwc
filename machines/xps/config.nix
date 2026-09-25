# nixos-hwc/machines/xps/config.nix
#
# MACHINE: HWC-XPS
# Dell XPS 2018 — remote peer server with desktop environment.
# Peer server to hwc-server. Runs its own services independently.

{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix

    # Roles (base, desktop, server) are supplied by the
    # flake.nix machines table — membership lives there, not here.
    # Machine-specific HM overrides live in ./home.nix (HM lane), wired by
    # the flake glue.

    # Domains — xps-specific capabilities
    ../../domains/ai/index.nix
    ../../domains/notifications/index.nix
    ../../domains/networking/index.nix
    ../../domains/data/index.nix
    # ../../domains/media/index.nix    # Enable when storage is mounted
    # ../../domains/business/index.nix # Enable when business services are needed
  ];

  # System identity
  networking.hostName = "hwc-xps";
  networking.hostId = "a7c3d821";

  # ZFS support for DAS media pool (scrub/trim hygiene from the server role)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;
  boot.zfs.extraPools = [ "media-pool" ];

  # Make ZFS import non-blocking — don't hang boot if DAS is disconnected
  systemd.services."zfs-import-media-pool" = {
    serviceConfig.TimeoutStartSec = "30s";  # Fail fast if pool unavailable
    unitConfig.ConditionPathExists = "/dev/sda";  # Skip entirely if DAS not connected
  };

  # Storage — external DAS not yet connected
  hwc.system.mounts = {
    hot.enable = false;
    media.enable = false;
    backup.enable = false;
  };

  # Swap file is defined in hardware.nix (was duplicated here — same entry).

  time.timeZone = "America/Denver";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Networking
  hwc.system.networking = {
    enable = true;
    networkManager.enable = true;

    # Wait for network (important for Tailscale and remote services)
    waitOnline.mode = "all";
    waitOnline.timeoutSeconds = 30;

    ssh.enable = true;
    tailscale.enable = true;
    # tailscale.funnel.* options removed when Funnel was retired in favor of
    # Cloudflare Tunnel (2026-05-22). Default = disabled; no setting needed.
    # firewall.level = "server" comes from the server role
    firewall.extraTcpPorts = [ 8096 7359 2283 4533 ];
    firewall.extraUdpPorts = [ 7359 ];
  };

  # Power management — keep laptop running 24/7
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      PCIE_ASPM_ON_AC = "default";
      RUNTIME_PM_ON_AC = "auto";
    };
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  services.thermald.enable = true;

  # hwc.data.backup — configure when /mnt/backup is mounted

  # GPU — Intel integrated only; uncomment if NVIDIA MX150 is detected
  # hwc.system.hardware.gpu = {
  #   type = "nvidia";
  #   nvidia.driver = "stable";
  # };

  # Desktop environment
  hwc.system.apps.hyprland.enable = true;
  hwc.system.apps.waybar.enable = true;
  hwc.system.apps.chromium.enable = true;

  # Session management (greetd + autologin) via hwc.system.core.session
  # Enabled by profiles/session.nix — autoLoginUser = "eric"
  hwc.system.core.session.loginManager.enable = true;

  hwc.ai.mcp = {
    enable = false;
    filesystem.nixos.enable = true;
    proxy.enable = true;
    reverseProxy.enable = true;
  };

  # Self serving-domain (rootHost/tailscaleDomain) now derives from
  # networking.hostName ("hwc-xps") + the shared tailnetSuffix — no override
  # needed. See domains/networking/{hosts,reverseProxy}.nix.

  # Off until /mnt/backup is mounted and a local/cloud method is configured —
  # enabled-with-no-methods was a no-op that only emitted an eval warning.
  hwc.data.backup.enable = false;

  # Reverse proxy for local services
  hwc.networking.reverseProxy.enable = true;

  # CouchDB for Obsidian LiveSync comes from the server role.

  # Not scraped: hwc-xps is not reachable from the fleet (no authorized ssh
  # key, 2026-09-25), so it cannot be deployed with a tailnet-bound agent;
  # enabling it would page "target down". Re-enable when it is reachable.
  # (Its own central stack was dropped with the monitoring role: its
  # Alertmanager posted to a dead localhost:11600.)
  hwc.monitoring.prometheus.agent.enable = false;

  # No automation on xps. n8n and mqtt live on the business role, which xps does
  # not take. The server role still imports domains/automation and defaults these
  # two on for the always-on machine; xps is not that machine, and a second
  # refinery would poll the same DataX queue as hwc-server.
  hwc.automation.nightlyBuilds.enable = false;
  hwc.automation.refinery.enable = false;

  services.openssh.settings = {
    X11Forwarding = lib.mkForce true;
  };

  # sudo NOPASSWD rules, permitCertUid, and the server package set come
  # from the server role.

  system.stateVersion = "24.05";
}
