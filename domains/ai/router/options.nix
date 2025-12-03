{ lib, ... }:

{
  options.hwc.ai.router = {
    enable = lib.mkEnableOption "AI model router for local/cloud fallback";

    port = lib.mkOption {
      type = lib.types.port;
      default = 11435;
      description = "Router port (Ollama uses 11434, router uses 11435)";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind the router service";
    };

    ollamaEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434";
      description = "Local Ollama endpoint";
    };

    routing = {
      strategy = lib.mkOption {
        type = lib.types.enum ["local-first" "cloud-first" "cost-optimized" "latency-optimized"];
        default = "local-first";
        description = ''
          Routing strategy:
          - local-first: Always try local, fallback to cloud on failure
          - cloud-first: Prefer cloud for large models, local for small
          - cost-optimized: Minimize cloud API costs
          - latency-optimized: Choose fastest option based on history
        '';
      };

      localTimeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Timeout in seconds for local model requests before fallback";
      };

      cloudTimeout = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Timeout in seconds for cloud API requests";
      };
    };

    modelMappings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          local = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Local Ollama model name";
          };
          cloud = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Cloud model name (provider:model format, e.g., openai:gpt-4o)";
          };
          preferLocal = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Prefer local model if available";
          };
        };
      });
      default = {};
      example = {
        "gpt-4" = {
          local = "llama3:70b";
          cloud = "openai:gpt-4o";
          preferLocal = true;
        };
        "claude" = {
          local = "llama3.2:3b";
          cloud = "anthropic:claude-sonnet-4-5-20250929";
          preferLocal = true;
        };
      };
      description = "Model mappings between local and cloud providers";
    };

    logging = {
      level = lib.mkOption {
        type = lib.types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
        default = "INFO";
        description = "Logging level for the router service";
      };

      logRequests = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Log all routing decisions and requests";
      };
    };
  };
}
