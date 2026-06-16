# domains/automation/nightly-builds/index.nix
#
# Nightly Builds — unattended overnight execution of gauntlet cards.
#
# Picks up cards marked `status: queued` from the brain vault's
# _inbox/nightly_builds/ goal folders, runs each in a disposable git
# worktree of the nixos repo via headless Claude Code, writes a
# self-verifying REPORT.md into the vault's runs/ tree, pushes the
# result branch to origin, and flips the card status. A card-smith
# pre-pass drafts new cards from _ideas.md (drafts only — a human
# flips draft -> queued; that flip IS the Phase-4 gate).
#
# Containment model (gauntlet gate 7): output goes to branches and the
# vault only. The agent never runs nixos-rebuild and never touches live
# services; morning review is the only thing that promotes anything.
#
# NAMESPACE: hwc.automation.nightlyBuilds.*
#
# DEPENDENCIES:
#   - hwc.paths.nixos (repo working copy)
#   - hwc.paths.brain.server-replica / .vault (Syncthing'd brain vault)
#   - Claude Code CLI authenticated for the eric user

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.nightlyBuilds;
  paths = config.hwc.paths;
  agentDir = "${paths.nixos}/domains/automation/nightly-builds";

  # Shared spool dir for the refinery board's "▶ Run now" / IMMEDIATE mode: the
  # (sandboxed) board drops a <goal> request file here; the path-triggered
  # drain unit below executes run.sh scoped to that one project. This MUST match
  # the board's REFINERY_RUNNOW_SPOOL (domains/automation/refinery/index.nix).
  spoolDir = "/var/lib/refinery/run-now";

  # Env + tool path shared by the nightly run and the run-now drain (same script,
  # same needs: git push, headless claude, jq/rg/awk/curl).
  nbEnv = {
    HOME = paths.user.home;
    NB_VAULT_DIR = toString cfg.vaultDir;
    NB_REPO_DIR = toString cfg.repoDir;
    NB_MAX_CARDS = toString cfg.maxCards;
    # Discord webhook for rich per-card report delivery (summary + REPORT.md
    # attached). send-report.sh posts directly here; metadata-only fallbacks
    # still go through hwc-notify. Same secret the discord-nightly-builds
    # notify channel uses; readable by the eric-run service (owner).
    NB_DISCORD_WEBHOOK_FILE = config.age.secrets."discord-webhook-nightly-builds".path;
  };
  nbPath = [
    pkgs.bash pkgs.coreutils pkgs.git pkgs.openssh
    pkgs.nodejs_22 pkgs.python3 pkgs.jq pkgs.ripgrep
    pkgs.gawk  # send-report.sh parses REPORT.md with awk
    pkgs.curl  # POST run results to hwc-notify + Discord webhook
  ];

  # Drains the run-now spool: for each requested goal, consume the request file
  # first (so a re-click during the run is captured as a fresh request and the
  # path unit doesn't re-fire on the same file), then run run.sh scoped to that
  # goal. run.sh's own lock serializes this against the 01:30 timer — if that's
  # mid-run, the targeted kick logs "previous run active" and exits 0.
  runnowDrain = pkgs.writeShellScript "nightly-builds-runnow-drain" ''
    set -uo pipefail
    SPOOL="${spoolDir}"
    [ -d "$SPOOL" ] || exit 0
    shopt -s nullglob
    for f in "$SPOOL"/*; do
      [ -e "$f" ] || continue
      goal="$(basename "$f")"
      rm -f "$f"
      echo "run-now: executing nightly-builds for goal '$goal'"
      NB_ONLY_GOAL="$goal" ${agentDir}/run.sh || echo "run-now: run.sh exited $? for '$goal'"
    done
  '';
in
{
  # OPTIONS
  options.hwc.automation.nightlyBuilds = {
    enable = lib.mkEnableOption "Nightly gauntlet-card runner (headless Claude Code)";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 01:30:00";
      description = "systemd calendar expression for the nightly launch";
    };

    maxCards = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Maximum number of queued cards to run per night";
    };

    vaultDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if paths.brain.server-replica != null
        then paths.brain.server-replica
        else paths.brain.vault;
      description = "Brain vault root (contains _inbox/nightly_builds/ and runs/)";
    };

    repoDir = lib.mkOption {
      type = lib.types.path;
      default = paths.nixos;
      description = "nixos repo working copy that worktrees are created from";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vaultDir != null;
        message = "hwc.automation.nightlyBuilds: vaultDir is null — brain vault path not defined on this host";
      }
    ];

    # The run-now spool dir must exist (owned by eric, group-writable so the
    # refinery board — also eric — drops request files there).
    systemd.tmpfiles.rules = [
      "d ${spoolDir} 0775 eric users - -"
    ];

    systemd.services.nightly-builds = {
      description = "Nightly Builds — gauntlet card runner (headless Claude Code)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = nbEnv;
      path = nbPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        # Whole-run ceiling for the oneshot (all queued cards, sequential).
        # Per-card execution is bounded inside run.sh by NB_CARD_TIMEOUT (5h);
        # this must comfortably exceed one card + overhead, and give a small
        # queue room to drain. A wedged run still can't outlive this and block
        # the next night's timer (which also skips while the lock is held).
        TimeoutSec = 12 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.nightly-builds = {
      description = "Nightly Builds launch timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Not Persistent: a missed night must not fire mid-day while the
        # repo/vault are being actively worked on.
        Persistent = false;
        RandomizedDelaySec = "60s";
      };
    };

    # ── Run-now: targeted, on-demand execution from the refinery board ─────────
    # The board can't run run.sh itself (hardened/sandboxed). It drops a <goal>
    # file in spoolDir; this path unit fires the drain service, which runs
    # run.sh scoped to that one project. This is the executor behind the board's
    # "▶ Run now" button and IMMEDIATE mode.
    systemd.services.nightly-builds-runnow = {
      description = "Nightly Builds — targeted run-now drain (refinery board trigger)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = nbEnv;
      path = nbPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${runnowDrain}";
        # One targeted card is bounded by run.sh's NB_CARD_TIMEOUT (5h); allow a
        # little headroom. A queued backlog of requests drains sequentially.
        TimeoutSec = 6 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.paths.nightly-builds-runnow = {
      description = "Watch the refinery run-now spool for targeted build requests";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        # Fires whenever the board drops a request file. The drain consumes the
        # files; once empty, the path unit re-arms.
        DirectoryNotEmpty = spoolDir;
        Unit = "nightly-builds-runnow.service";
      };
    };
  };
}
