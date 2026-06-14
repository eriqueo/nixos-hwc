# domains/automation/sr-gauntlet/index.nix
#
# SR Gauntlet — daily unattended investigation of DataX support requests.
#
# Fetches open SRs (SR2 board phases new+engaged) from the DataX Firestore,
# runs one headless read-only Claude Code investigation per SR against
# origin/main worktrees of the datax + jt-mcp repos (with the customer's
# Firestore context pack and OpenSearch log access), writes a reviewable
# REPORT.md per SR, and posts each report to Eric's Discord webhook.
#
# Containment model (mirrors nightly-builds gate 7): the pipeline never
# changes code and never replies to customers — reports + a thread-hash
# ledger are its only outputs. The human applies fixes / sends replies.
#
# The pipeline itself (run.sh, fetch-srs.mjs, aggregate-context.mjs,
# opensearch-query.mjs, send-report.sh) lives in its own repo at
# ~/700_datax/sr_gauntlet — this module only provides the schedule.
# Credentials are late-bound at runtime from ~/600_apps/sr_analyzer/.env
# (Firestore) and ~/700_datax/datax/.env.local (Firestore admin +
# OpenSearch); nothing secret passes through the Nix store.
#
# NAMESPACE: hwc.automation.srGauntlet.*
#
# DEPENDENCIES:
#   - ~/700_datax/sr_gauntlet checkout (the pipeline)
#   - ~/700_datax/datax + ~/700_datax/jt-mcp git checkouts (worktree sources)
#   - Claude Code CLI authenticated for the eric user
#   - hwc-notify on 127.0.0.1:11600 (run summaries; best-effort)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.srGauntlet;
  paths = config.hwc.paths;
in
{
  # OPTIONS
  options.hwc.automation.srGauntlet = {
    enable = lib.mkEnableOption "Daily SR investigation pipeline (headless Claude Code)";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 06:30:00";
      description = "systemd calendar expression for the daily run (7 days a week)";
    };

    maxSrs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Maximum SRs investigated per run";
    };

    gauntletDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.user.home}/700_datax/sr_gauntlet";
      description = "sr_gauntlet pipeline checkout (run.sh lives here)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.sr-gauntlet = {
      description = "SR Gauntlet — daily DataX support-request investigations (headless Claude Code)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        HOME = paths.user.home;
        SRG_MAX_SRS = toString cfg.maxSrs;
      };
      path = [
        pkgs.bash pkgs.coreutils pkgs.git pkgs.openssh
        pkgs.nodejs_22 pkgs.python3 pkgs.jq pkgs.ripgrep
        pkgs.curl  # Discord webhook delivery + hwc-notify
      ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = cfg.gauntletDir;
        ExecStart = "${cfg.gauntletDir}/run.sh";
        # maxSrs * 30 min agent budget + fetch/context overhead
        TimeoutSec = 3 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.sr-gauntlet = {
      description = "SR Gauntlet daily launch timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Persistent: a missed morning (host down) fires on next boot —
        # unlike nightly-builds, runs are read-only outside their own
        # state dir, so a mid-day catch-up is harmless.
        Persistent = true;
        RandomizedDelaySec = "60s";
      };
    };
  };
}
