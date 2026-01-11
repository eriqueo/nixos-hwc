# domains/home/apps/codex/options.nix
#
# OpenAI Codex CLI - Configuration options
{ lib, osConfig ? {}, ... }:
with lib;
{
  options.hwc.home.apps.codex = {
    enable = mkEnableOption "OpenAI Codex CLI for user environment";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Codex package to use. If null, will use flake input.";
    };

    env = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for Codex CLI";
      example = {
        OPENAI_API_KEY = "sk-...";
      };
    };
  };
}