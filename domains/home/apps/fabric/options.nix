# domains/home/apps/fabric/options.nix
#
# OPTIONS: Fabric CLI for user environment
# Namespace: hwc.home.apps.fabric.*

{ lib, ... }:
with lib;
{
  options.hwc.home.apps.fabric = {
    enable = mkEnableOption "Fabric CLI for user environment";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Package to use; defaults to Fabric flake package if null.";
    };

    provider = mkOption {
      type = types.enum [ "openai" "anthropic" "gemini" "ollama" "together" "venice" "openai-compatible" ];
      default = "openai";
      description = "AI provider to use (openai, anthropic, gemini, ollama, together, venice, openai-compatible)";
    };

    model = mkOption {
      type = types.str;
      default = "gpt-4o-mini";
      description = "Model to use with the provider";
    };

    env = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables for Fabric";
    };

    initPatterns = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to initialize Fabric patterns on first activation";
    };
  };
}
