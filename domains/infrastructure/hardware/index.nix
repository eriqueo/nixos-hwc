# domains/infrastructure/hardware/index.nix
#
# Hardware subdomain aggregator
# Imports options and all hardware implementation parts

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/gpu.nix
    ./parts/peripherals.nix
    ./parts/virtualization.nix
    ./parts/storage.nix
    ./parts/permissions.nix
  ];
}