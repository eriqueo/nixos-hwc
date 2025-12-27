# domains/server/business/index.nix
#
# Business subdomain aggregator
# Imports options and business API implementation

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    # TODO: Fix business-api.nix - wrong namespace and structure
    # ./parts/business-api.nix
  ];
}