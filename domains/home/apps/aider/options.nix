{ lib, osConfig ? {}, ... }:

with lib;
{
  options.hwc.home.apps.aider = {
    enable = mkEnableOption "aider AI pair-programming CLI";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Aider package to use. If null, auto-detect from nixpkgs.";
    };

    cloudModel = mkOption {
      type = types.str;
      default = "openai/gpt-4o-mini";
      description = "Default cloud model for aider.";
    };

    localModel = mkOption {
      type = types.str;
      default = "ollama/llama3.2:3b";
      description = "Default local model for aider via Ollama.";
    };

    ollamaApiBase = mkOption {
      type = types.str;
      default = "http://127.0.0.1:11434";
      description = "Ollama API base URL used by aider for local models.";
    };

    extraAliases = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        fast = "openai/gpt-4o-mini";
        deep = "anthropic/claude-sonnet-4-5";
      };
      description = "Additional aider model aliases in name -> model format.";
    };
  };
}
