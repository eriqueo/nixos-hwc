# domains/automation/mail-janitor/index.nix
#
# mail-janitor — scheduled, age-aware anti-buildup sweep for the Gmail accounts.
#
# Three tiers (see janitor.py): PRESERVE (people/history/finance — never touched),
# TXN (receipts/orders — trashed once older than txnMaxAgeDays), NOISE
# (promo/streaming/social/bot-noise — trashed at any age). The Family-Friends
# label and Sent are ALWAYS excluded. Trash is 30-day recoverable; nothing is
# hard-deleted. Posts a per-run summary to hwc-notify.
#
# ROLLOUT: dryRun defaults TRUE — it reports what it WOULD trash (to Discord)
# without touching anything. Flip hwc.automation.mailJanitor.dryRun = false once
# the dry-run reports look right.
#
# NAMESPACE: hwc.automation.mailJanitor.*
# DEPENDENCIES: agenix gmail-{personal,business}-password; hwc.notifications.notify.

{ config, lib, pkgs, ... }:

let
  cfg       = config.hwc.automation.mailJanitor;
  notifyCfg = config.hwc.notifications.notify;
  paths     = config.hwc.paths;
  agentDir  = "${paths.nixos}/domains/automation/mail-janitor";
  # One source of truth: the same trashSenders that drive the local notmuch rules
  # also tell the janitor which marketing/lead-gen senders are junk.
  mailRules = config.home-manager.users.eric.hwc.mail.notmuch.rules or {};
  denyDomains = mailRules.trashSenders or [];
in
{
  options.hwc.automation.mailJanitor = {
    enable = lib.mkEnableOption "Scheduled age-aware Gmail anti-buildup sweep";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "Sun *-*-* 04:00:00";
      description = "systemd calendar expression (default weekly, Sunday 04:00).";
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Report-only (no trashing). Set false to let it actually trash.";
    };

    txnMaxAgeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 365;
      description = "Transactional mail (receipts/orders) is trashed once older than this. NOISE is trashed at any age; PRESERVE never.";
    };

    triageMaxAgeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Newsletters sit in the Newsletters-Triage label this many days (from when they entered triage) before being trashed — unless starred or keep/Family-Friends-labeled.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${paths.user.home}/.local/state/mail-janitor";
      description = "Where the per-account triage clock state (message-id → first-seen date) is kept.";
    };

    notifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString notifyCfg.port}/notify";
      description = "hwc-notify endpoint the run summary POSTs to.";
    };

    accounts = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.str);
      default = [
        { name = "personal"; email = "eriqueokeefe@gmail.com";   secret = "/run/agenix/gmail-personal-password"; }
        { name = "business"; email = "heartwoodcraftmt@gmail.com"; secret = "/run/agenix/gmail-business-password"; }
      ];
      description = "Gmail accounts to sweep; each {name,email,secret(app-password file)}.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = notifyCfg.enable;
      message = "hwc.automation.mailJanitor expects hwc.notifications.notify.enable (it POSTs the run summary).";
    }];

    systemd.services.mail-janitor = {
      description = "mail-janitor — age-aware Gmail anti-buildup sweep";
      after = [ "network-online.target" "hwc-notify.service" ];
      wants = [ "network-online.target" ];
      environment = {
        MJ_DRY_RUN             = if cfg.dryRun then "1" else "0";
        MJ_TXN_MAX_AGE_DAYS    = toString cfg.txnMaxAgeDays;
        MJ_TRIAGE_MAX_AGE_DAYS = toString cfg.triageMaxAgeDays;
        MJ_STATE_DIR           = cfg.stateDir;
        MJ_NOTIFY_URL          = cfg.notifyUrl;
        MJ_ACCOUNTS            = builtins.toJSON cfg.accounts;
        MJ_DENY                = builtins.toJSON denyDomains;
      };
      path = [ pkgs.python3 ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        SupplementaryGroups = [ "secrets" ];   # read /run/agenix/gmail-*-password
        WorkingDirectory = agentDir;
        ExecStart = "${pkgs.python3}/bin/python3 ${agentDir}/janitor.py";
        TimeoutSec = 1800;
        NoNewPrivileges = true;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers.mail-janitor = {
      description = "mail-janitor weekly timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "600s";
      };
    };
  };
}
