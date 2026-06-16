# domains/automation/n8n/parts/workflow-export.nix
#
# Nightly snapshot of the live n8n workflow set into a local git repo.
#
# Each run: GETs every workflow via the n8n REST API (cursor-paginated,
# read-only), writes one pretty-printed JSON file per workflow to a local
# directory, prunes files for deleted workflows, then commits the change if
# anything moved. The directory is a standalone git repo (no remote) — off-box
# backup is a later step toward the n8n-workflow-versioning goal.
#
# NAMESPACE: hwc.automation.n8n.workflowExport.*
#
# Inputs (env, for both the systemd unit and ad-hoc dry runs):
#   N8N_EXPORT_DIR    target dir (default = exportDir option)
#   N8N_API_URL       base URL (default http://localhost:5678)
#   N8N_API_KEY_FILE  file containing the X-N8N-API-KEY (default
#                     /run/agenix/n8n-api-key)

{ config, lib, pkgs, ... }:

let
  cfg   = config.hwc.automation.n8n.workflowExport;
  paths = config.hwc.paths;

  runScript = pkgs.writeShellApplication {
    name = "n8n-workflow-export";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.git pkgs.gnused ];
    text = builtins.readFile ./workflow-export.sh;
  };
in
{
  options.hwc.automation.n8n.workflowExport = {
    enable = lib.mkEnableOption "Nightly snapshot of n8n workflows into a local git repo";

    exportDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/n8n/workflow-export";
      description = ''
        Local directory the snapshot script writes to. Treated as a standalone
        git repo (the script runs `git init` on first use). No remote is
        configured here; off-box backup is a later step.
      '';
    };

    apiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:5678";
      description = "Base URL of the n8n REST API (read-only GET only).";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/n8n-api-key";
      description = "Path to a file containing the n8n API key (X-N8N-API-KEY).";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 02:30:00";
      description = ''
        systemd calendar expression for the daily snapshot (default 02:30,
        after the 01:30 nightly-builds window).
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User the snapshot service runs as (needs read on apiKeyFile + write on exportDir).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.apiUrl != "";
        message = "hwc.automation.n8n.workflowExport.apiUrl must be set.";
      }
      {
        assertion = toString cfg.exportDir != "";
        message = "hwc.automation.n8n.workflowExport.exportDir must be set.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${toString cfg.exportDir} 0750 ${cfg.user} root -"
    ];

    systemd.services.n8n-workflow-export = {
      description = "n8n workflow snapshot — GET all workflows → JSON files → git commit";
      after = [ "network-online.target" "podman-n8n.service" ];
      wants = [ "network-online.target" ];
      environment = {
        N8N_EXPORT_DIR   = toString cfg.exportDir;
        N8N_API_URL      = cfg.apiUrl;
        N8N_API_KEY_FILE = toString cfg.apiKeyFile;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        ExecStart = lib.getExe runScript;
        TimeoutSec = 600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.n8n-workflow-export = {
      description = "n8n workflow snapshot daily timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "300s";
      };
    };
  };
}
