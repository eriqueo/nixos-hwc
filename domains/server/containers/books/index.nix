{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.services.containers.books;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
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
        assertion = cfg.network.mode != "vpn" || config.hwc.services.containers.gluetun.enable;
        message = "books container with VPN mode requires gluetun to be enabled";
      }
      {
        assertion = config.hwc.paths.hot != null;
        message = "books container requires hwc.paths.hot for downloads";
      }
      {
        assertion = config.hwc.paths.media != null;
        message = "books container requires hwc.paths.media for book library";
      }
    ];
  };
}
