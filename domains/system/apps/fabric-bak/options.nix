# domains/system/apps/fabric/options.nix
#
# Fabric system façade - Unified configuration interface
{ lib, ... }:
with lib;
{
  options.hwc.system.apps.fabric = {
    enableHome = mkEnableOption "Fabric CLI for user environment (Home Manager)";
    enableApi = mkEnableOption "Fabric REST API service (systemd)";

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
      description = "Additional environment variables for Fabric CLI";
    };

    initPatterns = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to initialize Fabric patterns on first activation (CLI only)";
    };

    api = {
      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address for API to listen on";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for API to listen on";
      };

      envFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to environment file containing API keys";
      };

      extraEnv = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for API";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to open the firewall port for API";
      };
    };
  };
}
