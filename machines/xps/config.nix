# nixos-hwc/machines/xps/config.nix
#
# MACHINE: HWC-XPS
# Dell XPS 2018 in Maryland — independent local media and proposed offsite
# recovery. Primary application ownership stays on home/work.

{ config, lib, pkgs, offsiteStorage ? null, ... }:
let
  mediaPool = "media-pool";
  dadHome = config.users.users.dad.home;
  # Same path the base role names for a primary Borg host; one producer.
  t3State = "${config.hwc.paths.user.home}/.t3/userdata";
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
    ../../domains/gaming/index.nix
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
  # Plasma's default daemon competes with this instance's existing TLP owner.
  services.power-profiles-daemon.enable = lib.mkForce false;

  # Covers Eric's Hyprland session and the no-session case only. Whenever dad's
  # Plasma session is active, PowerDevil takes logind's handle-lid-switch
  # inhibitor and these settings stop applying — the lid guarantee for that
  # session lives in domains/home/apps/plasma (plasmaLidPolicy).
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  services.thermald.enable = true;

  # Intel UHD 630 and NVIDIA GTX 1050 Ti Mobile were detected on 2026-10-22.
  # nouveau killed a game's GPU channel on 2026-10-25, so the GTX 1050 Ti
  # (Pascal) runs the last driver branch that supports it, the same one
  # hwc-home's P1000 uses. Intel keeps the panel; NVIDIA renders on demand.
  # Jellyfin stays on software encoding; hardware transcoding needs its own
  # real-transcode verification before it is enabled.
  hwc.system.hardware.gpu = {
    enable = true;
    type = "nvidia";
    nvidia = {
      driver = "legacy_580";
      # Server-era override; omitted on PRIME laptops (hwc-laptop precedent).
      legacyPerfLevelOverride = false;
      prime.enable = true;
      prime.nvidiaBusId = "PCI:1:0:0";
      prime.intelBusId = "PCI:0:2:0";
    };
  };
  hwc.gaming.steam.gpuOffload = true;

  # Unattended recovery for an unattended host: a panic or lockup reboots
  # instead of hanging, and a stalled PID 1 trips the hardware watchdog.
  # Boot/kernel trials stage the new generation with bootctl set-oneshot
  # while the default stays on the last good one (DEPLOYMENT.md).
  # Kernel parameters, not sysctls, so they hold before any module loads.
  # Soft lockups stay non-fatal: the USB enclosure has produced recoverable
  # stalls here.
  boot.kernelParams = [ "panic=10" "nmi_watchdog=panic" ];
  systemd.settings.Manager.RuntimeWatchdogSec = "60s";

  # Desktop environment
  hwc.system.apps.hyprland.enable = true;
  hwc.system.apps.waybar.enable = true;
  hwc.system.apps.chromium.enable = true;

  # Dad's desktop is separate from Eric's retained admin/Hyprland account.
  hwc.system.core.session.loginManager = {
    enable = true;
    backend = "plasma";
    autoLoginUser = "dad";
  };
  users.groups.dad = {};
  users.users.dad = {
    isNormalUser = true;
    uid = 1001;
    group = "dad";
    description = "Dad";
    home = "${builtins.dirOf config.hwc.paths.user.home}/dad";
    homeMode = "0700";
    shell = pkgs.bashInteractive;
    extraGroups = [ "video" "render" ];
    hashedPasswordFile = config.hwc.secrets.api.dad-login-password-hash;
  };
  home-manager.users.dad = {
    imports = [ ../../domains/home/apps/plasma/index.nix ];
    home = { username = "dad"; homeDirectory = dadHome; stateVersion = "26.05"; };
    hwc.home.apps.plasma.enable = true;
  };
  hwc.gaming.steam.enable = true;
  hardware.graphics = { enable = true; enable32Bit = true; };

  # A local household session may use the GPU, never service credentials or
  # system administration. Local Wi-Fi use must still work without Eric.
  # Eric retains the existing wheel/sudo policy and system connection ownership.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.user !== "dad") return;
      var wifiActions = [
        "org.freedesktop.NetworkManager.enable-disable-wifi",
        "org.freedesktop.NetworkManager.wifi.scan",
        "org.freedesktop.NetworkManager.network-control",
        "org.freedesktop.NetworkManager.settings.modify.own"
      ];
      if (subject.local && subject.active && wifiActions.indexOf(action.id) !== -1) {
        return polkit.Result.YES;
      }
      if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 ||
          action.id.indexOf("org.freedesktop.udisks2.") === 0 ||
          action.id.indexOf("org.freedesktop.systemd1.manage-") === 0 ||
          /^org\.freedesktop\.login1\.(power-off|reboot|suspend|hibernate|hybrid-sleep|set-|manage|halt)/.test(action.id)) {
        return polkit.Result.NO;
      }
    });
  '';
  services.logind.settings.Login.HandlePowerKey = "ignore";
  services.logind.settings.Login.HandleSuspendKey = "ignore";
  # CRITICAL documents and local game saves; downloads/installed games stay
  # replaceable on SSD. Precreate only the scoped source directories so the
  # existing bounded Borg job can run before Steam's first login.
  systemd.tmpfiles.rules = map (relative:
    "d ${dadHome}/${relative} 0700 dad dad -"
  ) [ "Documents" "Desktop" "Pictures" ".local" ".local/share"
      ".local/share/Steam" ".local/share/Steam/userdata"
      ".local/share/Steam/steamapps" ".local/share/Steam/steamapps/compatdata" ];

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
  hwc.data.borg = lib.mkIf (offsiteStorage != null && (offsiteStorage.recovery.ready or false)) {
    enable = true;
    primary.enable = false;
    monitoring.enable = true;
    sources = [ config.services.jellyfin.dataDir t3State ] ++ map (relative: "${dadHome}/${relative}") [
      "Documents" "Desktop" "Pictures" ".config"
      ".local/share/Steam/userdata" ".local/share/Steam/steamapps/compatdata"
    ];
    sqliteSnapshots.jellyfin = {
      source = "${config.services.jellyfin.dataDir}/data/jellyfin.db";
      user = "eric";
      maxBytes = 1073741824;
    };
    # CRITICAL: this host's T3 environment — the event-sourced thread store and
    # the server signing key, which no other machine holds and which nothing can
    # regenerate (losing the key invalidates every paired client).
    #
    # Spelled out HERE rather than inherited: profiles/base/sys.nix registers
    # the same three entries, but only when `primary.enable` is true, and XPS
    # deliberately keeps it false so a missing primary job is not invented. The
    # registrations are what is wanted; the primary job is not. ~/.t3/caches and
    # ~/.t3/worktrees stay REPLACEABLE and out — the source is `userdata` only.
    # The raw db/-wal/-shm/-journal tuple is excluded automatically by the
    # snapshot producer (domains/data/borg/index.nix `snapshotExcludes`), so
    # Borg stores the consistent copy and never a torn file beside live WAL.
    #
    # ONLY `t3-v2`, where the base role registers both V1 and V2. V1
    # (`state.sqlite`) exists on hwc-server and hwc-work because their stores
    # were MIGRATED to protocol 2 and keep the old file for rollback and lazy
    # import. This environment was created at protocol 2 and has no V1 history
    # to protect. Registering it anyway would not be harmless: a snapshot whose
    # source does not exist fails the copy worker, and `sqliteBackup` propagates
    # that with `|| exit "$?"`, taking down the Jellyfin and Dad-personal-file
    # archive with it. ADD `t3` WHEN: `~/.t3/userdata/state.sqlite` exists here.
    sqliteSnapshots.t3-v2 = { source = "${t3State}/statev2.sqlite"; user = "eric"; };
    excludePatterns = [
      "${config.services.jellyfin.dataDir}/cache"
      "${config.services.jellyfin.dataDir}/log"
      "${config.services.jellyfin.dataDir}/metadata"
      "${config.services.jellyfin.dataDir}/data/*.broken-backup"
      "${dadHome}/.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/windows/temp"
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

  # Keep pool queries out of Jellyfin's device sandbox. This short-lived
  # readiness unit can access /dev/zfs; the media daemon cannot.
  systemd.services.xps-media-ready = {
    after = [ "zfs-mount.service" ];
    requires = [ "zfs-mount.service" ];
    unitConfig = {
      RequiresMountsFor = [ config.hwc.paths.media.root ];
      AssertPathIsMountPoint = config.hwc.paths.media.root;
    };
    serviceConfig = {
      User = lib.mkForce "eric";
      Group = "users";
      Type = "oneshot";
      RemainAfterExit = false;
      DevicePolicy = "closed";
      DeviceAllow = [ "/dev/zfs rw" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      TimeoutStartSec = "15s";
      TimeoutStopSec = "5s";
    };
    script = ''
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

  # Refuse startup on an absent mount; finish the independent readiness
  # query before the native database preStart. Each start reruns the oneshot.
  systemd.services.jellyfin = {
    after = [ "zfs-mount.service" "xps-media-ready.service" ];
    requires = [ "zfs-mount.service" "xps-media-ready.service" ];
    unitConfig = {
      RequiresMountsFor = [ config.hwc.paths.media.root ];
      AssertPathIsMountPoint = config.hwc.paths.media.root;
    };
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
