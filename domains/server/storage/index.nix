{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.storage;
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
  config = lib.mkIf cfg.enable { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = lib.optionals cfg.enable [
    {
      assertion = config.hwc.paths.hot != null;
      message = "Storage automation requires hwc.paths.hot to be configured";
    }
  ];
}