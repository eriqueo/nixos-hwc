# domains/server/apps/fabric-api/options.nix
#
# OPTIONS: Fabric REST API service
# Namespace: hwc.server.apps.fabricApi.*

{ lib, ... }:
with lib;
{
  options.hwc.server.apps.fabricApi = {
    enable = mkEnableOption "Fabric REST API service";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Package to use; defaults to Fabric flake package if null.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen on (127.0.0.1 for localhost only)";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };

    envFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to environment file containing API keys (from agenix)";
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open firewall port (only if listenAddress != 127.0.0.1)";
    };
  };
}
