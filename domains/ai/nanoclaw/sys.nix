# domains/ai/nanoclaw/sys.nix
#
# Container definition for NanoClaw AI agent orchestrator.
# Uses mkInfraContainer helper for socket mount and pre-start script.
#
# Agent capabilities configured via mount-allowlist.json:
# - paths.nixos: NixOS configuration management
# - paths.media.root: Media file organization
# - /var/log: System log inspection (read-only)

{ lib, config, pkgs, ... }:

let
  # Import infrastructure container helper
  infraHelpers = import ../../lib/mkInfraContainer.nix { inherit lib pkgs; };
  inherit (infraHelpers) mkInfraContainer;

  cfg = config.hwc.ai.nanoclaw;
  paths = config.hwc.paths;

  # Mount allowlist configuration for agent containers
  # These are HOST paths that NanoClaw agents can mount
  # Note: /var/log excluded due to container validation conflict
  mountAllowlist = pkgs.writeText "mount-allowlist.json" (builtins.toJSON {
    allowedRoots = [
      {
        path = toString paths.nixos;
        allowReadWrite = true;
        description = "NixOS configuration repository for system management";
      }
      {
        path = toString paths.media.root;
        allowReadWrite = true;
        description = "Media library for file organization";
      }
      {
        path = toString paths.user.claude;
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
    # Allow non-main agents to have write access (server-admin needs to edit files)
    nonMainReadOnly = false;
  });

  # Sender allowlist for Slack/message access control
  # Format: default entry with allow/mode, optional per-chat overrides
  senderAllowlist = pkgs.writeText "sender-allowlist.json" (builtins.toJSON {
    default = { allow = "*"; mode = "trigger"; };
    chats = {};
    logDenied = true;
  });

  # Script to apply declarative group container configs
  # Separated to avoid Nix string escaping issues with SQL
  # Note: /var/log excluded because it conflicts with apt-get in NanoClaw container
  applyGroupConfig = pkgs.writeShellScriptBin "apply-group-config" ''
    DB_PATH="$1"
    CONTAINER_CONFIG='{"additionalMounts":[{"hostPath":"${paths.nixos}","containerPath":"nixos","readonly":false},{"hostPath":"${toString paths.media.root}","containerPath":"media","readonly":false},{"hostPath":"${toString paths.user.claude}","containerPath":"claude","readonly":false}]}'

    # Update groups that have no container_config (NULL or empty string)
    ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "UPDATE registered_groups SET container_config = '$CONTAINER_CONFIG' WHERE container_config IS NULL OR LENGTH(container_config) = 0;"

    # Always update main group
    ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "UPDATE registered_groups SET container_config = '$CONTAINER_CONFIG' WHERE is_main = 1;"
  '';
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Container definition using mkInfraContainer
    (mkInfraContainer {
      name = "nanoclaw";
      image = cfg.image;

      # Network configuration - use host network for direct internet access
      # This shares the host's network stack, avoiding podman bridge NAT issues
      networkMode = "host";

      # Volume mounts
      # - Full project dir for source, groups/, data/, DB
      # - Podman socket mapped to Docker socket path for agent spawning
      # - Config directory for allowlists (mounted to where config.ts expects)
      # - Host paths that agents can mount (so NanoClaw can validate they exist)
      volumes = [
        "${cfg.dataDir}:/app"
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
        "${cfg.dataDir}/config:/root/.config/nanoclaw:ro"
        # Mount host paths for validation (NanoClaw checks these exist before spawning agents)
        "${paths.nixos}:${paths.nixos}:ro"
        "${toString paths.media.root}:${toString paths.media.root}:ro"
        "${toString paths.user.claude}:${toString paths.user.claude}:ro"
        # /var/log mounted to alternate path to avoid blocking apt-get inside container
        "/var/log:/hostfs/logs:ro"
      ];

      # Environment from agenix-generated file
      environmentFiles = [ "${cfg.dataDir}/.env" ];

      # HOST_PROJECT_ROOT tells NanoClaw to use host paths when spawning
      # agent containers via the Podman socket (container-in-container pattern)
      environment = {
        HOST_PROJECT_ROOT = cfg.dataDir;
        HOME = "/root";
        # Credential proxy port
        CREDENTIAL_PROXY_PORT = "3002";
        # Trigger word must match the Slack bot's display name
        ASSISTANT_NAME = "NanoClaw";
      };

      # Run startup script that installs docker CLI and starts service
      # Force IPv4 (-o Acquire::ForceIPv4=true) since media-network has ipv6_enabled=false
      cmd = [ "bash" "-c" "apt-get -o Acquire::ForceIPv4=true update && apt-get -o Acquire::ForceIPv4=true install -y docker.io git curl && cd /app && exec npm run dev" ];

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

        # Deploy mount and sender allowlists to container config location
        mkdir -p ${cfg.dataDir}/config
        cp ${mountAllowlist} ${cfg.dataDir}/config/mount-allowlist.json
        cp ${senderAllowlist} ${cfg.dataDir}/config/sender-allowlist.json
        chmod 644 ${cfg.dataDir}/config/*.json

        # Also deploy to host location for spawned agent containers
        # (agents look for ~/.config/nanoclaw/ which resolves to host path)
        mkdir -p ${toString paths.user.config}/nanoclaw
        cp ${mountAllowlist} ${toString paths.user.config}/nanoclaw/mount-allowlist.json
        cp ${senderAllowlist} ${toString paths.user.config}/nanoclaw/sender-allowlist.json
        chown -R eric:users ${toString paths.user.config}/nanoclaw
        chmod 644 ${toString paths.user.config}/nanoclaw/*.json

        # Fix directory permissions - agent containers run as node (uid=1000)
        mkdir -p ${cfg.dataDir}/data/ipc
        mkdir -p ${cfg.dataDir}/data/sessions
        chown -R 1000:1000 ${cfg.dataDir}/data/ipc
        chown -R 1000:1000 ${cfg.dataDir}/data/sessions
        chmod -R 755 ${cfg.dataDir}/data/ipc
        chmod -R 755 ${cfg.dataDir}/data/sessions

        # Apply declarative group container configs to database
        # Database is at store/messages.db (NanoClaw creates it on first run)
        if [ -f "${cfg.dataDir}/store/messages.db" ]; then
          ${applyGroupConfig}/bin/apply-group-config "${cfg.dataDir}/store/messages.db"
          echo "Applied declarative group container configs"
        fi
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
        "d ${cfg.dataDir}/data/sessions 0755 1000 1000 - -"
        "d ${cfg.dataDir}/data/ipc 0755 1000 1000 - -"
        "d ${cfg.dataDir}/logs 0755 root root - -"
        "d ${cfg.dataDir}/groups 0755 root root - -"
        "d ${toString paths.user.config}/nanoclaw 0755 eric users - -"
      ];
    }
  ]);
}
