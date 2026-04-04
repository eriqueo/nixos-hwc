# domains/business/morning-briefing/index.nix
#
# Morning Briefing agent — daily systemd service that runs Claude Code CLI
# to gather data from MCP servers and write a JSON briefing file.
# An n8n workflow reads the JSON at 6:05am and posts a Slack summary.
# A static HTML dashboard also reads the JSON via Caddy.
#
# NAMESPACE: hwc.business.morningBriefing.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.morningBriefing;
  agentDir = "/home/eric/agents/morning-briefing";
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

      environment = {
        HOME = "/home/eric";
      };

      path = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.nodejs_22 ];

      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";

        # Claude Code needs time to call multiple MCP servers
        TimeoutSec = 120;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";

        # Minimal sandboxing — Claude Code spawns subprocesses and needs
        # network access for remote MCP endpoints (DataX, Google Calendar)
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;

        # Writable paths: agent output dir, logs, claude config, /tmp
        ReadWritePaths = [
          "${agentDir}/output"
          "${agentDir}/logs"
          "/home/eric/.claude"
          "/tmp"
        ];
      };
    };

    systemd.timers.morning-briefing = {
      description = "Daily morning briefing timer (6am MT)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;   # Run on boot if missed
        RandomizedDelaySec = "30s";
      };
    };
  };
}
