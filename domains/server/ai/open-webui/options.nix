# domains/server/ai/open-webui/options.nix
#
# Options for Open WebUI - Modern web interface for Ollama
# Charter v6.0 compliant

{ lib, config, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.ai.open-webui = {
    enable = mkEnableOption "Open WebUI - Web interface for Ollama";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Internal port for Open WebUI container";
    };

    ollamaEndpoint = mkOption {
      type = types.str;
      default = "http://127.0.0.1:11434";
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
  };
}
