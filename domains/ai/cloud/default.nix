{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.cloud;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    # Environment variables for cloud API configuration
    # These will be available to AI services that need cloud access
    environment.sessionVariables = lib.mkMerge [
      (lib.mkIf cfg.openai.enable {
        OPENAI_API_ENDPOINT = cfg.openai.endpoint;
        OPENAI_DEFAULT_MODEL = cfg.openai.defaultModel;
      })

      (lib.mkIf (cfg.openai.enable && cfg.openai.organization != null) {
        OPENAI_ORGANIZATION = cfg.openai.organization;
      })

      (lib.mkIf cfg.anthropic.enable {
        ANTHROPIC_API_ENDPOINT = cfg.anthropic.endpoint;
        ANTHROPIC_DEFAULT_MODEL = cfg.anthropic.defaultModel;
      })
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (cfg.openai.enable || cfg.anthropic.enable);
        message = "hwc.ai.cloud enabled but no providers configured. Enable at least one provider (openai or anthropic).";
      }
      {
        assertion = !cfg.openai.enable || (cfg.openai.apiKeyFile != null);
        message = "hwc.ai.cloud.openai enabled but apiKeyFile not set. Provide path to OpenAI API key file.";
      }
      {
        assertion = !cfg.anthropic.enable || (cfg.anthropic.apiKeyFile != null);
        message = "hwc.ai.cloud.anthropic enabled but apiKeyFile not set. Provide path to Anthropic API key file.";
      }
      {
        assertion = !cfg.openai.enable || (builtins.pathExists cfg.openai.apiKeyFile || true);
        message = "hwc.ai.cloud.openai.apiKeyFile path does not exist: ${toString cfg.openai.apiKeyFile}";
      }
      {
        assertion = !cfg.anthropic.enable || (builtins.pathExists cfg.anthropic.apiKeyFile || true);
        message = "hwc.ai.cloud.anthropic.apiKeyFile path does not exist: ${toString cfg.anthropic.apiKeyFile}";
      }
    ];

    warnings = lib.optionals cfg.enable [
      ''
        Cloud AI APIs enabled. Remember:
        - API keys should be stored in agenix secrets
        - Cloud APIs incur usage costs
        - Local-first philosophy: prefer Ollama when possible
        ${lib.optionalString cfg.fallback.enable "- Automatic fallback to cloud is enabled"}
      ''
    ];
  };
}
