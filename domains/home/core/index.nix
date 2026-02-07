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
    ./options.nix
    ./xdg-dirs.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

}
