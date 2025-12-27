# domains/server/fabric-api/options.nix
#
# Fabric REST API service - Configuration options
{ lib, ... }:
with lib;
{
  options.hwc.server.native.fabric-api = {
    enable = mkEnableOption "Fabric REST API service";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Fabric package to use. If null, will use flake input.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen on";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };

    envFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to environment file containing API keys";
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port";
    };
  };
}
