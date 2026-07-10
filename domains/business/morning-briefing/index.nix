# domains/business/morning-briefing/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.business.morningBriefing;
  paths = config.hwc.paths;
  agentDir = "${paths.nixos}/domains/business/morning-briefing";
in
{
  options.hwc.business.morningBriefing = {
    enable = lib.mkEnableOption "Morning briefing agent (Claude Code CLI + MCP)";
    onCalendar = lib.mkOption {
      type = with lib.types; either str (listOf str);
      default = "*-*-* 06:00:00";
      description = ''
        systemd calendar expression(s). A list adds midday/evening dashboard
        refreshes; run.sh only emails on the pre-9am run, so extra firings
        never re-send the briefing email.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.morning-briefing = {
      description = "Morning Briefing — Claude Code CLI data gathering agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment.HOME = paths.user.home;
      # git: config-drift tile (HEAD/unpushed/dirty). coredumpctl comes from
      # systemd which is always on the base PATH via /run/current-system.
      # pass+gnupg: msmtp's passwordeval for the Step-5 email (proton bridge).
      # curl: website tile (umami stats via loopback API). postgresql client
      # comes from /run/current-system/sw/bin (absolute path in run.sh).
      path = [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.gawk pkgs.gnugrep pkgs.jq pkgs.nodejs_22 pkgs.notmuch pkgs.git pkgs.msmtp pkgs.pass pkgs.gnupg pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        # Step 1b (gateway gather, ≤120s) + Step 2 (claude triage) both fit
        TimeoutSec = 420;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ReadWritePaths = [
          "${agentDir}/output"
          "${agentDir}/logs"
          "${agentDir}/dashboard"
          paths.user.claude
          "/tmp"
        ];
      };
    };

    systemd.timers.morning-briefing = {
      description = "Daily morning briefing timer (6am MT)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
