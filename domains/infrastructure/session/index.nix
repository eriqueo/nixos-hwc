# domains/infrastructure/session/index.nix
#
# Session subdomain aggregator
# Imports options and all session implementation parts

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/services.nix
    ./parts/commands.nix
  ];
}