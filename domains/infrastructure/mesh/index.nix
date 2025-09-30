# domains/infrastructure/mesh/index.nix
#
# Mesh subdomain aggregator
# Imports options and all mesh implementation parts

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/container-networking.nix
  ];
}