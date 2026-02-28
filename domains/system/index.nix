# domains/system/index.nix — domain aggregator
{ ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./core/index.nix
    ./hardware/index.nix       # NEW: GPU, peripherals (migrated from infrastructure)
    ./networking/index.nix     # Promoted from services/ per Charter v10.3
    ./services/index.nix
    ./storage/index.nix
    ./users/index.nix
    ./virtualization/index.nix # NEW: VMs, containers (migrated from infrastructure)
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
