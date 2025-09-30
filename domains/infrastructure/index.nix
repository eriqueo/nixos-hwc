# domains/infrastructure/index.nix
#
# Infrastructure Domain aggregator
# Imports all infrastructure subdomain aggregators

{ lib, ... }:

{
  imports = [
    ./hardware/index.nix  # Hardware subdomain (GPU, peripherals, virtualization, storage, permissions)
    ./session/index.nix   # Session subdomain (user services, shared commands)
    ./mesh/index.nix      # Mesh subdomain (container networking)
  ];
}
