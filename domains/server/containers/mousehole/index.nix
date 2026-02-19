# domains/server/containers/mousehole/index.nix
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.containers.mousehole;
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
        assertion = config.hwc.server.containers.gluetun.enable;
        message = "mousehole requires gluetun to be enabled (runs inside VPN tunnel)";
      }
    ];
  };
}
