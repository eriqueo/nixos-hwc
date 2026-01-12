# domains/server/ai/ai-bible/options.nix
#
# Consolidated options for AI Bible subdomain
# Charter-compliant: ALL ai-bible options defined here

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.server.aiBible = {
    enable = lib.mkEnableOption "AI Bible documentation system";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "API port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/ai-bible";
      description = "Data directory for AI Bible";
    };

    #==========================================================================
    # FEATURES
    #==========================================================================
    features = {
      autoGeneration = lib.mkEnableOption "Auto documentation generation";

      llmIntegration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable LLM integration";
      };

      webApi = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable web API for querying documentation";
      };

      categories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "system_architecture"
          "container_services"
          "hardware_gpu"
          "monitoring_observability"
          "storage_data"
          "networking"
          "backup"
        ];
        description = "Documentation categories";
      };
    };

    #==========================================================================
    # CODEBASE ANALYSIS
    #==========================================================================
    codebase = {
      rootPath = lib.mkOption {
        type = lib.types.path;
        default = /etc/nixos;
        description = "Root path of NixOS configuration to analyze";
      };

      scanInterval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "How often to scan codebase for changes";
      };

      excludePaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ".git" "result" ".direnv" ];
        description = "Paths to exclude from analysis";
      };
    };

    #==========================================================================
    # LLM CONFIGURATION
    #==========================================================================
    llm = {
      provider = lib.mkOption {
        type = lib.types.enum [ "ollama" "openai" "anthropic" ];
        default = "ollama";
        description = "LLM provider to use";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "llama2";
        description = "LLM model to use";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:11434";
        description = "LLM API endpoint";
      };
    };
  };
}