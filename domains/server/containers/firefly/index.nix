# domains/server/containers/firefly/index.nix
#
# Firefly III Personal Finance Manager
# Includes both Firefly III core and Firefly-Pico mobile companion
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.containers.firefly;
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
  config = lib.mkIf cfg.enable { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Assertions are defined in parts/config.nix alongside the implementation
}
