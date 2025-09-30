# domains/server/ai/ai-bible/options.nix
#
# Consolidated options for AI Bible subdomain
# Charter-compliant: ALL ai-bible options defined here

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.services.aiBible = {
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

      categories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "system_architecture"
          "container_services"
          "hardware_gpu"
          "monitoring_observability"
          "storage_data"
        ];
        description = "Documentation categories";
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