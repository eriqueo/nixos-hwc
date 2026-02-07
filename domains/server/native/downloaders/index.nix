# domains/server/downloaders/index.nix
#
# Downloaders subdomain aggregator
# Imports options and downloaders implementation

{ lib, config, pkgs, ... }:

{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    (lib.mkRenamedOptionModule [ "hwc" "services" "media" "downloaders" ] [ "hwc" "server" "native" "downloaders" ])
    (lib.mkRenamedOptionModule [ "hwc" "services" "downloaders" ] [ "hwc" "server" "native" "downloaders" ])
    ./options.nix
    ./parts/downloaders.nix
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
