# domains/server/networking/index.nix
#
# Server networking subdomain aggregator
# Imports options and networking implementation files

{ lib, config, pkgs, ... }:

{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./parts/vpn.nix
    ./parts/ntfy.nix
    ./parts/transcript-api.nix
    ./parts/yt-transcripts-api
    ./parts/yt-videos-api
    ./parts/databases.nix
    ./parts/networking.nix
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