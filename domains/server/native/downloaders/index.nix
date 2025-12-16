# domains/server/downloaders/index.nix
#
# Downloaders subdomain aggregator
# Imports options and downloaders implementation

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/downloaders.nix
  ];
}