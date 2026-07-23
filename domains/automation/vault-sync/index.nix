# domains/automation/vault-sync/index.nix
#
# Brain Vault Git Sync — periodic commit + pull + push of the brain vault
# against the bare hub repo (the vault's `origin` remote).
#
# In the Tier-2 architecture git is the ONLY vault sync transport: laptop and
# server are clones of the bare hub, the phone is a receive-only Syncthing
# mirror fed by the server. This timer is what keeps the server clone current
# and publishes server-side changes (brain-mcp refactors, mobile-inbox
# captures, automation outputs, manual edits) up to the hub so the laptop
# sees them on its next pull.
#
# Concurrency: all git access is serialized through an flock on
# <vault>/.git/.sync.lock. brain-mcp takes the SAME lock (see
# domains/server/native/ai/brain-mcp), so the timer and brain-mcp can never
# collide on index.lock.
#
# NAMESPACE: hwc.automation.vaultSync.*
#
# DEPENDENCIES:
#   - hwc.paths.brain.server-replica / .vault (the vault working copy)
#   - the vault repo must already have `origin` pointed at the bare hub

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.vaultSync;
  paths = config.hwc.paths;

  syncScript = pkgs.writeShellApplication {
    name = "brain-vault-sync";
    runtimeInputs = [ pkgs.git pkgs.coreutils pkgs.util-linux pkgs.openssh ];
    text = ''
      set -uo pipefail
      V=${lib.escapeShellArg (toString cfg.vaultDir)}
      cd "$V" || { echo "vault-sync: vault $V missing"; exit 1; }

      # Serialize ALL git access (shared with brain-mcp) via flock. Block until
      # the lock is free so we never race brain-mcp's checkpoint commits.
      exec 9>".git/.sync.lock"
      flock 9

      # 1. Commit any local vault changes. The server is a first-class committer
      #    in Tier-2; git add -A skips the embedded raw-import repos by design.
      if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "vault-sync: ${config.networking.hostName} auto-commit $(date -Iminutes)" || true
      fi

      # 2. Integrate hub (laptop) changes. --autostash guards any stray
      #    working-tree edit; abort cleanly on conflict rather than leaving a
      #    half-merged tree for a timer to trip over.
      if ! git pull --no-rebase --autostash --no-edit; then
        git merge --abort 2>/dev/null || true
        echo "vault-sync: pull failed (conflict?) — aborted, will retry" >&2
        exit 1
      fi

      # 3. Publish to the hub. Non-fatal if it fails (next cycle retries).
      git push || echo "vault-sync: push failed — will retry next cycle" >&2
    '';
  };

  # Event-driven companion: watch the vault tree and run the SAME sync script
  # within `debounceSec` of any create/update/delete/move, so local edits reach
  # the hub in seconds instead of waiting up to a full timer interval. It calls
  # syncScript directly (not `systemctl start`) so it needs no privilege and
  # shares the same flock — it can never race the timer or brain-mcp. The timer
  # still runs to provide the periodic PULL (remote changes when the laptop is
  # idle) and as a backstop if this watcher ever dies.
  watchScript = pkgs.writeShellApplication {
    name = "brain-vault-watch";
    runtimeInputs = [ pkgs.inotify-tools pkgs.coreutils ];
    text = ''
      set -uo pipefail
      V=${lib.escapeShellArg (toString cfg.vaultDir)}
      cd "$V" || { echo "vault-watch: vault $V missing"; exit 1; }
      DEBOUNCE=${toString cfg.watch.debounceSec}

      # Exclude paths that must NOT trigger a sync: `.git/` (else the sync's own
      # commits loop forever), the sync lock, and high-churn non-note state.
      EXCLUDE='(/\.git/|\.sync\.lock|/\.obsidian/workspace|/\.stversions/|/\.stfolder/|/\.trash/)'

      echo "vault-watch: watching $V (debounce ''${DEBOUNCE}s)"
      while true; do
        # Block until the first change anywhere in the tree.
        inotifywait -r -q -e modify,create,delete,move \
          --exclude "$EXCLUDE" "$V" >/dev/null || true
        # Debounce: keep draining events until DEBOUNCE seconds pass with none,
        # so a burst of saves coalesces into a single sync.
        while inotifywait -r -q -t "$DEBOUNCE" -e modify,create,delete,move \
          --exclude "$EXCLUDE" "$V" >/dev/null 2>&1; do :; done
        echo "vault-watch: changes settled — syncing"
        ${lib.getExe syncScript} || echo "vault-watch: sync failed — timer will retry" >&2
      done
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.automation.vaultSync = {
    enable = lib.mkEnableOption "Periodic git commit+pull+push of the brain vault to the hub";

    vaultDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if paths.brain.server-replica != null
        then paths.brain.server-replica
        else paths.brain.vault;
      description = "Brain vault working copy (a git clone of the bare hub)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User that owns the vault and runs the sync (must own .git and the hub)";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/15";
      description = "systemd OnCalendar expression for the sync cadence (default every 15 min)";
    };

    watch = {
      enable = lib.mkEnableOption ''
        an event-driven filesystem watcher that runs the sync within
        watch.debounceSec of any vault create/update/delete/move, so local edits
        reach the hub in seconds rather than waiting for the timer. The timer
        stays on for the periodic pull and as a backstop'';

      debounceSec = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Seconds of filesystem quiet to wait after the last change before syncing (coalesces bursts of saves into one sync)";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.vaultDir != null;
      message = "hwc.automation.vaultSync: vaultDir is null — brain vault path not defined on this host";
    }];

    systemd.services.brain-vault-sync = {
      description = "Brain vault git sync (commit + pull + push to hub)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = "users";
        ExecStart = lib.getExe syncScript;
        # ssh for the hub remote if it is ever an ssh:// URL; harmless otherwise.
        Environment = "HOME=/home/${cfg.user}";
      };
    };

    systemd.timers.brain-vault-sync = {
      description = "Periodic brain vault git sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };

    # Event-driven sync: long-running watcher that triggers the sync on any
    # vault CRUD (debounced). Runs as the vault owner and invokes syncScript
    # directly, so it shares the flock and needs no privilege escalation.
    systemd.services.brain-vault-watch = lib.mkIf cfg.watch.enable {
      description = "Brain vault change watcher (event-driven git sync)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        ExecStart = lib.getExe watchScript;
        Restart = "always";
        RestartSec = "5s";
        Environment = "HOME=/home/${cfg.user}";
      };
    };
  };
}
