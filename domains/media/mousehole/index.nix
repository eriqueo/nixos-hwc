# domains/media/mousehole/index.nix
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.media.mousehole;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.mousehole = {
    enable = lib.mkEnableOption "Mousehole - MyAnonamouse seedbox IP updater";
    image = lib.mkOption { type = lib.types.str; default = "tmmrtn/mousehole:latest"; description = "Container image for Mousehole"; };
    port = lib.mkOption { type = lib.types.int; default = 5010; description = "Port for Mousehole web UI"; };
    checkInterval = lib.mkOption { type = lib.types.int; default = 300; description = "Interval in seconds between IP checks"; };
    staleResponseSeconds = lib.mkOption { type = lib.types.int; default = 86400; description = "How long a MAM response is considered valid"; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.networking.gluetun.enable;
        message = "mousehole requires gluetun to be enabled (runs inside VPN tunnel)";
      }
    ];
  };
}
