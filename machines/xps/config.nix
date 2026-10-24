# nixos-hwc/machines/xps/config.nix
#
# MACHINE: HWC-XPS
# Dell XPS 2018 in Maryland — independent local media and proposed offsite
# recovery. Primary application ownership stays on home/work.

{ config, lib, pkgs, offsiteStorage ? null, ... }:
let
  mediaPool = "media-pool";
  offsiteDataset = "${mediaPool}/offsite";
  offsiteRoot = config.hwc.paths.backup;
  offsitePeers = {
    hwc-home = { directory = "home"; datasetQuota = "805306368000"; borgQuota = "700G";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPQWOW7Pznzp3hEMz3guzJN2zwf/Qvcl+bmR/kH2upNT borg-home-offsite-ssh-key"; };
    hwc-work = { directory = "work"; datasetQuota = "161061273600"; borgQuota = "140G";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJWkksdWaqAL9rUv48tIhDneMgvoS1+UrQavhMNAadb6 borg-work-offsite-ssh-key"; };
  };
  offsiteRepoGuard = name: {
    # Hold automatic directory/dataset creation while the cable/recovery gate
    # is closed. Remove this hold by opening ready after destination acceptance.
    wantedBy = lib.mkForce (lib.optional (offsiteStorage != null && offsiteStorage.ready) "multi-user.target");
    after = [ "xps-offsite-storage.service" ];
    requires = [ "xps-offsite-storage.service" ];
    unitConfig.AssertPathIsMountPoint = config.services.borgbackup.repos.${name}.path;
  };
  offsiteBootstrap = ''
    set -euo pipefail
    test "$(${pkgs.coreutils}/bin/timeout 10s ${config.boot.zfs.package}/bin/zpool list -H -o health ${mediaPool})" = ONLINE
    datasets=$(${pkgs.coreutils}/bin/timeout 10s ${config.boot.zfs.package}/bin/zfs list -H -o name -r ${mediaPool})
    dataset_exists() {
      printf '%s\n' "$datasets" | ${pkgs.ripgrep}/bin/rg --fixed-strings --line-regexp --quiet "$1"
    }
    validate_dataset() {
      local dataset="$1" mountpoint="$2" quota="$3"
      if dataset_exists "$dataset"; then
        test "$(${config.boot.zfs.package}/bin/zfs get -H -o value mountpoint "$dataset")" = "$mountpoint"
        test "$(${config.boot.zfs.package}/bin/zfs get -Hp -o value quota "$dataset")" = "$quota"
        ${pkgs.util-linux}/bin/mountpoint --quiet "$mountpoint"
      fi
    }
    ensure_dataset() {
      local dataset="$1" mountpoint="$2" quota="$3"
      if ! dataset_exists "$dataset"; then
        ${config.boot.zfs.package}/bin/zfs create -o "mountpoint=$mountpoint" -o "quota=$quota" -o compression=zstd "$dataset"
      fi
      ${pkgs.util-linux}/bin/mountpoint --quiet "$mountpoint"
    }
    # Validate the entire existing set before creating any missing child.
    validate_dataset ${offsiteDataset} ${lib.escapeShellArg offsiteRoot} 1099511627776
    ${lib.concatMapStrings (peer: ''
      validate_dataset ${offsiteDataset}/${peer.directory} ${lib.escapeShellArg "${offsiteRoot}/${peer.directory}"} ${peer.datasetQuota}
    '') (builtins.attrValues offsitePeers)}
    ensure_dataset ${offsiteDataset} ${lib.escapeShellArg offsiteRoot} 1099511627776
    ${pkgs.coreutils}/bin/chmod 0711 ${lib.escapeShellArg offsiteRoot}
    ${lib.concatMapStrings (peer: ''
      ensure_dataset ${offsiteDataset}/${peer.directory} ${lib.escapeShellArg "${offsiteRoot}/${peer.directory}"} ${peer.datasetQuota}
      ${pkgs.coreutils}/bin/chown borg:users ${lib.escapeShellArg "${offsiteRoot}/${peer.directory}"}
      ${pkgs.coreutils}/bin/chmod 0700 ${lib.escapeShellArg "${offsiteRoot}/${peer.directory}"}
    '') (builtins.attrValues offsitePeers)}
  '';
in {
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
    ../../domains/media/jellyfin-native/index.nix
    # ../../domains/business/index.nix # Enable when business services are needed
  ];

  # System identity
  networking.hostName = "hwc-xps";
  networking.hostId = "a7c3d821";

  # ZFS support for DAS media pool (scrub/trim hygiene from the server role)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;
  boot.zfs.extraPools = [ mediaPool ];

  # Make ZFS import non-blocking — don't hang boot if DAS is disconnected
  systemd.services."zfs-import-${mediaPool}" = {
    serviceConfig.TimeoutStartSec = "30s";  # Fail fast if pool unavailable
  };

  # ZFS imports the external media pool; the generic mount module must not
  # create a competing ext4 mount for it.
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

  # Intel UHD 630 and NVIDIA GTX 1050 Ti Mobile were detected on 2026-10-22.
  # Jellyfin starts with software encoding; hardware acceleration needs its
  # own driver and real-transcode verification before it is enabled.

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

  # AUTO-MANAGED: independent Borg archives, bounded by parent/child ZFS
  # quotas and client retention. Never upgrade the pool or resize an existing
  # dataset silently. This creates no dataset until the reviewed unit runs.
  hwc.paths.backup = "${config.hwc.paths.media.root}/offsite";
  services.borgbackup.repos = lib.mapAttrs (_: peer: {
    path = "${offsiteRoot}/${peer.directory}";
    authorizedKeys = [ peer.key ];
    quota = peer.borgQuota;
    allowSubRepos = false;
    user = "borg";
    group = "users";
  }) offsitePeers;
  systemd.services.xps-offsite-storage = {
      description = "Prepare bounded XPS offsite datasets";
      after = [ "zfs-mount.service" ];
      requires = [ "zfs-mount.service" ];
      unitConfig = {
        RequiresMountsFor = [ config.hwc.paths.media.root ];
        AssertPathIsMountPoint = config.hwc.paths.media.root;
      };
      script = offsiteBootstrap;
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = "60s"; TimeoutStopSec = "10s"; };
  };
  # Native repo-directory initialization must not run on a fallback path.
  systemd.services.borgbackup-repo-hwc-home = offsiteRepoGuard "hwc-home";
  systemd.services.borgbackup-repo-hwc-work = offsiteRepoGuard "hwc-work";

  # CRITICAL: library definitions, users and watch history. Source/config and
  # media have separate owners; archive a consistent SQLite copy, not WAL files.
  hwc.data.borg = lib.mkIf (offsiteStorage != null && offsiteStorage.ready) {
    enable = true;
    primary.enable = false;
    sources = [ config.services.jellyfin.dataDir ];
    sqliteSnapshots.jellyfin = {
      source = "${config.services.jellyfin.dataDir}/data/jellyfin.db";
      user = "eric";
      maxBytes = 1073741824;
    };
    excludePatterns = [
      "${config.services.jellyfin.dataDir}/cache"
      "${config.services.jellyfin.dataDir}/log"
      "${config.services.jellyfin.dataDir}/metadata"
      "${config.services.jellyfin.dataDir}/data/*.broken-backup"
    ];
    additionalDestinations.home = {
      host = offsiteStorage.recovery.address;
      user = offsiteStorage.recovery.repository.user;
      repository = offsiteStorage.recovery.repository.path;
      hostKey = offsiteStorage.recovery.hostKey;
      sshKeySecret = "borg-xps-state-ssh-key";
      passphraseSecret = "borg-xps-state-passphrase";
      startAt = "*-*-* 02:30:00";
      timeoutSeconds = 3600;
      uploadLimitKiB = 1024;
    };
  };

  # Independent Maryland library. Clients use this host's LAN address rather
  # than the home server's Jellyfin vhost, so playback stays in this house.
  # Media is REPLACEABLE from the home library; existing Jellyfin users and
  # library definitions remain in the native service's persistent state.
  hwc.media.jellyfin = {
    enable = true;
    openFirewall = true;
    gpu.enable = false;
    network.localSubnets = [ "192.168.1.0/24" ];
  };

  # Refuse to scan the root filesystem's empty mount directory when the DAS
  # is absent. ZFS owns the mount, and the assertion fails startup loudly.
  systemd.services.jellyfin = {
    after = [ "zfs-mount.service" ];
    requires = [ "zfs-mount.service" ];
    unitConfig = {
      RequiresMountsFor = [ config.hwc.paths.media.root ];
      AssertPathIsMountPoint = config.hwc.paths.media.root;
    };
    # A suspended ZFS pool can remain mounted. Check the pool's own health
    # before Jellyfin touches its database or scans files; never wait forever.
    preStart = lib.mkBefore ''
      if ! pool_health=$(${pkgs.coreutils}/bin/timeout 10s ${config.boot.zfs.package}/bin/zpool list -H -o health ${lib.escapeShellArg mediaPool}); then
        echo "Jellyfin cannot read the media pool state. Inspect: zpool status ${mediaPool}" >&2
        exit 1
      fi
      case "$pool_health" in
        ONLINE) ;;
        DEGRADED)
          echo "WARNING: The media mirror is degraded. Inspect: zpool status ${mediaPool}" >&2
          ;;
        *)
          echo "Jellyfin cannot use the media pool in state $pool_health. Inspect: zpool status ${mediaPool}" >&2
          exit 1
          ;;
      esac
    '';
  };

  # Reverse proxy for local services
  hwc.networking.reverseProxy.enable = true;

  # The older running generation still has CouchDB and a central monitoring
  # stack. This source does not enable them. Classify their consumers before
  # switching; keep the migration and current state in DEPLOYMENT.md.

  # Central monitoring stays on work. Its fleet aggregation reads this
  # agent declaration and automatically includes XPS node/service probes.
  hwc.monitoring.prometheus.agent.enable = offsiteStorage != null && (offsiteStorage.ready or false);

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
