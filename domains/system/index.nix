# domains/system/index.nix — domain aggregator
{ ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./core/index.nix           # OS primitives: identity, shell, session, polkit, packages
    ./hardware/index.nix       # GPU, peripherals, audio, fan control
    ./networking/index.nix     # OS-level networking (interfaces, firewall, resolved)
    ./mounts/index.nix         # Filesystem mounts, storage tiers, external drives
    ./users/index.nix          # User accounts and groups
    ./virtualization/index.nix # VMs, container runtime
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
