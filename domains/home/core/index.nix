# domains/home/core/index.nix
#
# Home Core Domain Aggregator
# Automatically imports all core home modules

{ lib, osConfig ? {}, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./xdg-dirs.nix
    ./shell/index.nix
    ./development/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

}
