{ lib, config, pkgs, ... }:
{
  imports = [
    ./options.nix
    ./parts/config.nix
    ./parts/lib.nix
  ];
}
