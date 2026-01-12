{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.storage;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./parts/cleanup.nix
    ./parts/monitoring.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # No validation required - paths.nix always provides non-null paths
  };
}