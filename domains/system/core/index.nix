# modules/system/core/index.nix — aggregates core system functionality
{ ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./packages.nix
    # paths.nix moved to domains/paths/paths.nix (Primitive Module)
    ../../paths/paths.nix
    ./filesystem.nix
    ./thermal.nix
    ./validation.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = [];
}
