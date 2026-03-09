# domains/ai/nanoclaw/sys.nix
#
# Container definition for NanoClaw AI agent orchestrator.
# Uses mkInfraContainer helper for socket mount and pre-start script.
#
# Agent capabilities configured via mount-allowlist.json:
# - /home/eric/.nixos: NixOS configuration management
# - /mnt/media: Media file organization
# - /var/log: System log inspection (read-only)

{ lib, config, pkgs, ... }:

let
  # Import infrastructure container helper
  infraHelpers = import ../../lib/mkInfraContainer.nix { inherit lib pkgs; };
  inherit (infraHelpers) mkInfraContainer;

  cfg = config.hwc.ai.nanoclaw;

  # Mount allowlist configuration for agent containers
  # These are HOST paths that NanoClaw agents can mount
  mountAllowlist = pkgs.writeText "mount-allowlist.json" (builtins.toJSON {
    allowedRoots = [
      {
        path = "/home/eric/.nixos";
        allowReadWrite = true;
        description = "NixOS configuration repository for system management";
      }
      {
        path = "/mnt/media";
        allowReadWrite = true;
        description = "Media library for file organization";
      }
      {
        path = "/var/log";
        allowReadWrite = false;
        description = "System logs for diagnostics (read-only)";
      }
      {
        path = "/home/eric/.claude";
        allowReadWrite = true;
        description = "Claude Code settings and session history";
      }
    ];
    # Block files containing sensitive patterns from being accessed
    blockedPatterns = [
      "password"
      "secret"
      "token"
      ".age"
      "id_rsa"
      "id_ed25519"
      ".gnupg"
    ];
    # Non-main agents get read-only access by default
    nonMainReadOnly = true;
  });

  # Sender allowlist for Slack/message access control
  senderAllowlist = pkgs.writeText "sender-allowlist.json" (builtins.toJSON {
    # Allow all senders by default (can be restricted later)
    allowAll = true;
    allowedSenders = [];
    blockedSenders = [];
  });
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Container definition using mkInfraContainer
    (mkInfraContainer {
      name = "nanoclaw";
      image = cfg.image;

      # Network configuration
      networkMode = "media-network";

      # Volume mounts
      # - Full project dir for source, groups/, data/, DB
      # - Podman socket mapped to Docker socket path for agent spawning
      # - Config directory for allowlists (mounted to where config.ts expects)
      volumes = [
        "${cfg.dataDir}:/app"
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
        "${cfg.dataDir}/config:/root/.config/nanoclaw:ro"
      ];

      # Environment from agenix-generated file
      environmentFiles = [ "${cfg.dataDir}/.env" ];

      # HOST_PROJECT_ROOT tells NanoClaw to use host paths when spawning
      # agent containers via the Podman socket (container-in-container pattern)
      environment = {
        HOST_PROJECT_ROOT = cfg.dataDir;
        HOME = "/root";
      };

      # Run startup script that installs docker and starts service
      cmd = [ "bash" "-c" "apt-get update -qq && apt-get install -y -qq docker.io git curl >/dev/null 2>&1; cd /app && exec npm run dev" ];

      # Pre-start script to inject all secrets and configuration
      preStartScript = ''
        mkdir -p ${cfg.dataDir}
        chmod 755 ${cfg.dataDir}

        # Build .env with all required tokens
        # Use ANTHROPIC_API_KEY (not ANTHROPIC_AUTH_TOKEN) for API key mode
        {
          echo "ANTHROPIC_API_KEY=$(cat ${config.age.secrets.nanoclaw-anthropic-key.path})"
          ${lib.optionalString cfg.slack.enable ''
          echo "SLACK_BOT_TOKEN=$(cat ${config.age.secrets.nanoclaw-slack-bot-token.path})"
          echo "SLACK_APP_TOKEN=$(cat ${config.age.secrets.nanoclaw-slack-app-token.path})"
          ''}
        } > ${cfg.dataDir}/.env
        chmod 600 ${cfg.dataDir}/.env

        # Ensure sessions directory exists with proper permissions
        mkdir -p ${cfg.dataDir}/data/sessions
        chmod 755 ${cfg.dataDir}/data/sessions

        # Sync to data/env for NanoClaw's internal config
        mkdir -p ${cfg.dataDir}/data/env
        cp ${cfg.dataDir}/.env ${cfg.dataDir}/data/env/env

        # Deploy mount and sender allowlists
        mkdir -p ${cfg.dataDir}/config
        cp ${mountAllowlist} ${cfg.dataDir}/config/mount-allowlist.json
        cp ${senderAllowlist} ${cfg.dataDir}/config/sender-allowlist.json
        chmod 644 ${cfg.dataDir}/config/*.json
      '';
      preStartDeps = [ "agenix.service" ];

      # Systemd dependencies
      systemdAfter = [ "network-online.target" "init-media-network.service" ];
      systemdWants = [ "network-online.target" ];

      # Resource limits (orchestrator is lightweight; agents spawn externally)
      memory = "1g";
      cpus = "1.0";
    })

    # Tmpfiles for directory creation
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root - -"
        "d ${cfg.dataDir}/config 0755 root root - -"
        "d ${cfg.dataDir}/data 0755 root root - -"
        "d ${cfg.dataDir}/data/env 0755 root root - -"
        "d ${cfg.dataDir}/data/sessions 0755 root root - -"
        "d ${cfg.dataDir}/logs 0755 root root - -"
        "d ${cfg.dataDir}/groups 0755 root root - -"
      ];
    }
  ]);
}
