# domains/automation/brain-sweep/index.nix
#
# Brain Janitor — the nightly mechanical sweep. Runs `brain sweep --report` (the brain CLI at
# ~/600_apps/brain) against the vault, writing a dated, append-only drift report to
# _inbox/janitor/. A DETECTOR, not a fixer: it edits no note. vault-sync then carries the report
# to the hub.
#
# Pattern: same "code lives in its own ~/600_apps checkout, Nix only schedules + provides the
# environment" shape as brainvec (domains/server/native/ai/brainvec). A missing/unbuilt checkout
# logs the fix and exits 0 — a rebuild without the code degrades gracefully.
#
# NAMESPACE: hwc.automation.brainSweep.*
# DEPENDENCIES:
#   - the brain CLI checkout at cfg.repoDir (built: dist/bin/brain.js + node_modules)
#   - the vault working copy (cfg.vaultDir) with its .git/.sync.lock (shared flock)
#   - hwc-notify listening on cfg.notifyUrl (optional; fail-soft)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.brainSweep;
  paths = config.hwc.paths;

  sweepScript = pkgs.writeShellApplication {
    name = "brain-sweep";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.git pkgs.util-linux pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      set -uo pipefail
      REPO=${lib.escapeShellArg (toString cfg.repoDir)}
      VAULT=${lib.escapeShellArg (toString cfg.vaultDir)}
      NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
      export BRAIN_VAULT="$VAULT"

      if [ ! -f "$REPO/dist/bin/brain.js" ]; then
        echo "brain checkout missing/unbuilt — run: deploy brain  (git clone <remote> $REPO && cd $REPO && npm ci && npm run build)"
        exit 0
      fi
      # NB: no `git pull` here — this app needs a build step, so pull+build is owned by deploy.sh
      # (the `deploy brain` path), not the nightly job. The nightly job runs the pre-built dist only,
      # so a half-updated source tree can never ship an unbuilt sweep.

      # Serialize vault access on the SHARED lock (vault-sync + brain-mcp take the same one), so the
      # sweep never races a commit. Blocking flock; released when this script exits.
      exec 9>"$VAULT/.git/.sync.lock"
      flock 9

      set +e
      node "$REPO/dist/bin/brain.js" sweep --report
      rc=$?
      set -e

      # Exit-code contract from `brain sweep`: 0 = clean or review-level (report is the deliverable,
      # no 3am push), 2 = an ALERT-severity trip (push), other = the sweep itself failed (push + fail).
      title=""; pri=2
      case "$rc" in
        0) exit 0 ;;
        2) title="brain janitor: ALERT-level drift (see _inbox/janitor/)" ;;
        *) title="brain sweep FAILED (exit $rc)" ;;
      esac

      if [ -n "$NOTIFY_URL" ]; then
        jq -nc --arg t "$title" \
          '{topic:"automation", source:"brain-sweep", title:$t, body:"", priority:'"$pri"', tags:["brain","janitor"]}' \
          | curl -fsS --max-time 8 -X POST -H 'content-type: application/json' \
              -d @- "$NOTIFY_URL/notify" >/dev/null 2>&1 \
          || echo "WARN: hwc-notify unreachable (alert dropped)"
      fi

      # An alert-level trip is a successful sweep (unit stays green); a real failure fails the unit.
      [ "$rc" = "2" ]
    '';
  };
in {
  options.hwc.automation.brainSweep = {
    enable = lib.mkEnableOption "nightly brain sweep — the vault-drift janitor (writes _inbox/janitor/)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User the sweep runs as (must own the vault + checkout).";
    };

    repoDir = lib.mkOption {
      type = lib.types.str;
      default = "${paths.user.home}/600_apps/brain";
      description = "The brain CLI checkout (built: dist/bin/brain.js + node_modules).";
    };

    vaultDir = lib.mkOption {
      type = lib.types.str;
      default =
        if paths.brain.vault != null then toString paths.brain.vault
        else if paths.brain.server-replica != null then toString paths.brain.server-replica
        else "${paths.user.home}/900_vaults/brain";
      description = "The brain vault working copy the sweep reads and writes into.";
    };

    notifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11600";
      description = "hwc-notify base URL; the sweep POSTs to <url>/notify on alert/failure. Empty disables.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 03:30:00";
      description = "systemd OnCalendar for the nightly sweep.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.brain-sweep = {
      description = "Brain janitor — nightly vault-drift sweep (writes _inbox/janitor/ under flock)";
      after = [ "network-online.target" "brain-vault-sync.service" ];
      wants = [ "network-online.target" ];
      environment.HOME = "/home/${cfg.user}";
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce cfg.user;
        Group = "users";
        ExecStart = "${sweepScript}/bin/brain-sweep";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.brain-sweep = {
      description = "Nightly trigger for the brain janitor sweep";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "2m";
      };
    };
  };
}
