# domains/home/apps/fabric/options.nix
#
# Fabric CLI for user environment - Configuration options
{ lib, ...}:
with lib;
{
  options.hwc.home.apps.fabric-bak = {
    enable = mkEnableOption "Fabric CLI for user environment";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Fabric package to use. If null, will use flake input.";
    };

    provider = mkOption {
      type = types.enum [ "openai" "anthropic" "gemini" "ollama" "together" "venice" "openai-compatible" ];
      default = "openai";
      description = "AI provider to use";
    };

    model = mkOption {
      type = types.str;
      default = "gpt-4o-mini";
      description = "Model to use for AI processing";
    };

    env = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for Fabric";
      example = {
        FABRIC_API_URL = "https://hwc.ocelot-wahoo.ts.net";
      };
    };

    initPatterns = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to initialize Fabric patterns on first activation";
    };
  };
}
