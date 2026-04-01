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
    ./shell.nix
    ./development.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

}
