{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.jellyfin;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  #==========================================================================
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [];
  };
}
