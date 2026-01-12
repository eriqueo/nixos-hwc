# domains/server/business/index.nix
#
# Business subdomain aggregator
# Imports options and business API implementation

{ lib, config, pkgs, ... }:

{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    # TODO: Fix business-api.nix - wrong namespace and structure
    # ./parts/business-api.nix
  ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}