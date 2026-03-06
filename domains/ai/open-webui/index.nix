# domains/ai/open-webui/index.nix
#
# Open WebUI - Modern web interface for Ollama
# Provides a beautiful, feature-rich UI for interacting with local LLMs

{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.ai.open-webui;

  # Package custom tools
  customTools = pkgs.stdenv.mkDerivation {
    name = "open-webui-custom-tools";
    src = ./tools;
    installPhase = ''
      mkdir -p $out
      cp -r * $out/
    '';
  };

  # Build environment variables
  baseEnv = {
    # Access Ollama via host gateway (container uses bridge networking, not host mode)
    OLLAMA_BASE_URL = cfg.ollamaEndpoint;
    WEBUI_AUTH = if cfg.enableAuth then "true" else "false";
    DEFAULT_MODELS = cfg.defaultModel;

    # RAG Configuration
    ENABLE_RAG_WEB_SEARCH = "false";  # Keep it local
    CHUNK_SIZE = toString cfg.ragChunkSize;
    CHUNK_OVERLAP = toString cfg.ragOverlap;

    # UI Customization
    WEBUI_NAME = "HWC AI Assistant";

    # Security
    ENABLE_SIGNUP = "true";  # Allow user registration
    ENABLE_LOGIN_FORM = toString cfg.enableAuth;

    # Performance
    NUM_WORKERS = "2";
  };

  # Merge with user-provided extra environment variables
  containerEnv = baseEnv // cfg.extraEnv;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.open-webui = {
    enable = lib.mkEnableOption "Open WebUI - Web interface for Ollama";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Host port for Open WebUI (avoids conflict with Grafana on 3000)";
    };

    ollamaEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://ollama:11434";
      description = "Ollama API endpoint";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/open-webui";
      description = "Data directory for Open WebUI (database, uploads, etc.)";
    };

    enableAuth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable user authentication (recommended for multi-user)";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "phi3.5:3.8b";
      description = "Default model for new conversations";
    };

    enableRAG = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable RAG (Retrieval Augmented Generation) features";
    };

    ragChunkSize = lib.mkOption {
      type = lib.types.int;
      default = 1500;
      description = "Chunk size for RAG document processing";
    };

    ragOverlap = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Overlap size for RAG chunks";
    };

    imageTag = lib.mkOption {
      type = lib.types.str;
      default = "latest";
      description = "Docker image tag for Open WebUI";
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables for Open WebUI container";
      example = {
        WEBUI_NAME = "HWC AI Assistant";
      };
    };

    healthCheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable health check for Open WebUI container";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "Health check interval";
      };

      timeout = lib.mkOption {
        type = lib.types.str;
        default = "10s";
        description = "Health check timeout";
      };

      retries = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Health check retries before marking unhealthy";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Podman container configuration
    virtualisation.oci-containers.containers.open-webui = {
      image = "ghcr.io/open-webui/open-webui:${cfg.imageTag}";
      
      autoStart = true;

      ports = [
        "${toString cfg.port}:8080"  # Open WebUI default internal port is 8080
      ];

      volumes = [
        "${cfg.dataDir}:/app/backend/data"
        "${customTools}:/app/backend/data/functions:ro"  # Mount tools as read-only
      ];

      environment = containerEnv;

      # Health check and extra options
      extraOptions = [] ++ lib.optionals cfg.healthCheck.enable [
        "--health-cmd=wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1"
        "--health-interval=${cfg.healthCheck.interval}"
        "--health-timeout=${cfg.healthCheck.timeout}"
        "--health-retries=${toString cfg.healthCheck.retries}"
      ];
    };

    # Ensure Podman is enabled
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # Ensure OCI containers backend is set
    virtualisation.oci-containers.backend = "podman";

    # Systemd service customization
    systemd.services."oci-containers-open-webui" = {
      after = [ "oci-containers-ollama.service" ];
      wants = [ "oci-containers-ollama.service" ];
      serviceConfig = {
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # Create data directory and tools directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/functions 0750 root root -"
    ];

    # Copy custom tools to data directory for Open WebUI to discover
    system.activationScripts.openwebuiTools = lib.mkIf cfg.enable ''
      mkdir -p ${cfg.dataDir}/functions
      ${pkgs.rsync}/bin/rsync -av --delete ${customTools}/ ${cfg.dataDir}/functions/
      chown -R root:root ${cfg.dataDir}/functions
      chmod -R 0750 ${cfg.dataDir}/functions
    '';

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.enable -> (cfg.port > 0 && cfg.port < 65536);
        message = "Open WebUI port must be between 1 and 65535";
      }
      {
        assertion = cfg.enable -> (cfg.ragChunkSize > 0);
        message = "RAG chunk size must be positive";
      }
      {
        assertion = cfg.enable -> (cfg.ragOverlap >= 0 && cfg.ragOverlap < cfg.ragChunkSize);
        message = "RAG overlap must be non-negative and less than chunk size";
      }
    ];
  };
}
