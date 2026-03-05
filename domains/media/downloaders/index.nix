# domains/media/downloaders/index.nix
#
# Downloaders subdomain aggregator
# Namespace: hwc.media.downloaders.*

{ lib, config, pkgs, ... }:

{
  imports = [
    ./options.nix
    ./parts/downloaders.nix
  ];
}
