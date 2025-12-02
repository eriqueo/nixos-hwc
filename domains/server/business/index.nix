# domains/server/business/default.nix
#
# Business subdomain aggregator
# Imports options and business API implementation

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/business-api.nix
  ];
}