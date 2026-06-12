# domains/automation/readme-freshness/index.nix
#
# README freshness — weekly Law-12 drift report + optional autonomous fix.
#
# Stage 1 (always): runs workspace/tools/readme-freshness.sh against the repo
# working copy and POSTs a drift summary to hwc-notify (topic "nightly-builds"),
# which routes to the #nightly-builds Discord channel.
#
# Stage 2 (autoFix, default on): when drift exists, a headless Claude agent runs
# the `readme-refresh` skill in a disposable git worktree off origin/main, edits
# READMEs only, and commits. The launcher then HARD-VERIFIES the diff touches
# nothing but README.md files (blast radius is enforced here, not trusted to the
# agent), pushes the branch, opens a PR via gh, and posts the result to Discord.
# The PR review is the human gate — there is no queue-flip for this loop.
#
# NAMESPACE: hwc.automation.readmeFreshness.*
#
# DEPENDENCIES:
#   - hwc.paths.nixos (repo working copy; the linter lives at workspace/tools/)
#   - hwc.notifications.notify (loopback dispatcher on notify.port)
#   - Claude Code CLI + gh, both authenticated for the eric user (autoFix only)

{ config, lib, pkgs, ... }:

let
  cfg       = config.hwc.automation.readmeFreshness;
  paths     = config.hwc.paths;
  notifyCfg = config.hwc.notifications.notify;
  agentDir  = "${paths.nixos}/domains/automation/readme-freshness";
in
{
  # OPTIONS
  options.hwc.automation.readmeFreshness = {
    enable = lib.mkEnableOption "Weekly README freshness report (Law-12 drift → Discord)";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "Mon *-*-* 09:00:00";
      description = "systemd calendar expression for the weekly run (default Monday 09:00)";
    };

    repoDir = lib.mkOption {
      type = lib.types.path;
      default = paths.nixos;
      description = "nixos repo working copy the linter scans";
    };

    notifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString notifyCfg.port}/notify";
      description = "hwc-notify endpoint the report POSTs to (topic nightly-builds)";
    };

    autoFix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When drift is found, run a headless Claude agent (the `readme-refresh`
        skill) in a disposable worktree to fix the stale READMEs, then push a
        branch and open a PR. The launcher hard-verifies the diff is READMEs-only
        before pushing. PR review is the human gate. Set false to report only.
      '';
    };

    branchPrefix = lib.mkOption {
      type = lib.types.str;
      default = "readme/auto-refresh";
      description = "Branch name prefix for autonomous fix runs (date appended).";
    };

    claudeBin = lib.mkOption {
      type = lib.types.str;
      default = "/etc/profiles/per-user/eric/bin/claude";
      description = "Path to the Claude Code CLI used for the autoFix stage.";
    };

    fixTimeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7200;
      description = "Wall-clock cap for the headless fix agent (seconds).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hwc.notifications.notify.enable;
        message = "hwc.automation.readmeFreshness needs hwc.notifications.notify.enable (it POSTs the report there).";
      }
    ];

    systemd.services.readme-freshness = {
      description = "README freshness — Law-12 drift report + autonomous fix";
      after = [ "network-online.target" "hwc-notify.service" ];
      wants = [ "network-online.target" ];
      environment = {
        HOME             = paths.user.home;
        RF_REPO_DIR      = toString cfg.repoDir;
        RF_NOTIFY_URL    = cfg.notifyUrl;
        RF_AUTO_FIX      = if cfg.autoFix then "1" else "0";
        RF_BRANCH_PREFIX = cfg.branchPrefix;
        RF_CLAUDE_BIN    = cfg.claudeBin;
        RF_FIX_TIMEOUT   = toString cfg.fixTimeoutSec;
      };
      path = [
        pkgs.bash pkgs.coreutils pkgs.git pkgs.ripgrep pkgs.curl pkgs.jq
        pkgs.openssh pkgs.gh pkgs.nodejs_22
      ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        # Report is seconds; the fix agent can run up to fixTimeoutSec.
        TimeoutSec = if cfg.autoFix then (cfg.fixTimeoutSec + 900) else 600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.readme-freshness = {
      description = "README freshness weekly timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Persistent: a missed weekly run fires on next boot. Stage 2 output is
        # branch + PR only (gate-7 contained), so a daytime catch-up is safe.
        Persistent = true;
        RandomizedDelaySec = "300s";
      };
    };
  };
}
