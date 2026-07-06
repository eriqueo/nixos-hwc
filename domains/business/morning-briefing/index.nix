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
      type = lib.types.str;
      default = "*-*-* 06:00:00";
      description = "systemd calendar expression for when to run the briefing";
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
      path = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.nodejs_22 pkgs.notmuch pkgs.git pkgs.msmtp pkgs.pass pkgs.gnupg ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        TimeoutSec = 300;
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
