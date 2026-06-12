# domains/automation/readme-freshness/index.nix
#
# README freshness — weekly Law-12 drift report.
#
# Runs workspace/tools/readme-freshness.sh against the repo working copy on a
# weekly timer and POSTs a summary to hwc-notify (topic "nightly-builds"), which
# routes to the #nightly-builds Discord channel. Report-only: it never edits a
# README, only surfaces which domain dirs changed after their README's last
# commit (Charter Law 12 / CLAUDE.md "On Commit").
#
# NAMESPACE: hwc.automation.readmeFreshness.*
#
# DEPENDENCIES:
#   - hwc.paths.nixos (repo working copy; the linter lives at workspace/tools/)
#   - hwc.notifications.notify (loopback dispatcher on notify.port)

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
      description = "systemd calendar expression for the weekly report (default Monday 09:00)";
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
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hwc.notifications.notify.enable;
        message = "hwc.automation.readmeFreshness needs hwc.notifications.notify.enable (it POSTs the report there).";
      }
    ];

    systemd.services.readme-freshness = {
      description = "README freshness report (Law-12 drift detector → Discord)";
      after = [ "network-online.target" "hwc-notify.service" ];
      wants = [ "network-online.target" ];
      environment = {
        HOME          = paths.user.home;
        RF_REPO_DIR   = toString cfg.repoDir;
        RF_NOTIFY_URL = cfg.notifyUrl;
      };
      path = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.ripgrep pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        TimeoutSec = 600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.readme-freshness = {
      description = "README freshness weekly report timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Persistent: a missed weekly report should fire on next boot — it's
        # read-only, so unlike nightly-builds there's no mid-day-mutation risk.
        Persistent = true;
        RandomizedDelaySec = "300s";
      };
    };
  };
}
