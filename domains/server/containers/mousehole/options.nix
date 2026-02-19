# domains/server/containers/mousehole/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.mousehole = {
    enable = mkEnableOption "Mousehole - MyAnonamouse seedbox IP updater";

    image = mkOption {
      type = types.str;
      default = "tmmrtn/mousehole:latest";
      description = "Container image for Mousehole";
    };

    port = mkOption {
      type = types.int;
      default = 5010;
      description = "Port for Mousehole web UI";
    };

    checkInterval = mkOption {
      type = types.int;
      default = 300;
      description = "Interval in seconds between IP checks";
    };

    staleResponseSeconds = mkOption {
      type = types.int;
      default = 86400;
      description = "How long a MAM response is considered valid (seconds)";
    };
  };
}
