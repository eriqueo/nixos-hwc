# domains/automation/inbox-janitor/index.nix
#
# Inbox Janitor — drains ~/000_inbox/downloads on a timer, routing each loose
# file to its domain (datax stays resident; business/tech/personal drain to the
# home PARA dirs) per the declarative rule table ~/000_inbox/_inbox-routing.yaml.
#
# WHY SERVER-ONLY: ~/000_inbox is a multi-writer Syncthing tree (laptop + server
# + LLM posts). If a mover ran on both hosts they would race the same path and
# Syncthing would spit .sync-conflict-* copies — the same failure that forced the
# brain vault onto a single-writer hub. So exactly one host owns the routing pass.
# The guard is enforced twice: this module is only enabled in machines/server,
# AND janitor.py refuses to --apply unless hostname == meta.owner_host in the YAML.
#
# NAMESPACE: hwc.automation.inboxJanitor.*
#
# DEPENDENCIES:
#   - ~/000_inbox/_inbox-routing.yaml (the rule table; live-editable, not nix-managed)
#   - the home PARA dirs the rules drain into (~/100_hwc, ~/200_personal, ~/300_tech)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.inboxJanitor;

  pyEnv = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  janitorBin = pkgs.writeShellApplication {
    name = "inbox-janitor";
    runtimeInputs = [ pyEnv ];
    text = ''exec ${pyEnv}/bin/python3 ${./janitor.py} "$@"'';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.automation.inboxJanitor = {
    enable = lib.mkEnableOption "Timer that drains ~/000_inbox/downloads per the routing rule table";

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User that owns the inbox tree and runs the janitor";
    };

    rulesFile = lib.mkOption {
      type = lib.types.path;
      default = "/home/${cfg.user}/000_inbox/_inbox-routing.yaml";
      defaultText = lib.literalExpression ''"/home/''${cfg.user}/000_inbox/_inbox-routing.yaml"'';
      description = "Declarative routing + naming rule table consumed each run (live-editable)";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/30";
      description = "systemd OnCalendar expression for the drain cadence (default every 30 min)";
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true (the safe default), the janitor only LOGS the moves it would make
        to the journal and touches nothing. Flip to false to actually move files.
        Recommended rollout: deploy with dryRun=true, watch `journalctl -u inbox-janitor`
        for a few cycles, then set false.'';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.inbox-janitor = {
      description = "Drain ~/000_inbox/downloads per the routing rule table";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = "users";
        ExecStart =
          "${lib.getExe janitorBin} --config ${cfg.rulesFile}"
          + lib.optionalString (!cfg.dryRun) " --apply";
        Environment = "HOME=/home/${cfg.user}";
      };
    };

    systemd.timers.inbox-janitor = {
      description = "Periodic inbox-downloads drain";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
