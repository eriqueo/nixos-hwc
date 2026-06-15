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
        git commit -m "vault-sync: server auto-commit $(date -Iminutes)" || true
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
  };
}
