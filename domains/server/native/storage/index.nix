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
  config = lib.mkIf cfg.enable {
    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.paths.hot.root != null;
        message = "Storage automation requires hwc.paths.hot.root to be configured";
      }
    ];
  };
}