# domains/ai/anything-llm/index.nix
#
# AnythingLLM implementation - Local AI assistant with file system access
# Provides ChatGPT-like interface for interacting with local files via Ollama

{ config, lib, pkgs, aiProfile ? null, aiProfileName ? "laptop", ... }:

let
  cfg = config.hwc.ai.anything-llm;

  # Build volume mount list based on configuration
  volumeMounts =
    lib.optionals cfg.workspace.nixosDir [
      "${config.hwc.paths.user.home}/.nixos:/app/collector/nixos:ro"
    ] ++
    lib.optionals cfg.workspace.homeDir [
      "${config.hwc.paths.user.home}:/app/collector/home:ro"
    ] ++
    (map (path: "${path}:/app/collector/${baseNameOf path}:ro") cfg.workspace.customPaths) ++
    [
      "${cfg.dataDir}:/app/server/storage"
    ];

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.anything-llm = {
    enable = lib.mkEnableOption "AnythingLLM local AI assistant with file access";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3002;
      description = "Port for AnythingLLM web interface";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hwc/anything-llm";
      description = "Directory for AnythingLLM data and embeddings";
    };

    workspace = {
      nixosDir = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Mount ~/.nixos directory for AI access";
      };

      homeDir = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Mount entire home directory (broader access)";
      };

      customPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional custom paths to mount (read-only)";
        example = [ config.hwc.paths.nixos "${config.hwc.paths.user.work}/documents" ];
      };
    };

    ollama = {
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:11434";
        description = "Ollama API endpoint (uses host networking for direct access)";
      };

      defaultModel = lib.mkOption {
        type = lib.types.str;
        default = "llama3.2:3b";
        description = "Default Ollama model to use";
      };
    };

    embeddings = {
      provider = lib.mkOption {
        type = lib.types.enum [ "ollama" "native" ];
        default = "ollama";
        description = "Embedding provider (ollama uses nomic-embed-text)";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "nomic-embed-text:latest";
        description = "Embedding model name";
      };
    };

    resourceLimits = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable resource limits to prevent runaway CPU/memory usage";
      };

      maxCpuPercent = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Maximum CPU usage percentage (100 = 1 core, 200 = 2 cores, etc.)
          null = unlimited (server default), set to 100-200 for laptop
        '';
      };

      maxMemoryMB = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Maximum memory in MB
          null = unlimited (server default), set to 2048-4096 for laptop
        '';
      };
    };

    autoRestart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Automatically restart service on failure
        Recommended: false for laptop (manual control), true for server
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Apply profile-based defaults if profile available
    (lib.mkIf (aiProfile != null) {
      hwc.ai.anything-llm.resourceLimits = {
        enable = lib.mkDefault true;
        maxCpuPercent = lib.mkDefault (aiProfile.ollama.maxCpuPercent / 2); # Half of Ollama's limit
        maxMemoryMB = lib.mkDefault (aiProfile.ollama.maxMemoryMB / 2); # Half of Ollama's limit
      };

      # Don't auto-restart if using idle shutdown (let it stay stopped)
      hwc.ai.anything-llm.autoRestart = lib.mkDefault false;
    })

    # Service implementation
    {
    # Create data directory with proper permissions for container
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0777 root root -"
      "d ${cfg.dataDir}/vector-cache 0777 root root -"
    ];

    # AnythingLLM container service
    virtualisation.podman.enable = true;

    systemd.services.podman-anything-llm = {
      description = "AnythingLLM - Local AI assistant with file access";
      after = [ "network-online.target" "podman-ollama.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ ]; # Don't auto-start on boot

      path = [ pkgs.podman ];

      serviceConfig = lib.mkMerge [
        {
          Type = "forking";
          Restart = if cfg.autoRestart then "always" else "no";
          RestartSec = "10s";
          TimeoutStartSec = "120s";
        }
        # Apply resource limits if enabled
        (lib.mkIf cfg.resourceLimits.enable (lib.mkMerge [
          (lib.mkIf (cfg.resourceLimits.maxCpuPercent != null) {
            CPUQuota = "${toString cfg.resourceLimits.maxCpuPercent}%";
          })
          (lib.mkIf (cfg.resourceLimits.maxMemoryMB != null) {
            MemoryMax = "${toString (cfg.resourceLimits.maxMemoryMB * 1024 * 1024)}";
            MemoryHigh = "${toString (cfg.resourceLimits.maxMemoryMB * 1024 * 1024 * 90 / 100)}";
          })
        ]))
      ];

      preStart = ''
        ${pkgs.podman}/bin/podman pull mintplexlabs/anythingllm:latest

        # Ensure storage directory exists and is writable
        mkdir -p ${cfg.dataDir}
        chmod -R 777 ${cfg.dataDir}
      '';

      script = ''
        ${pkgs.podman}/bin/podman run \
          --rm \
          --name anything-llm \
          --detach \
          --network host \
          ${lib.concatMapStringsSep " " (v: "--volume ${v}") volumeMounts} \
          --env "LLM_PROVIDER=ollama" \
          --env "OLLAMA_BASE_PATH=http://127.0.0.1:11434" \
          --env "OLLAMA_MODEL_PREF=${cfg.ollama.defaultModel}" \
          --env "EMBEDDING_ENGINE=${cfg.embeddings.provider}" \
          --env "EMBEDDING_BASE_PATH=http://127.0.0.1:11434" \
          --env "EMBEDDING_MODEL_PREF=${cfg.embeddings.model}" \
          --env "STORAGE_DIR=/app/server/storage" \
          --env "DISABLE_TELEMETRY=true" \
          --env "SERVER_PORT=${toString cfg.port}" \
          mintplexlabs/anythingllm:latest
      '';

      preStop = ''
        ${pkgs.podman}/bin/podman stop -t 10 anything-llm || true
      '';

      postStop = ''
        ${pkgs.podman}/bin/podman rm -f anything-llm || true
      '';
    };

    # Firewall configuration (localhost only by default)
    # Access via: http://localhost:${cfg.port}

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.ai.ollama.enable;
        message = "AnythingLLM requires Ollama to be enabled (hwc.ai.ollama.enable = true)";
      }
      {
        assertion = cfg.workspace.nixosDir || cfg.workspace.homeDir || (cfg.workspace.customPaths != []);
        message = "AnythingLLM requires at least one workspace path to be enabled";
      }
      {
        assertion = !cfg.resourceLimits.enable ||
          (cfg.resourceLimits.maxCpuPercent == null || cfg.resourceLimits.maxCpuPercent > 0);
        message = "hwc.ai.anything-llm.resourceLimits.maxCpuPercent must be positive if set";
      }
      {
        assertion = !cfg.resourceLimits.enable ||
          (cfg.resourceLimits.maxMemoryMB == null || cfg.resourceLimits.maxMemoryMB > 0);
        message = "hwc.ai.anything-llm.resourceLimits.maxMemoryMB must be positive if set";
      }
    ];
    } # End service implementation block
  ]); # End mkMerge + mkIf cfg.enable
}
