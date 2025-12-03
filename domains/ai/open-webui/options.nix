# domains/server/ai/open-webui/options.nix
#
# Options for Open WebUI - Modern web interface for Ollama
# Charter v6.0 compliant

{ lib, config, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.ai.open-webui = {
    enable = mkEnableOption "Open WebUI - Web interface for Ollama";

    port = mkOption {
      type = types.port;
      default = 3001;
      description = "Host port for Open WebUI (avoids conflict with Grafana on 3000)";
    };

    ollamaEndpoint = mkOption {
      type = types.str;
      default = "http://ollama:11434";
      description = "Ollama API endpoint";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/open-webui";
      description = "Data directory for Open WebUI (database, uploads, etc.)";
    };

    enableAuth = mkOption {
      type = types.bool;
      default = true;
      description = "Enable user authentication (recommended for multi-user)";
    };

    defaultModel = mkOption {
      type = types.str;
      default = "phi3.5:3.8b";
      description = "Default model for new conversations";
    };

    enableRAG = mkOption {
      type = types.bool;
      default = true;
      description = "Enable RAG (Retrieval Augmented Generation) features";
    };

    ragChunkSize = mkOption {
      type = types.int;
      default = 1500;
      description = "Chunk size for RAG document processing";
    };

    ragOverlap = mkOption {
      type = types.int;
      default = 100;
      description = "Overlap size for RAG chunks";
    };

    imageTag = mkOption {
      type = types.str;
      default = "latest";
      description = "Docker image tag for Open WebUI";
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for Open WebUI container";
      example = {
        WEBUI_NAME = "HWC AI Assistant";
      };
    };

    healthCheck = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable health check for Open WebUI container";
      };

      interval = mkOption {
        type = types.str;
        default = "30s";
        description = "Health check interval";
      };

      timeout = mkOption {
        type = types.str;
        default = "10s";
        description = "Health check timeout";
      };

      retries = mkOption {
        type = types.int;
        default = 3;
        description = "Health check retries before marking unhealthy";
      };
    };
  };
}
