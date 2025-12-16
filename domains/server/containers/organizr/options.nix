# modules/server/containers/organizr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.organizr = {
    enable = mkEnableOption "Organizr unified dashboard";

    image = mkOption {
      type = types.str;
      default = "organizr/organizr:latest";
      description = "Container image for Organizr";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode";
    };

    webPort = mkOption {
      type = types.port;
      default = 9983;
      description = "Web UI port";
    };

    gpu.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GPU acceleration (not typically needed for Organizr)";
    };
  };
}
