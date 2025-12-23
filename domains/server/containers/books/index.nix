{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.containers.books;
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
        assertion = cfg.network.mode != "vpn" || config.hwc.server.containers.gluetun.enable;
        message = "books container with VPN mode requires gluetun to be enabled";
      }
      {
        assertion = config.hwc.paths.hot.root != null;
        message = "books container requires hwc.paths.hot.root for downloads";
      }
      {
        assertion = config.hwc.paths.media.root != null;
        message = "books container requires hwc.paths.media.root for book library";
      }
    ];
  };
}
