# domains/system/index.nix — domain aggregator
{ ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./core/index.nix
    ./networking/index.nix  # Promoted from services/ per Charter v10.3
    ./services/index.nix
    ./storage/index.nix
    ./users/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
