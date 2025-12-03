{ lib, ... }:

{
  options.hwc.ai.cloud = {
    enable = lib.mkEnableOption "Cloud AI API integration (OpenAI, Anthropic, etc.)";

    openai = {
      enable = lib.mkEnableOption "OpenAI API integration";

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing OpenAI API key";
      };

      organization = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OpenAI organization ID (optional)";
      };

      defaultModel = lib.mkOption {
        type = lib.types.str;
        default = "gpt-4o";
        description = "Default OpenAI model to use";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "https://api.openai.com/v1";
        description = "OpenAI API endpoint (for proxies or compatible APIs)";
      };
    };

    anthropic = {
      enable = lib.mkEnableOption "Anthropic API integration";

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing Anthropic API key";
      };

      defaultModel = lib.mkOption {
        type = lib.types.str;
        default = "claude-sonnet-4-5-20250929";
        description = "Default Anthropic model to use";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "https://api.anthropic.com/v1";
        description = "Anthropic API endpoint";
      };
    };

    fallback = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable automatic fallback to cloud when local models unavailable";
      };

      preferLocal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Always try local models first before falling back to cloud";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Timeout in seconds before falling back to cloud (if preferLocal=true)";
      };
    };
  };
}
