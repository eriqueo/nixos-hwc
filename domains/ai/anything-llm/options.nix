# domains/ai/anything-llm/options.nix
#
# AnythingLLM - Local AI assistant with filesystem access
# Provides ChatGPT-like interface using local Ollama models

{ lib, config, ... }:

{
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
        example = [ "/etc/nixos" "/mnt/media/documents" ];
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
  };
}
