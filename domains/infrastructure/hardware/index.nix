# domains/infrastructure/hardware/index.nix
{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/gpu.nix
    ./parts/peripherals.nix
  ];
}
