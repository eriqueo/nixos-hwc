# domains/system/apps/fabric/options.nix
#
# OPTIONS: Fabric system façade (unified configuration interface)
# Namespace: hwc.system.apps.fabric.*

{ lib, ... }:
with lib;
{
  options.hwc.system.apps.fabric = {
    enableHome = mkEnableOption "Enable Fabric CLI in the user environment via Home Manager";
    enableApi = mkEnableOption "Enable Fabric REST API as a systemd service";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Package to use for both home and API; defaults to Fabric flake package if null.";
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
      description = "Additional environment variables for Fabric (shared by home and API)";
    };

    initPatterns = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to initialize Fabric patterns on first home activation";
    };

    api = {
      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address for API to listen on (127.0.0.1 for localhost only)";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for API to listen on";
      };

      envFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to environment file containing API keys (from agenix)";
      };

      extraEnv = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Additional environment variables for API only";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to open firewall port for API (only if listenAddress != 127.0.0.1)";
      };
    };
  };
}
