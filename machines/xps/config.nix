# nixos-hwc/machines/xps/config.nix
#
# MACHINE: HWC-XPS
# Dell XPS 2018 — remote peer server with desktop environment.
# Peer server to hwc-server. Runs its own services independently.

{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware.nix

    # Profiles — core (system/paths/secrets) + session (GUI/audio/HM)
    ../../profiles/core.nix
    ../../profiles/session.nix
    ./home.nix  # Machine-specific HM overrides

    # Domains — xps-specific capabilities
    ../../domains/ai/index.nix
    ../../domains/alerts/index.nix
    ../../domains/networking/index.nix
    ../../domains/data/index.nix
    ../../profiles/monitoring.nix
    # ../../domains/media/index.nix    # Enable when storage is mounted
    # ../../domains/business/index.nix # Enable when business services are needed
  ];

  # System identity
  networking.hostName = "hwc-xps";
  networking.hostId = "a7c3d821";

  hwc.server.enable = true;

  # ZFS support for backup drives (if needed)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # ZFS configuration (if using ZFS for backups)
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

  # Storage — external DAS not yet connected
  hwc.system.mounts = {
    hot.enable = false;
    media.enable = false;
    backup.enable = false;
  };

  # Swap file for laptop (16GB recommended)
  swapDevices = [ { device = "/var/swapfile"; size = 16384; } ];

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
    tailscale.funnel.enable = false;
    firewall.level = lib.mkForce "server";
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

  hwc.automation.ntfy = {
    enable = false;
    serverUrl = "https://hwc-xps.ocelot-wahoo.ts.net:2586";
    defaultTopic = "hwc-xps-events";
    defaultTags = [ "hwc" "xps" "production" ];
    defaultPriority = 4;
    hostTag = true;
    auth.enable = false;
  };

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

  # Display manager (greetd for Wayland)
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  # AI domain — laptop profile for conservative thermal limits
  hwc.ai = {
    profiles.selected = "laptop";
    tools.enable = false;
    ollama.enable = false;
    local-workflows = {
      enable = false;
      fileCleanup.enable = false;
      journaling.enable = false;
      autoDoc.enable = false;
      chatCli.enable = false;
      api.enable = false;
    };
  };

  hwc.ai.open-webui = {
    enable = false;
    enableAuth = false;
  };

  hwc.ai.mcp = {
    enable = false;
    filesystem.nixos.enable = true;
    proxy.enable = true;
    reverseProxy.enable = true;
  };

  hwc.ai.router = {
    enable = false;
    port = 11435;
  };

  hwc.ai.agent = {
    enable = false;
    port = 6020;
  };

  hwc.networking.shared = {
    tailscaleDomain = "hwc-xps.ocelot-wahoo.ts.net";
    rootHost = "hwc-xps.ocelot-wahoo.ts.net";
  };

  hwc.data.backup.enable = true;

  # Reverse proxy for local services
  hwc.networking.reverseProxy.enable = true;

  # CouchDB for Obsidian LiveSync
  hwc.data.couchdb = {
    enable = true;
    settings = {
      port = 5984;
      bindAddress = "127.0.0.1";
    };
    monitoring.enableHealthCheck = true;
    reverseProxy = {
      enable = true;
      path = "/sync";
    };
  };

  hwc.alerts.server = {
    enable = true;
    port = 2586;
    dataDir = "/var/lib/hwc/ntfy";
  };

  # exportarr disabled — no *arr services on this machine
  hwc.monitoring.exportarr.enable = lib.mkForce false;

  services.openssh.settings = {
    X11Forwarding = lib.mkForce true;
    PasswordAuthentication = lib.mkForce true;  # Temporary — remove after SSH key update
  };

  hwc.system.core.session.sudo.extraRules = [
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

  hwc.system.core.packages.server.enable = true;

  system.stateVersion = "24.05";
}
